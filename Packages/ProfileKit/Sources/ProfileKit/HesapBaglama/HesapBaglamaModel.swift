import AppFoundation
import Observation

/// Hesap bağlama ekran modeli (SS-132; ONB-06 / App Store 4.8). @Observable/@MainActor; SwiftUI View
/// ince kalır. Misafir → Apple (F1) / Google / e-posta (F2) bağlama — hepsi SAĞLAYICI-BAĞIMSIZ TEK
/// akıştan geçer: kimlik-bilgisi al (`AppleSignInProviding`/`GoogleSignInProviding`/`EmailLinkProviding`)
/// → `LinkCredential`'a sar → backend bağlama (`AccountLinkingServicing`). Başarıda sunucu `userId`'yi
/// korur → bakiye/ilerleme SUNUCU-otoriter korunur, client kaybetmez (§3.3, sıfır-kayıp). Çakışma (409)
/// birleştirme kararını modeller; iptal ve hata ayrı durumlardır. Analitik: `link_account_started/
/// success/failed {provider}` (02 §4.13) — `provider` aktif akıştan türer.
///
/// Durum makinesi: `idle → linking → {linked | conflict | cancelled | failed}`;
/// `conflict → switching → {linked | failed}`. İptal (sağlayıcı sayfası kapatıldı VEYA birleştirme
/// reddedildi) benign'dir — success/failed analitiği ÜRETMEZ (registry yalnız started/success/failed
/// tanımlar; ayrı cancel event'i yoktur).
@MainActor
@Observable
public final class HesapBaglamaModel {
    // MARK: - Durum

    public enum State: Equatable, Sendable {
        case idle
        /// Sağlayıcı sayfası + backend `POST /auth/link` işlemde (Apple/Google/e-posta ortak).
        case linking
        /// 409 — kimlik başka hesaba bağlı; kullanıcı "geç"/"vazgeç" seçer.
        case conflict(AccountLinkConflict)
        /// "Mevcut hesabıma geç" → `POST /auth/switch` işlemde.
        case switching
        /// Bağlandı (oturum bağlıya yükseldi).
        case linked(AccountSummary)
        /// Kullanıcı iptal etti (sağlayıcı sayfası VEYA birleştirme diyaloğu) — sessizce başa dön.
        case cancelled
        /// Ağ/beklenmedik hata — "Tekrar Dene".
        case failed(HesapBaglamaError)

        /// Yeni bir bağlama tetiklenemez (uçuşta) — çift tetik koruması.
        var isBusy: Bool {
            switch self {
            case .linking, .switching: true
            case .idle, .conflict, .linked, .cancelled, .failed: false
            }
        }
    }

    public private(set) var state: State = .idle

    /// En son başlatılan/uçuştaki akışın sağlayıcısı — analitik `provider` + hata mesajı buradan türer.
    /// Yalnız `startXxxLinking` başlangıcında yazılır; çakışma→switch aynı sağlayıcıyı KORUR.
    public private(set) var activeProvider: AuthProvider = .apple

    /// Akış uçuşta mı (spinner + butonlar devre dışı) — durum makinesinin TEK isBusy kaynağı.
    /// View bunu okur; kendi kopyasını türetmez (review #14).
    public var isBusy: Bool {
        state.isBusy
    }

    /// Uçuştaki sağlayıcı (varsa) — View yalnız İLGİLİ butonda spinner gösterir; diğer sağlayıcı
    /// butonları meşgulken spinner göstermeden devre dışı kalır (`nil` ⇒ uçuşta akış yok).
    public var inFlightProvider: AuthProvider? {
        isBusy ? activeProvider : nil
    }

    // MARK: - Bağımlılıklar

    private let appleSignIn: any AppleSignInProviding
    private let googleSignIn: any GoogleSignInProviding
    private let emailLink: any EmailLinkProviding
    private let linking: any AccountLinkingServicing
    private let analytics: any AnalyticsTracking
    private weak var delegate: (any HesapBaglamaDelegate)?

    private var activeTask: Task<Void, Never>?

