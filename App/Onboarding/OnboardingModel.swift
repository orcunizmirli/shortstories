import AppFoundation
import ContentKit
import Foundation
import Observation
import ProfileKit

/// SS-064 — Onboarding adım durum makinesi + izin orkestrasyonu (2-3 adım: dil → tür (atlanabilir) →
/// bildirim izni + ATT). Kanon §3 / 01 ONB-03/04/05 / 02 §4.2 / 08 §3.1 & §9.1.
///
/// Tasarım: İNCE view'lar; TÜM akış kararı burada. Dış sistemler (bildirim izni, ATT) port arkasında
/// (`NotificationAuthorizationRequesting`/`AppTrackingRequesting`) → testler gerçek sistem izni olmadan
/// koşar. Dil `OnboardingLanguageWriting` (canlı: ProfileKit `LanguagePreferenceService`), tür seçimi
/// `PreferencesStoring`'e persist edilir. Analitik adları 08 registry ile birebir.
///
/// İzin sırası ZORUNLU (01 ONB-05, 08 §9.1): önce değer önerisi ekranı, SONRA bildirim ön-izni, SONRA
/// (bayrak açık + ATT `.notDetermined` ise) ATT ön-izni — asla dil/tür adımı sırasında değil.
@Observable
@MainActor
final class OnboardingModel {
    /// Kanonik onboarding adımı (08 §3.1 `step` + `step_index`).
    enum Step: Int, CaseIterable, Sendable {
        case language = 0
        case genre = 1
        case permissions = 2

        /// `onboarding_step_view.step` kanonik değeri.
        var analyticsKey: String {
            switch self {
            case .language: "language"
            case .genre: "genre"
            case .permissions: "permissions"
            }
        }
    }

    /// İzin adımının (adım 3) iç alt-fazları — değer önerisi → bildirim ön-izni → ATT ön-izni.
    enum PermissionsPhase: Equatable, Sendable {
        case valueProposition
        case notificationPrePrompt
        case trackingPrePrompt
    }

    /// Bildirim izni sonucu (verildi/reddedildi/ertelendi) — "ertelendi" ön-izinde "Şimdi değil"dir:
    /// sistem diyaloğu HİÇ tetiklenmez (hak yakılmaz, 01 ONB-05).
    enum NotificationOutcome: Equatable, Sendable {
        case pending
        case granted
        case denied
        case deferred
    }

    /// Akışın bitiş biçimi — routing (Faz 2) buna göre yönlendirir; ikisinde de onboarding bir daha gösterilmez.
    enum Completion: Equatable, Sendable {
        case completed
        case skipped
    }

    // MARK: - Gözlemlenen durum

    private(set) var step: Step = .language
    private(set) var permissionsPhase: PermissionsPhase = .valueProposition
    private(set) var selectedLanguage: AppLanguage
    private(set) var selectedGenreIDs: Set<String> = []
    private(set) var notificationOutcome: NotificationOutcome = .pending
    private(set) var trackingOutcome: AppTrackingAuthorizationResult?
    /// `nil` iken onboarding sürüyor; `.completed`/`.skipped` olunca bitti.
    private(set) var completion: Completion?

    let languageOptions: [AppLanguage]
    let genreOptions: [Genre]

    // MARK: - Bağımlılıklar (dar portlar)

    private let language: any OnboardingLanguageWriting
    private let preferences: any PreferencesStoring
    private let notifications: any NotificationAuthorizationRequesting
    /// APNs uzak-bildirim kaydı tetikleyicisi (SS-140): bildirim izni VERİLİNCE `registerForRemote
    /// Notifications()` çağrılır → token akışı başlar. İzin verilmezse çağrılmaz (izin yoksa kayıt yok).
    /// Opsiyonel: onboarding testleri (izin akışı) bunu enjekte etmeden koşabilir.
    private let remoteNotifications: (any RemoteNotificationRegistering)?
    private let tracking: any AppTrackingRequesting
    private let analytics: any AnalyticsTracking
    /// ATT istemi bayrağı (08 §9.1) — kapalıysa ATT adımı hiç gösterilmez, event üretilmez.
    private let attEnabled: Bool
    private let now: () -> Date
    private let onFinish: (@MainActor (Completion) -> Void)?

