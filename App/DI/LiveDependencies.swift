import AppFoundation

/// `Dependencies` protokolünün canlı kompozisyonu (03 §5.1) — yalnız kompozisyon
/// kökünde (`ShortSeriesApp.init`) kurulur.
///
/// SS-021/022 ile `session`/`secureStore` ve 401 kurtarma zinciri GERÇEK:
/// `KeychainSecureStore` + `SessionManager` + `TokenRefreshCoordinator` + `AuthInterceptor`.
/// `analytics` artık GERÇEK: `AppAnalyticsTracker` (registry-doğrulamalı; `NoopAnalyticsTracker`
/// F1'de emekliye ayrıldı — 08 §2). Gerçek sink (Firebase) SS-150'de `AnalyticsSink` ile eklenir.
struct LiveDependencies: Dependencies {
    let apiClient: any APIClientProtocol
    let session: any SessionManaging
    let featureFlags: any FeatureFlagReading
    let logger: any Logging
    let analytics: any AnalyticsTracking
    let secureStore: any SecureStoring
    let preferences: any PreferencesStoring

    /// - Parameter configuration: F0 varsayılanı `.development`; xcconfig tabanlı
    ///   ortam seçimi SS-006'da bağlanır.
    @MainActor
    init(configuration: APIConfiguration = .development) {
        let secureStore = KeychainSecureStore()
        // Auth uçları (guest/refresh) requiresAuth=false'tur; interceptor'sız ve
        // tokenRefresher'sız bare istemci 401 kurtarma döngüsüne giremez. `X-Timezone` yine de
        // her istekte gider (05 §2.9): auth bootstrap'ında da zararsız/tutarlı.
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
            // `X-Timezone` HER istekte (GET okumalar dahil, 05 §2.9); Bearer yalnız requiresAuth uçlara.
            interceptors: [AuthInterceptor(secureStore: secureStore), TimezoneInterceptor()],
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
}
