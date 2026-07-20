import AppFoundation
import UIKit

/// `Dependencies` protokolünün canlı kompozisyonu (03 §5.1) — yalnız kompozisyon
/// kökünde (`ShortSeriesApp.init`) kurulur.
///
/// SS-021/022 ile `session`/`secureStore` ve 401 kurtarma zinciri GERÇEK:
/// `KeychainSecureStore` + `SessionManager` + `TokenRefreshCoordinator` + `AuthInterceptor`.
/// `analytics` artık GERÇEK: `AppAnalyticsTracker` (registry-doğrulamalı; `NoopAnalyticsTracker`
/// F1'de emekliye ayrıldı — 08 §2). Gerçek sink (Firebase) SS-150'de `AnalyticsSink` ile eklenir.
/// SS-100 (F2): authed apiClient zincirine `FraudSignalInterceptor` (cihaz-bütünlüğü + kazanç-hızı
/// danışma bayrakları) eklenir; kazanç-hızı raporlayıcısı kompozisyon kökünden enjekte edilir.
struct LiveDependencies: Dependencies {
    let apiClient: any APIClientProtocol
    let session: any SessionManaging
    let featureFlags: any FeatureFlagReading
    let logger: any Logging
    let analytics: any AnalyticsTracking
    let secureStore: any SecureStoring
    let preferences: any PreferencesStoring

    /// - Parameters:
    ///   - configuration: F0 varsayılanı `.development`; xcconfig tabanlı ortam seçimi SS-006'da bağlanır.
    ///   - velocityReporter: SS-100 kazanç-hızı danışma kaynağı (WalletKit `EarningVelocityMonitor`);
    ///     kompozisyon kökünden enjekte edilir. `nil` ise velocity header hiç eklenmez (bütünlük yine gider).
    @MainActor
    init(
        configuration: APIConfiguration = .development,
        velocityReporter: (any EarnVelocityReporting)? = nil
    ) {
        let secureStore = KeychainSecureStore()
        // Auth uçları (guest/refresh) requiresAuth=false'tur; interceptor'sız ve
        // tokenRefresher'sız bare istemci 401 kurtarma döngüsüne giremez. `X-Timezone` yine de
        // her istekte gider (05 §2.9): auth bootstrap'ında da zararsız/tutarlı. Fraud header'ları
        // yalnız authed apiClient zincirindedir (bare istemci yalnız requiresAuth=false uçlara gider).
        let bareClient = APIClient(
            configuration: configuration,
            interceptors: [TimezoneInterceptor()]
        )
        let sessionManager = SessionManager(apiClient: bareClient, secureStore: secureStore)
        let refreshCoordinator = TokenRefreshCoordinator(
            apiClient: bareClient,
            secureStore: secureStore,
            failureHandler: sessionManager
        )

        apiClient = APIClient(
            configuration: configuration,
            interceptors: Self.makeInterceptors(secureStore: secureStore, velocityReporter: velocityReporter),
            tokenRefresher: refreshCoordinator
        )
        session = sessionManager
        featureFlags = FeatureFlagStore() // UserDefaults snapshot; remote fetch SS-024
        let logger = OSLogger(category: "App")
        self.logger = logger
        // Registry-doğrulamalı canlı tracker (08 §2.3); Firebase sink SS-150'de eklenir.
        analytics = AppAnalyticsTracker(logger: logger)
        self.secureStore = secureStore
        preferences = UserDefaultsPreferences()
    }

    /// Authed apiClient interceptor zinciri (03 §8.1). Sıra: `AuthInterceptor` (Bearer, yalnız
    /// requiresAuth) → `TimezoneInterceptor` (X-Timezone HER istekte, 05 §2.9) → `FraudSignalInterceptor`
    /// (SS-100: X-Device-Integrity her authed istekte + X-Earn-Velocity-Flag sinyal varken; karar
    /// backend'de). Fabrika → App wiring testi zinciri (fraud interceptor kaydı + header davranışı)
    /// gerçek dependency grafiği kurmadan doğrular.
    @MainActor
    static func makeInterceptors(
        secureStore: any SecureStoring,
        velocityReporter: (any EarnVelocityReporting)?
    ) -> [any RequestInterceptor] {
        [
            AuthInterceptor(secureStore: secureStore),
            TimezoneInterceptor(),
            FraudSignalInterceptor(probe: liveDeviceIntegrityProbe(), velocityReporter: velocityReporter)
        ]
    }

    /// Canlı cihaz-bütünlüğü prob'u (SS-100): AppFoundation'ın UIKit-free `BasicDeviceIntegrityProbe`'una
    /// gerçek `UIApplication.canOpenURL(<scheme>://)` heuristiğini enjekte eder (dosya + sandbox-kaçış
    /// heuristikleri varsayılan). Prob `FraudSignalInterceptor` init'inde TEK KEZ (bu @MainActor bağlamda)
    /// değerlenir → `canOpenScheme` closure yalnız main-actor'da çağrılır (`assumeIsolated` güvenli;
    /// `adapt` prob'u tekrar çağırmaz). Şemalar Info.plist `LSApplicationQueriesSchemes`'te tanımlı
    /// olmalıdır; değilse iOS `canOpenURL`'ü false döndürür → best-effort false-negative (kabul edilir).
    @MainActor
    static func liveDeviceIntegrityProbe() -> BasicDeviceIntegrityProbe {
        #if targetEnvironment(simulator)
            // Simülatör, host macOS dosya sistemini görür: `/bin/bash`, `/usr/bin/ssh`, `/usr/sbin/sshd`
            // gibi generic jailbreak-artefaktı yolları macOS'ta MEVCUTtur → `fileExists` true → her dev/QA
            // koşusu gerçek-dışı `X-Device-Integrity: suspected` gönderir ve backend fraud sinyalini kirletir.
            // Jailbreak tespiti zaten yalnız fiziksel cihazda anlamlıdır → simülatörde TEMİZ prob (boş
            // heuristik). Gerçek cihaz yolu (#else) değişmez; sandbox bu yolları zaten reddeder.
            return BasicDeviceIntegrityProbe(
                suspiciousPaths: [],
                suspiciousSchemes: [],
                sandboxEscapeProbe: { false }
            )
        #else
            return BasicDeviceIntegrityProbe(
                canOpenScheme: { scheme in
                    MainActor.assumeIsolated {
                        guard let url = URL(string: "\(scheme)://") else { return false }
                        return UIApplication.shared.canOpenURL(url)
                    }
                }
            )
        #endif
    }
}
