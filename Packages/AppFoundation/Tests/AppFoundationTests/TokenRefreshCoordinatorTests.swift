import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

/// Ağ gecikmesini taklit eden sarmalayıcı — single-flight testinde eşzamanlı çağrıların
/// ilk refresh uçuştayken kuyruklanmasını garanti eder.
private final class DelayingAPIClient: APIClientProtocol, @unchecked Sendable {
    let inner = MockAPIClient()
    private let delay: Duration

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        return try await inner.send(endpoint)
    }
}

@MainActor
private final class FakeRefreshFailureHandler: RefreshFailureHandling {
    private(set) var callCount = 0
    private let tokenToReturn: String?

    init(tokenToReturn: String? = nil) {
        self.tokenToReturn = tokenToReturn
    }

    func handleRefreshFailure() async -> String? {
        callCount += 1
        return tokenToReturn
    }
}

@MainActor
struct TokenRefreshCoordinatorTests {
    private let apiClient = MockAPIClient()
    private let secureStore = MockSecureStore()

    private func seedRefreshToken(_ token: String = "rt_old") throws {
        try secureStore.setString(token, forKey: .refreshToken)
        try secureStore.setString("at_old", forKey: .accessToken)
    }

    private func stubRefreshSuccess(on client: MockAPIClient) throws {
        try client.stub(
            "/auth/refresh",
            returning: ["accessToken": "at_new", "refreshToken": "rt_new"]
        )
    }

    // MARK: - Başarılı refresh

    @Test func basariliRefreshYeniAccessTokenDondurur() async throws {
        try seedRefreshToken()
        try stubRefreshSuccess(on: apiClient)
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        let token = try await coordinator.refreshAccessToken()

        #expect(token == "at_new")
    }

    @Test func basariliRefreshTokenlariRotasyonlaKeychaineYazar() async throws {
        try seedRefreshToken()
        try stubRefreshSuccess(on: apiClient)
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        try await coordinator.refreshAccessToken()

        #expect(try secureStore.string(forKey: .accessToken) == "at_new")
        #expect(try secureStore.string(forKey: .refreshToken) == "rt_new")
    }

    @Test func refreshIstegiSozlesmeyeUygundur() async throws {
        try seedRefreshToken("rt_gonderilecek")
        try stubRefreshSuccess(on: apiClient)
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        try await coordinator.refreshAccessToken()

        let endpoint = try #require(apiClient.receivedEndpoints.first as? RefreshTokenEndpoint)
        #expect(endpoint.path == "/auth/refresh")
        #expect(endpoint.method == .post)
        #expect(endpoint.requiresAuth == false)
        #expect(endpoint.requestBody.refreshToken == "rt_gonderilecek")
    }

    // MARK: - Single-flight (03 §8.2 madde 2)

    @Test func esZamanliCagrilarAyniRefreshTaskiniPaylasir() async throws {
        let delayingClient = DelayingAPIClient(delay: .milliseconds(200))
        try seedRefreshToken()
        try stubRefreshSuccess(on: delayingClient.inner)
        let coordinator = TokenRefreshCoordinator(apiClient: delayingClient, secureStore: secureStore)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 5 {
                group.addTask { try await coordinator.refreshAccessToken() }
            }
            var collected: [String] = []
            for try await token in group {
                collected.append(token)
            }
            return collected
        }

