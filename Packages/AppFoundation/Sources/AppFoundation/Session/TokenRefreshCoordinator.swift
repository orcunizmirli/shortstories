import Foundation

/// APIClient'ın 401 sonrası tuttuğu yenileme kolu (03 §8.2). Canlı uygulama:
/// `TokenRefreshCoordinator`.
public protocol AuthTokenRefreshing: Sendable {
    /// Tek-uçuş token yenileme; başarıda geçerli access token döner.
    /// `ifStaleTokenWas`: 401'i alan isteğin kullandığı access token. Mevcut token bundan
    /// farklıysa rotasyon o istek uçuştayken zaten tamamlanmıştır — yeni refresh
    /// BAŞLATILMAZ, mevcut token döner (geç-401 yarışı; 03 §8.2'nin tekillik amacı).
    @discardableResult
    func refreshAccessToken(ifStaleTokenWas staleToken: String?) async throws -> String

    /// 401 + `TOKEN_INVALID` sonrası (05 §10.2): refresh DENENMEZ — Keychain temizliği +
    /// misafir yeniden-bootstrap (SessionManager yolu; bağlı hesapta `.loggedOut`).
    /// `ifStaleTokenWas` bayat çıkarsa yıkıcı kurtarma da ATLANIR (mevcut token döner).
    /// Başarıda yeni access token döner.
    @discardableResult
    func recoverFromInvalidToken(ifStaleTokenWas staleToken: String?) async throws -> String
}

public extension AuthTokenRefreshing {
    @discardableResult
    func refreshAccessToken() async throws -> String {
        try await refreshAccessToken(ifStaleTokenWas: nil)
    }

    @discardableResult
    func recoverFromInvalidToken() async throws -> String {
        try await recoverFromInvalidToken(ifStaleTokenWas: nil)
    }
}

/// Refresh zinciri koptuğunda oturum sahibinin (SessionManager) düşüş stratejisi (05 §4.2):
/// misafirse sessizce yeniden bootstrap edip yeni access token döner; bağlı hesapta
/// `.loggedOut` durumuna geçer ve `nil` döner (yeniden giriş F2 akışı).
@MainActor
public protocol RefreshFailureHandling: AnyObject, Sendable {
    func handleRefreshFailure() async -> String?
}

/// Single-flight token yenileme actor'ü (03 §8.2 madde 2; 05 §4.2 eşzamanlılık kuralı):
/// eşzamanlı 401'ler AYNI refresh task'ını await eder — thundering herd önlenir.
/// Refresh ucu `requiresAuth=false` olduğundan yenileme isteği 401 kurtarma akışına giremez.
public actor TokenRefreshCoordinator: AuthTokenRefreshing {
    private let apiClient: any APIClientProtocol
    private let secureStore: any SecureStoring
    private let failureHandler: (any RefreshFailureHandling)?
    private var inFlight: Task<String, Error>?

    public init(
        apiClient: any APIClientProtocol,
        secureStore: any SecureStoring,
        failureHandler: (any RefreshFailureHandling)? = nil
    ) {
        self.apiClient = apiClient
        self.secureStore = secureStore
        self.failureHandler = failureHandler
    }

    @discardableResult
    public func refreshAccessToken(ifStaleTokenWas staleToken: String?) async throws -> String {
        try await singleFlight {
            if let current = await self.currentTokenIfRotated(since: staleToken) {
                return current
            }
            return try await self.performRefresh()
        }
    }

    /// TOKEN_INVALID'de refresh token da geçersiz sayılır: `/auth/refresh` HİÇ denenmez,
    /// doğrudan SessionManager düşüş yoluna gidilir (token temizliği + misafir
    /// yeniden-bootstrap; bağlı hesapta `.loggedOut`). Eşzamanlı çağrılar aynı uçuşu paylaşır.
    @discardableResult
    public func recoverFromInvalidToken(ifStaleTokenWas staleToken: String?) async throws -> String {
        try await singleFlight {
            if let current = await self.currentTokenIfRotated(since: staleToken) {
                return current
            }
            return try await self.recoverViaFallback()
        }
    }

    /// Geç-401 yarışı: istek `staleToken` ile kurulmuş ama Keychain'deki token artık farklıysa
    /// rotasyon o istek uçuştayken tamamlanmıştır — çağıran yeni token'la tekrar etmelidir.
    private func currentTokenIfRotated(since staleToken: String?) -> String? {
        guard let staleToken,
              let current = try? secureStore.string(forKey: .accessToken),
              !current.isEmpty, current != staleToken
        else {
            return nil
        }
        return current
    }

    private func singleFlight(_ operation: @escaping @Sendable () async throws -> String) async throws -> String {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { try await operation() }
        inFlight = task
        let result = await task.result
        inFlight = nil
        return try result.get()
    }

    private func performRefresh() async throws -> String {
        guard let refreshToken = try? secureStore.string(forKey: .refreshToken),
              !refreshToken.isEmpty
        else {
            return try await recoverViaFallback()
        }
        do {
            let endpoint = RefreshTokenEndpoint(requestBody: RefreshTokenEndpoint.RequestBody(
                refreshToken: refreshToken
            ))
            let response = try await apiClient.send(endpoint)
            try secureStore.setString(response.accessToken, forKey: .accessToken)
            try secureStore.setString(response.refreshToken, forKey: .refreshToken)
            return response.accessToken
        } catch let error as AppError {
            // Yalnız auth reddi düşüş akışını tetikler; ağ/sunucu hataları yüzer (05 §10.2).
            guard case .auth = error else {
                throw error
            }
            return try await recoverViaFallback()
        }
    }

    private func recoverViaFallback() async throws -> String {
        if let failureHandler, let token = await failureHandler.handleRefreshFailure() {
            return token
        }
        throw AppError.auth(.sessionExpired)
    }
}