    public init(
        appleSignIn: any AppleSignInProviding,
        googleSignIn: any GoogleSignInProviding,
        emailLink: any EmailLinkProviding,
        linking: any AccountLinkingServicing,
        analytics: any AnalyticsTracking,
        delegate: (any HesapBaglamaDelegate)?
    ) {
        self.appleSignIn = appleSignIn
        self.googleSignIn = googleSignIn
        self.emailLink = emailLink
        self.linking = linking
        self.analytics = analytics
        self.delegate = delegate
    }

    // MARK: - Testler için deterministik bekleme

    /// Askıdaki bağlama/geçiş görevini bekler (test kancası).
    func pendingWork() async {
        await activeTask?.value
    }

    // MARK: - Akış (sağlayıcıya özel giriş noktaları → ortak akış)

    /// "Apple ile Devam Et" (App Store 4.8 zorunlu; F1'den KORUNUR).
    public func startAppleLinking() {
        begin(.apple)
    }

    /// "Google ile Devam Et" (F2).
    public func startGoogleLinking() {
        begin(.google)
    }

    /// "E-posta ile Devam Et" (F2). Ham parola modelde TUTULMAZ — yalnız akış boyunca porta iletilir.
    public func startEmailLinking(email: String, password: String) {
        begin(.email(email: email, password: password))
    }

    // MARK: - Çakışma çözümü (sağlayıcı-bağımsız)

    /// Çakışma diyaloğu: "Mevcut hesabıma geç" → `POST /auth/switch`.
    public func resolveConflictBySwitching() {
        guard case let .conflict(conflict) = state else { return }
        state = .switching
        activeTask = Task { [weak self] in await self?.performSwitch(conflict) }
    }

    /// Çakışma diyaloğu: "Vazgeç" → başa dön (benign iptal; success/failed ÜRETME).
    public func cancelConflict() {
        guard case .conflict = state else { return }
        state = .cancelled
    }

    /// Hata/iptal ekranından "Tekrar Dene"/kapat sonrası başa dön. Çakışma kararı BEKLERKEN
    /// (`conflict`) NO-OP: bekleyen `AccountLinkConflict`+`switchToken` sessizce düşmez — kullanıcı
    /// çıkış için açıkça `resolveConflictBySwitching`/`cancelConflict` seçer.
    public func reset() {
        guard canRestart else { return }
        state = .idle
    }

    public func dismiss() {
        delegate?.hesapBaglamaRequestsDismiss()
    }

    // MARK: - Ortak akış (SAĞLAYICI-BAĞIMSIZ — tek yer)

    /// Sağlayıcı-bağımsız bağlama isteği: hangi kimliğin nasıl üretileceğini taşır; akış tek yerden
    /// (`performLinking`) koşar. E-posta girdileri burada TAŞINIR (modelde kalıcı parola tutulmaz).
    private enum LinkRequest: Sendable {
        case apple
        case google
        case email(email: String, password: String)

        var provider: AuthProvider {
            switch self {
            case .apple: .apple
            case .google: .google
            case .email: .email
            }
        }
    }

    /// Yalnız yeniden-başlatılabilir durumlardan ilerler: uçuşta (`linking`/`switching`), çakışma
    /// kararı beklerken (`conflict`) ve başarı sonrası (`linked`) NO-OP — çift oturum-yükseltme ve
    /// bekleyen çakışmanın sessizce düşmesi engellenir (SS-132 durum makinesi bütünlüğü).
    private func begin(_ request: LinkRequest) {
        guard canRestart else { return }
        activeProvider = request.provider
        state = .linking
        trackStarted()
        activeTask = Task { [weak self] in await self?.performLinking(request) }
    }

    private func performLinking(_ request: LinkRequest) async {
        let credential: LinkCredential
        do {
            credential = try await fetchCredential(request)
        } catch {
            // İptal benign: success/failed ÜRETME, sessizce başa dön. Gerçek hata → failed.
            if isBenignCancellation(error) {
                state = .cancelled
            } else {
                fail(providerUnavailableError)
            }
            return
        }
        await completeLink(with: credential)
    }

