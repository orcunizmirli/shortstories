/// Hafif, protokol tabanlı DI konteyneri (03 §5.1). YALNIZ AppFoundation'da tanımlı
/// cross-cutting protokolleri taşır (R1: AppFoundation hiçbir iç modüle bağımlı olamaz).
///
/// Bağlayıcı sonuçlar (03 §5.1):
/// - `analytics` type-erased'dır; tipli event yüzeyi `AnalyticsKit`'te kalır.
/// - Feature'a özgü servisler (`PlayerPool`, `WalletStore`, ...) buraya GİREMEZ —
///   onlar `ShortSeriesApp` kompozisyon kökünde kurulup init-injection ile verilir.
/// - Feature modülleri geniş konteyneri değil, ihtiyaç duydukları DAR protokolleri alır
///   (interface segregation); seçim koordinatörde yapılır.
public protocol Dependencies: Sendable {
    var apiClient: any APIClientProtocol { get }
    var session: any SessionManaging { get }
    var featureFlags: any FeatureFlagReading { get }
    var logger: any Logging { get }
    var analytics: any AnalyticsTracking { get }
    var secureStore: any SecureStoring { get }
    var preferences: any PreferencesStoring { get }
}
