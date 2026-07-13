import AppFoundation
import Foundation

/// `Dependencies` protokolünün canlı kompozisyonu (03 §5.1) — yalnız kompozisyon
/// kökünde (`ShortSeriesApp.init`) kurulur.
///
/// SS-021/022 ile `session`/`secureStore` ve 401 kurtarma zinciri GERÇEK:
/// `KeychainSecureStore` + `SessionManager` + `TokenRefreshCoordinator` + `AuthInterceptor`.
/// Kalan stub: `analytics` → F1 (AnalyticsKit tracker'ı).
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
        // tokenRefresher'sız bare istemci 401 kurtarma döngüsüne giremez.
        let bareClient = APIClient(configuration: configuration)
        let sessionManager = SessionManager(apiClient: bareClient, secureStore: secureStore)
        let refreshCoordinator = TokenRefreshCoordinator(
            apiClient: bareClient,
            secureStore: secureStore,
            failureHandler: sessionManager
        )

        apiClient = APIClient(
            configuration: configuration,
            interceptors: [AuthInterceptor(secureStore: secureStore)],
            tokenRefresher: refreshCoordinator
        )
        session = sessionManager
        featureFlags = FeatureFlagStore() // UserDefaults snapshot; remote fetch SS-024
        logger = OSLogger(category: "App")
        analytics = NoopAnalyticsTracker()
        self.secureStore = secureStore
        preferences = UserDefaultsPreferences()
    }
}
