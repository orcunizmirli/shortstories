import AppFoundation
import Observation

/// Hesap bağlama ekran modeli (SS-132; ONB-06 / App Store 4.8). @Observable/@MainActor; SwiftUI View
/// ince kalır. Misafir → Sign in with Apple akışı: Apple kimlik-bilgisi (`AppleSignInProviding`) →
/// backend bağlama (`AccountLinkingServicing`). Başarıda sunucu `userId`'yi korur → bakiye/ilerleme
/// SUNUCU-otoriter korunur, client kaybetmez (§3.3). Çakışma (409) birleştirme kararını modeller;
/// iptal ve hata ayrı durumlardır. Analitik: `link_account_started/success/failed {provider}` (02 §4.13).
///
/// Durum makinesi: `idle → linking → {linked | conflict | cancelled | failed}`;
/// `conflict → switching → {linked | failed}`. İptal (Apple sayfası kapatıldı VEYA birleştirme
/// reddedildi) benign'dir — success/failed analitiği ÜRETMEZ (registry yalnız started/success/failed
/// tanımlar; ayrı cancel event'i yoktur).
@MainActor
@Observable
public final class HesapBaglamaModel {
    /// Ekran değişmez tanımı: F1'de yalnız Apple bağlanır (Google/e-posta F2). Analitik `provider`.
    public static let provider: AuthProvider = .apple

    // MARK: - Durum

    public enum State: Equatable, Sendable {
        case idle
        /// Apple sayfası + backend `POST /auth/link` işlemde.
        case linking
        /// 409 — kimlik başka hesaba bağlı; kullanıcı "geç"/"vazgeç" seçer.
        case conflict(AccountLinkConflict)
        /// "Mevcut hesabıma geç" → `POST /auth/switch` işlemde.
        case switching
        /// Bağlandı (oturum bağlıya yükseldi).
        case linked(AccountSummary)
        /// Kullanıcı iptal etti (Apple sayfası VEYA birleştirme diyaloğu) — sessizce başa dön.
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

    /// Akış uçuşta mı (spinner + Apple butonu devre dışı) — durum makinesinin TEK isBusy kaynağı.
    /// View bunu okur; kendi kopyasını türetmez (review #14).
    public var isBusy: Bool {
        state.isBusy
    }

    // MARK: - Bağımlılıklar

    private let appleSignIn: any AppleSignInProviding
    private let linking: any AccountLinkingServicing
    private let analytics: any AnalyticsTracking
    private weak var delegate: (any HesapBaglamaDelegate)?

    private var activeTask: Task<Void, Never>?

    public init(
        appleSignIn: any AppleSignInProviding,
        linking: any AccountLinkingServicing,
        analytics: any AnalyticsTracking,
        delegate: (any HesapBaglamaDelegate)?
    ) {
        self.appleSignIn = appleSignIn
        self.linking = linking
        self.analytics = analytics
        self.delegate = delegate
    }

    // MARK: - Testler için deterministik bekleme

    /// Askıdaki bağlama/geçiş görevini bekler (test kancası).
    func pendingWork() async {
        await activeTask?.value
    }

    // MARK: - Akış

    /// "Apple ile Devam Et" → kimlik-bilgisi al, ardından backend'e bağla. Yalnız yeniden-başlatılabilir
    /// durumlardan ilerler: uçuşta (`linking`/`switching`), çakışma kararı beklerken (`conflict`) ve
    /// başarı sonrası (`linked`) NO-OP — çift oturum-yükseltme ve bekleyen çakışmanın sessizce düşmesi
    /// engellenir (SS-132 durum makinesi bütünlüğü).
    public func startAppleLinking() {
        guard canRestart else { return }
        state = .linking
        trackStarted()
        activeTask = Task { [weak self] in await self?.performLinking() }
    }

    private func performLinking() async {
        let credential: AppleCredential
        do {
            credential = try await appleSignIn.requestCredential()
        } catch let error as AppleSignInError {
            // İptal benign: success/failed ÜRETME, sessizce başa dön.
            if error == .cancelled {
                state = .cancelled
            } else {
                fail(.appleUnavailable)
            }
            return
        } catch {
            fail(.appleUnavailable)
            return
        }
        await completeLink(with: credential)
    }

    private func completeLink(with credential: AppleCredential) async {
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

    /// Çakışma diyaloğu: "Mevcut hesabıma geç" → `POST /auth/switch`.
    public func resolveConflictBySwitching() {
        guard case let .conflict(conflict) = state else { return }
        state = .switching
        activeTask = Task { [weak self] in await self?.performSwitch(conflict) }
    }

    private func performSwitch(_ conflict: AccountLinkConflict) async {
        do {
            let account = try await linking.switchToExistingAccount(conflict)
            finishLinked(account)
        } catch {
            fail(.linkFailed)
        }
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

    // MARK: - İç

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

    // MARK: - Analitik (02 §4.13)

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
        ["provider": .string(Self.provider.rawValue)]
    }
}

/// Bağlama ekranının kullanıcıya gösterdiği SAF hata sınıflandırması — ham `AppError`/`ASAuthorizationError`
/// SIZMAZ; View tek cümle mesaj seçer.
public enum HesapBaglamaError: Equatable, Sendable {
    /// Apple girişi başlatılamadı/başarısız.
    case appleUnavailable
    /// Backend bağlama başarısız (ağ/5xx/beklenmedik).
    case linkFailed
}
