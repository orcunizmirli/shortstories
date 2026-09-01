import Foundation

/// `Authorization: Bearer <access>` ekleyen interceptor (03 §8.2). Token'ı her istekte
/// Keychain'den okur — `TokenRefreshCoordinator` rotasyonu yazdığı anda sonraki istek
/// yeni token'ı görür. `requiresAuth=false` uçlara ve token yokken header EKLENMEZ
/// (eksik token sunucuda 401 → refresh/bootstrap akışıyla kendini onarır).
public struct AuthInterceptor: RequestInterceptor {
    private let secureStore: any SecureStoring
    /// İzinli API host'u (auth hunt LOW, defense-in-depth): Bearer YALNIZ bu host'a eklenir → gelecekte
    /// yabancı-host bir istek (CDN/analytics/3P) bu zincirden geçse bile kullanıcı token'ı SIZMAZ. `nil`
    /// = host kısıtı yok (yalnız izole birim testleri; canlı wiring her zaman gerçek host'u geçer).
    private let apiHost: String?

    public init(secureStore: any SecureStoring, apiHost: String? = nil) {
        self.secureStore = secureStore
        self.apiHost = apiHost
    }

    public func adapt(_ request: URLRequest, context: RequestContext) async throws -> URLRequest {
        guard context.requiresAuth,
              isAllowedHost(request.url),
              let accessToken = try? secureStore.string(forKey: .accessToken),
              !accessToken.isEmpty
        else {
            return request
        }
        var adapted = request
        adapted.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return adapted
    }

    /// `apiHost` set ise istek host'u ona EŞLEŞMELİ (aksi halde Bearer eklenmez); `nil` ise kısıt yok.
    private func isAllowedHost(_ url: URL?) -> Bool {
        guard let apiHost else { return true }
        return url?.host == apiHost
    }
}