    private var startedAt: Date?
    private var didStart = false

    init(
        initialLanguage: AppLanguage,
        languageOptions: [AppLanguage] = LanguageCatalog.supportedAppLanguages,
        genreOptions: [Genre],
        language: any OnboardingLanguageWriting,
        preferences: any PreferencesStoring,
        notifications: any NotificationAuthorizationRequesting,
        tracking: any AppTrackingRequesting,
        analytics: any AnalyticsTracking,
        attEnabled: Bool,
        remoteNotifications: (any RemoteNotificationRegistering)? = nil,
        now: @escaping () -> Date = { Date() },
        onFinish: (@MainActor (Completion) -> Void)? = nil
    ) {
        selectedLanguage = initialLanguage
        self.languageOptions = languageOptions
        self.genreOptions = genreOptions
        self.language = language
        self.preferences = preferences
        self.notifications = notifications
        self.remoteNotifications = remoteNotifications
        self.tracking = tracking
        self.analytics = analytics
        self.attEnabled = attEnabled
        self.now = now
        self.onFinish = onFinish
    }

    // MARK: - Yaşam döngüsü

    /// İlk adım görünür olunca çağrılır (view `.task`). Idempotent: `onboarding_start` yalnız bir kez.
    func start() {
        guard !didStart else { return }
        didStart = true
        startedAt = now()
        analytics.track("onboarding_start", parameters: [:])
        trackStepView(step)
    }

    // MARK: - Adım 1: dil

    /// Dil seçimini günceller (henüz commit ETMEZ — commit `advance()`te). Ön-seçim cihaz dilidir (ONB-03).
    func selectLanguage(_ value: AppLanguage) {
        selectedLanguage = value
    }

    // MARK: - Adım 2: tür (atlanabilir)

    func isGenreSelected(_ id: String) -> Bool {
        selectedGenreIDs.contains(id)
    }

    func toggleGenre(_ id: String) {
        if selectedGenreIDs.contains(id) {
            selectedGenreIDs.remove(id)
        } else {
            selectedGenreIDs.insert(id)
        }
    }

    /// Tür adımını ATLA (kişiselleştirmesiz devam) — `onboarding_genre_select` GÖNDERİLMEZ (08 §3.1),
    /// tür tercihi persist edilmez. İzin adımına geçer.
    func skipGenreStep() {
        guard step == .genre else { return }
        goToPermissions()
    }

    // MARK: - İleri / geri (birincil "Devam")

    /// Mevcut adımı işleyip ileri taşır. Dil: commit + `onboarding_language_select`. Tür: seçim varsa
    /// persist + `onboarding_genre_select`. İzin adımı alt-faz makinesiyle sürer → burada no-op.
    func advance() {
        switch step {
        case .language:
            commitLanguage()
            goToGenre()
        case .genre:
            commitGenresIfAny()
            goToPermissions()
        case .permissions:
            break
        }
    }

    /// Bir önceki adıma döner (dil/tür seçimleri korunur). Adım tekrar görünür olduğundan `step_view` yeniden atılır.
    func back() {
        switch step {
        case .language:
            break
        case .genre:
            step = .language
            trackStepView(.language)
        case .permissions:
            step = .genre
            permissionsPhase = .valueProposition
            trackStepView(.genre)
        }
    }

    /// Akışı TAMAMEN atlar (flow-abandon) — `onboarding_skip {skipped_at_step}` atar, bayrağı işaretler.
    func skip() {
        guard completion == nil else { return }
        analytics.track("onboarding_skip", parameters: [
            "skipped_at_step": .string(step.analyticsKey)
        ])
        finish(.skipped)
    }

    // MARK: - Adım 3: izinler (değer önerisi → bildirim → ATT)

    /// Değer önerisi ekranından bildirim ön-iznine geçer.
    func continueFromValueProposition() {
        guard step == .permissions, permissionsPhase == .valueProposition else { return }
        permissionsPhase = .notificationPrePrompt
    }

