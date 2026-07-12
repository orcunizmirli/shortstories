import Foundation

/// İsteğe sıralı uygulanan dönüştürücü zinciri halkası (03 §8.1).
/// Canlı örnekler: `AuthInterceptor` (SS-021), `LocaleInterceptor`. F0'da somut
/// interceptor yoktur; `APIClient` boş zincirle kurulur.
public protocol RequestInterceptor: Sendable {
    func adapt(_ request: URLRequest) async throws -> URLRequest
}
