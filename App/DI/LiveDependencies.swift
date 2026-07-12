import AppFoundation
import Foundation

/// `Dependencies` protokolünün canlı kompozisyonu (03 §5.1) — yalnız kompozisyon
/// kökünde (`ShortSeriesApp.init`) kurulur.
///
/// F0 kapsamı (plan §5): `APIClient`, `OSLogger`, UserDefaults tabanlı flag
/// snapshot'ı ve preferences GERÇEK; kalanlar canlı impl'leri gelene dek
/// AppFoundation'daki stub'lardır:
/// - `session` / `secureStore` → SS-021 (misafir hesap + Keychain)
/// - `analytics` → F1 (AnalyticsKit tracker'ı)
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
    init(configuration: APIConfiguration = .development) {
        apiClient = APIClient(configuration: configuration)
        session = StubSessionManager()
        featureFlags = FeatureFlagStore() // UserDefaults snapshot; remote fetch SS-024
        logger = OSLogger(category: "App")
        analytics = NoopAnalyticsTracker()
        secureStore = InMemorySecureStore()
        preferences = UserDefaultsPreferences()
    }
}