    /// Ön-izinde "Bildirimleri Aç": sistem diyaloğunu tetikler, sonucu (`grant`/`deny`) loglar.
    func requestNotificationAuthorization() async {
        guard step == .permissions, permissionsPhase == .notificationPrePrompt else { return }
        let result = await notifications.requestAuthorization()
        notificationOutcome = (result == .granted) ? .granted : .denied
        analytics.track("onboarding_push_prompt", parameters: [
            "action": .string(result == .granted ? "grant" : "deny")
        ])
        // SS-140: izin VERİLDİYSE APNs kaydını tetikle (token akışı → POST /devices); reddedilirse
        // kayıt YOK. Kayıt asenkron sürer; sonuç `AppDelegate.didRegister...` → `DeviceTokenRegistering`.
        if result == .granted {
            remoteNotifications?.registerForRemoteNotifications()
        }
        proceedAfterNotifications()
    }

    /// Ön-izinde "Şimdi değil": sistem diyaloğu HİÇ tetiklenmez (hak yakılmaz) → `onboarding_push_prompt` YOK.
    func deferNotifications() {
        guard step == .permissions, permissionsPhase == .notificationPrePrompt else { return }
        notificationOutcome = .deferred
        proceedAfterNotifications()
    }

    /// ATT ön-izninde "Devam": sistem ATT diyaloğunu tetikler, sonucu loglar, akışı tamamlar.
    func requestAppTracking() async {
        guard step == .permissions, permissionsPhase == .trackingPrePrompt else { return }
        let result = await tracking.requestAuthorization()
        trackingOutcome = result
        analytics.track("onboarding_att_prompt", parameters: [
            "action": .string(result.analyticsAction)
        ])
        complete()
    }

    /// ATT ön-izninde "Şimdi değil": sistem ATT diyaloğu gösterilmez → `onboarding_att_prompt` YOK; akış tamamlanır.
    func deferTracking() {
        guard step == .permissions, permissionsPhase == .trackingPrePrompt else { return }
        complete()
    }

    // MARK: - Özel

    private func trackStepView(_ step: Step) {
        analytics.track("onboarding_step_view", parameters: [
            "step": .string(step.analyticsKey),
            "step_index": .int(step.rawValue)
        ])
    }

    private func commitLanguage() {
        language.setAppLanguage(selectedLanguage)
        analytics.track("onboarding_language_select", parameters: [
            "language": .string(selectedLanguage.code)
        ])
    }

    private func goToGenre() {
        step = .genre
        trackStepView(.genre)
    }

    private func commitGenresIfAny() {
        guard !selectedGenreIDs.isEmpty else { return }
        // Deterministik sıra: katalog sırasını koru (seçim kümesinin iterasyon sırası değil).
        let ordered = genreOptions.map(\.id).filter(selectedGenreIDs.contains)
        let joined = ordered.joined(separator: ",")
        preferences.set(joined, for: OnboardingPreferenceKeys.selectedGenres)
        analytics.track("onboarding_genre_select", parameters: [
            "genres": .string(joined),
            "genre_count": .int(ordered.count)
        ])
    }

    private func goToPermissions() {
        step = .permissions
        permissionsPhase = .valueProposition
        trackStepView(.permissions)
    }

    /// Bildirim kararı sonrası: bayrak açık + ATT henüz belirlenmemişse ATT ön-iznine geç; değilse tamamla
    /// (08 §9.1: ATT global reddedilmiş/kısıtlıysa veya bayrak kapalıysa istem HİÇ gösterilmez).
    private func proceedAfterNotifications() {
        if shouldRequestTracking {
            permissionsPhase = .trackingPrePrompt
        } else {
            complete()
        }
    }

    private var shouldRequestTracking: Bool {
        attEnabled && tracking.currentStatus == .notDetermined
    }

    private func complete() {
        guard completion == nil else { return }
        let elapsed = now().timeIntervalSince(startedAt ?? now())
        analytics.track("onboarding_complete", parameters: [
            "duration_s": .int(max(0, Int(elapsed.rounded())))
        ])
        finish(.completed)
    }

    private func finish(_ completion: Completion) {
        // Onboarding bir daha gösterilmez (kanon §3 / 03 §9 UserDefaults bayrağı) — hem tamamla hem atla.
        preferences.set(true, for: PreferenceKeys.onboardingCompleted)
        self.completion = completion
        onFinish?(completion)
    }
}
