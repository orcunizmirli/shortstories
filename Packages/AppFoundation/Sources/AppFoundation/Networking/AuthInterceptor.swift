import Foundation

/// `Authorization: Bearer <access>` ekleyen interceptor (03 §8.2). Token'ı her istekte
/// Keychain'den okur — `TokenRefreshCoordinator` rotasyonu yazdığı anda sonraki istek
/// yeni token'ı görür. `requiresAuth=false` uçlara ve token yokken header EKLENMEZ
/// (eksik token sunucuda 401 → refresh/bootstrap akışıyla kendini onarır).
public struct AuthInterceptor: RequestInterceptor {
    private let secureStore: any SecureStoring

    public init(secureStore: any SecureStoring) {
        self.secureStore = secureStore
    }

    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        guard context.requiresAuth,
              let accessToken = try? secureStore.string(forKey: .accessToken),
              !accessToken.isEmpty
        else {
            return request
        }
        var adapted = request
        adapted.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return adapted
    }
}