    /// Sağlayıcıya özel TEK adım: kimlik-bilgisi üret, `LinkCredential`'a sar. Ham SDK hatası
    /// (`AppleSignInError`/`GoogleSignInError`/`EmailLinkError`) yukarı çıkar; sınıflandırma ortakta.
    private func fetchCredential(_ request: LinkRequest) async throws -> LinkCredential {
        switch request {
        case .apple: try await .apple(appleSignIn.requestCredential())
        case .google: try await .google(googleSignIn.signIn())
        case let .email(email, password): try await .email(emailLink.linkCredential(email: email, password: password))
        }
    }

    private func completeLink(with credential: LinkCredential) async {
        do {
            let outcome = try await linking.link(credential)
            switch outcome {
            case let .linked(account):
                finishLinked(account)
            case let .conflict(conflict):
                // Kullanıcı kararı beklenir — henüz success/failed yok.
                state = .conflict(conflict)
            }
        } catch {
            fail(.linkFailed)
        }
    }

    private func performSwitch(_ conflict: AccountLinkConflict) async {
        do {
            let account = try await linking.switchToExistingAccount(conflict)
            finishLinked(account)
        } catch {
            fail(.linkFailed)
        }
    }

    // MARK: - İç

    /// Sağlayıcıların benign kullanıcı iptali — success/failed ÜRETMEZ (funnel'a girmez). Diğer tüm
    /// hatalar (SDK/ağ/beklenmedik) gerçek hatadır → `.failed`.
    private func isBenignCancellation(_ error: Error) -> Bool {
        switch error {
        case let error as AppleSignInError: error == .cancelled
        case let error as GoogleSignInError: error == .cancelled
        case let error as EmailLinkError: error == .cancelled
        default: false
        }
    }

    /// Aktif sağlayıcının "giriş tamamlanamadı" hatası (SAF; ham hata SIZMAZ).
    private var providerUnavailableError: HesapBaglamaError {
        switch activeProvider {
        case .apple: .appleUnavailable
        case .google: .googleUnavailable
        case .email: .emailUnavailable
        }
    }

    /// Yeni akış başlatma/sıfırlama İZİN durumu — terminal-olmayan-meşgul + başarı + çakışma kararı
    /// beklerken kilitli. Yalnız `idle`/benign-iptal/hata'dan yeni akış açılır. `isBusy` (spinner)
    /// yalnız uçuşu kapsarken bu kapı ek olarak `conflict` (karar bekliyor) ve `linked` (terminal-başarı)
    /// durumlarını da kilitler → çift didLink ve çakışma kaybı önlenir.
    private var canRestart: Bool {
        switch state {
        case .idle, .cancelled, .failed: true
        case .linking, .switching, .conflict, .linked: false
        }
    }

    private func finishLinked(_ account: AccountSummary) {
        state = .linked(account)
        trackSuccess()
        delegate?.hesapBaglamaDidLink(account)
    }

    private func fail(_ error: HesapBaglamaError) {
        state = .failed(error)
        trackFailed()
    }

    // MARK: - Analitik (02 §4.13) — provider aktif akıştan

    private func trackStarted() {
        analytics.track("link_account_started", parameters: providerParameters)
    }

    private func trackSuccess() {
        analytics.track("link_account_success", parameters: providerParameters)
    }

    private func trackFailed() {
        analytics.track("link_account_failed", parameters: providerParameters)
    }

    private var providerParameters: [String: AnalyticsValue] {
        ["provider": .string(activeProvider.rawValue)]
    }
}

/// Bağlama ekranının kullanıcıya gösterdiği SAF hata sınıflandırması — ham `AppError`/
/// `ASAuthorizationError`/`GIDSignInError`/`APIErrorBody` SIZMAZ; View tek cümle mesaj seçer.
public enum HesapBaglamaError: Equatable, Sendable {
    /// Apple girişi başlatılamadı/başarısız.
    case appleUnavailable
    /// Google girişi başlatılamadı/başarısız.
    case googleUnavailable
    /// E-posta bağlama başlatılamadı/başarısız.
    case emailUnavailable
    /// Backend bağlama başarısız (ağ/5xx/beklenmedik).
    case linkFailed
}
