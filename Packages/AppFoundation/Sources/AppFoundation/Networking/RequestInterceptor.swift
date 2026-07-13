import Foundation

/// Interceptor'a taşınan endpoint bağlamı — `URLRequest` tek başına `requiresAuth`
/// beyanını taşıyamadığı için 03 §8.1 iskeletindeki `adapt(_:)` imzası bağlam alacak
/// biçimde genişletilmiştir (03 §8.2 "requiresAuth=false uçlara eklenmez" kuralı için).
public struct RequestContext: Sendable {
    public let requiresAuth: Bool

    public init(requiresAuth: Bool) {
        self.requiresAuth = requiresAuth
    }
}

/// İsteğe sıralı uygulanan dönüştürücü zinciri halkası (03 §8.1).
/// Canlı örnekler: `AuthInterceptor`, `LocaleInterceptor` (F1).
public protocol RequestInterceptor: Sendable {
    func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest
}
