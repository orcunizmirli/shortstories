/// APNs teslim ortamı (05 §4.9 POST /devices `environment`). Debug/TestFlight build'leri sandbox,
/// App Store build'i production token üretir → sunucu token'ı doğru APNs ana bilgisayarına yönlendirir.
/// Karar App kompozisyon kökünde verilir (DEBUG → `.sandbox`); AppFoundation ham değeri taşır.
public enum APNsEnvironment: String, Sendable, Equatable, CaseIterable {
    case sandbox
    case production
}