        #expect(tokens == Array(repeating: "at_new", count: 5))
        #expect(delayingClient.inner.receivedPaths == ["/auth/refresh"])
    }

    @Test func tamamlanmisRefreshSonrasiYeniCagriYenidenUcusBaslatir() async throws {
        try seedRefreshToken()
        try stubRefreshSuccess(on: apiClient)
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        try await coordinator.refreshAccessToken()
        try await coordinator.refreshAccessToken()

        #expect(apiClient.receivedPaths == ["/auth/refresh", "/auth/refresh"])
    }

    // MARK: - Refresh düşerse fallback (05 §4.2: sessizce misafir yeniden-auth)

    @Test func refreshAuthHatasindaFallbackTokeniDondurur() async throws {
        try seedRefreshToken()
        apiClient.stub("/auth/refresh", throwing: .auth(.sessionExpired))
        let handler = FakeRefreshFailureHandler(tokenToReturn: "at_guest")
        let coordinator = TokenRefreshCoordinator(
            apiClient: apiClient,
            secureStore: secureStore,
            failureHandler: handler
        )

        let token = try await coordinator.refreshAccessToken()

        #expect(token == "at_guest")
        #expect(handler.callCount == 1)
    }

    @Test func fallbackNilDondururseSessionExpiredFirlar() async throws {
        try seedRefreshToken()
        apiClient.stub("/auth/refresh", throwing: .auth(.sessionExpired))
        let handler = FakeRefreshFailureHandler(tokenToReturn: nil)
        let coordinator = TokenRefreshCoordinator(
            apiClient: apiClient,
            secureStore: secureStore,
            failureHandler: handler
        )

        await #expect(throws: AppError.auth(.sessionExpired)) {
            try await coordinator.refreshAccessToken()
        }
        #expect(handler.callCount == 1)
    }

    @Test func fallbackHandlerYoksaSessionExpiredFirlar() async throws {
        try seedRefreshToken()
        apiClient.stub("/auth/refresh", throwing: .auth(.sessionExpired))
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        await #expect(throws: AppError.auth(.sessionExpired)) {
            try await coordinator.refreshAccessToken()
        }
    }

    @Test func refreshTokenYoksaAgaCikmadanFallbackCagrilir() async throws {
        let handler = FakeRefreshFailureHandler(tokenToReturn: "at_guest")
        let coordinator = TokenRefreshCoordinator(
            apiClient: apiClient,
            secureStore: secureStore,
            failureHandler: handler
        )

        let token = try await coordinator.refreshAccessToken()

        #expect(token == "at_guest")
        #expect(apiClient.receivedPaths.isEmpty)
        #expect(handler.callCount == 1)
    }

    @Test func agHatasiFallbackTetiklemezVeYuzer() async throws {
        try seedRefreshToken()
        apiClient.stub("/auth/refresh", throwing: .network(.offline))
        let handler = FakeRefreshFailureHandler(tokenToReturn: "at_guest")
        let coordinator = TokenRefreshCoordinator(
            apiClient: apiClient,
            secureStore: secureStore,
            failureHandler: handler
        )

        await #expect(throws: AppError.network(.offline)) {
            try await coordinator.refreshAccessToken()
        }
        #expect(handler.callCount == 0)
    }

    // MARK: - TOKEN_INVALID kurtarması (05 §10.2: refresh DENENMEZ)

    @Test func recoverFromInvalidTokenRefreshUcunaHicGitmedenFallbackYolunuKullanir() async throws {
        // Keychain'de refresh token VAR ama TOKEN_INVALID'de kullanılMAMALIDIR:
        // doğrudan SessionManager yolu (token temizliği + misafir yeniden-bootstrap).
        try seedRefreshToken()
        let handler = FakeRefreshFailureHandler(tokenToReturn: "at_guest")
        let coordinator = TokenRefreshCoordinator(
            apiClient: apiClient,
            secureStore: secureStore,
            failureHandler: handler
        )

        let token = try await coordinator.recoverFromInvalidToken()

        #expect(token == "at_guest")
        #expect(apiClient.receivedPaths.isEmpty)
        #expect(handler.callCount == 1)
    }

    @Test func recoverFromInvalidTokenFallbackNilDondururseSessionExpiredFirlar() async throws {
        try seedRefreshToken()
        let handler = FakeRefreshFailureHandler(tokenToReturn: nil)
        let coordinator = TokenRefreshCoordinator(
            apiClient: apiClient,
            secureStore: secureStore,
            failureHandler: handler
        )

        await #expect(throws: AppError.auth(.sessionExpired)) {
            try await coordinator.recoverFromInvalidToken()
        }
        #expect(handler.callCount == 1)
    }

    @Test func basarisizRefreshSonrasiYeniCagriYenidenDener() async throws {
        try seedRefreshToken()
        apiClient.stub("/auth/refresh", throwing: .network(.offline))
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        await #expect(throws: AppError.network(.offline)) {
            try await coordinator.refreshAccessToken()
        }
        try stubRefreshSuccess(on: apiClient)

        let token = try await coordinator.refreshAccessToken()

        #expect(token == "at_new")
        #expect(apiClient.receivedPaths == ["/auth/refresh", "/auth/refresh"])
    }
}
