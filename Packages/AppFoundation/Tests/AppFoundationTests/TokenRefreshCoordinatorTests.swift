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

/// `.refreshToken` okumasında geçici Keychain hatası (`keychainUnavailable`) fırlatan stub; diğer
/// anahtarlar `MockSecureStore`'a devredilir. performRefresh'in geçici-hata↔yok-token ayrımını test eder.
private final class RefreshTokenReadFailingStore: SecureStoring, @unchecked Sendable {
    private let backing = MockSecureStore()
    func data(forKey key: SecureStoreKey) throws -> Data? {
        if key == .refreshToken {
            throw AppError.storage(.keychainUnavailable)
        }
        return try backing.data(forKey: key)
    }

    func setData(_ data: Data, forKey key: SecureStoreKey) throws {
        try backing.setData(data, forKey: key)
    }

    func removeData(forKey key: SecureStoreKey) throws {
        try backing.removeData(forKey: key)
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

    // MARK: - Geçici Keychain hatası (audit MEDIUM: yıkıcı logout DEĞİL)

    @Test func geciciKeychainOkumaHatasiLogoutTetiklemezVeYuzer() async throws {
        // `keychainUnavailable` (cihaz ilk kilit açılmadan / securityd glitch) yok-token DEĞİLDİR:
        // geçerli refresh token'ı olan kullanıcı yıkıcı fallback'e (logout) SOKULMAMALI; hata yüzmeli.
        let failing = RefreshTokenReadFailingStore()
        let handler = FakeRefreshFailureHandler(tokenToReturn: "at_recovered")
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: failing, failureHandler: handler)

        do {
            _ = try await coordinator.refreshAccessToken()
            Issue.record("geçici Keychain hatası fırlamalıydı, fallback'e gitmemeliydi")
        } catch let error as AppError {
            #expect(error == .storage(.keychainUnavailable)) // geçici hata YÜZER
        }
        let calls = await handler.callCount
        #expect(calls == 0) // yıkıcı fallback (logout) TETİKLENMEZ
    }

    // MARK: - Torn write (audit LOW): kısmi Keychain yazımı eşleşmeyen token çifti bırakmamalı

    @Test func refreshTokenYazimiKoparsaYeniAccessEskiRefreshCiftiOlusmaz() async throws {
        // access ve refresh yazımı atomik değil. Refresh-token yazımı koparsa Keychain'de
        // (YENİ access, ESKİ rotasyonlanmış refresh) kalırsa access süresi dolunca geçersiz refresh'le
        // sessizce logout'a zorlar (saatli bomba). Refresh ÖNCE yazıldığından bu koparsa ESKİ çift
        // korunur (self-heal) → torn çift OLUŞMAZ.
        let store = WriteFailingSecureStore(failWriteFor: .refreshToken)
        try store.backing.setString("rt_old", forKey: .refreshToken)
        try store.backing.setString("at_old", forKey: .accessToken)
        try stubRefreshSuccess(on: apiClient)
        store.arm()
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: store)

        _ = try? await coordinator.refreshAccessToken() // refresh yazımı koptuğu için throw

        let access = try store.backing.string(forKey: .accessToken)
        let refresh = try store.backing.string(forKey: .refreshToken)
        #expect(!(access == "at_new" && refresh == "rt_old")) // torn çift YASAK
    }

    @Test func accessTokenYazimiKoparsaRefreshKaliciDonerVeTazeAccessDoner() async throws {
        // Refresh ÖNCE kalıcılaşır; access (best-effort) yazımı koparsa Keychain'de bayat access kalır
        // ama sonraki 401 yeni refresh'le kendini onarır → çağırana yine taze access döner, logout YOK.
        let store = WriteFailingSecureStore(failWriteFor: .accessToken)
        try store.backing.setString("rt_old", forKey: .refreshToken)
        try store.backing.setString("at_old", forKey: .accessToken)
        try stubRefreshSuccess(on: apiClient)
        store.arm()
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: store)

        let token = try await coordinator.refreshAccessToken()

        #expect(token == "at_new") // best-effort access yazım hatası refresh'i BOZMAZ
        #expect(try store.backing.string(forKey: .refreshToken) == "rt_new") // refresh kalıcılaştı
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

    // MARK: - Bayat-token kontrolü (geç 401: istek eski token'la kurulmuş, rotasyon zaten olmuş)

    @Test func bayatTokenIleGelen401RotasyonSonrasiYeniRefreshTetiklemez() async throws {
        // Rotasyon tamamlanmış: Keychain'de artık at_new var; geç kalan istek at_old kullanmıştı.
        try secureStore.setString("at_new", forKey: .accessToken)
        try secureStore.setString("rt_new", forKey: .refreshToken)
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        let token = try await coordinator.refreshAccessToken(ifStaleTokenWas: "at_old")

        #expect(token == "at_new")
        #expect(apiClient.receivedPaths.isEmpty) // /auth/refresh HİÇ çağrılmadı
    }

    @Test func gecerliTokenIleBayatKontrolNormalRefreshYurutur() async throws {
        // İstek mevcut token'la kurulmuştu (rotasyon OLMAMIŞ) — normal refresh akışı işler.
        try seedRefreshToken() // access = at_old
        try stubRefreshSuccess(on: apiClient)
        let coordinator = TokenRefreshCoordinator(apiClient: apiClient, secureStore: secureStore)

        let token = try await coordinator.refreshAccessToken(ifStaleTokenWas: "at_old")

        #expect(token == "at_new")
        #expect(apiClient.receivedPaths == ["/auth/refresh"])
    }

    @Test func bayatTokenIleGelenInvalidSinyaliYikiciKurtarmayiAtlar() async throws {
        // Geç TOKEN_INVALID: token zaten rotasyondan geçmişse Keychain temizliği/misafir
        // yeniden-bootstrap YAPILMAZ — mevcut token döner (05 §10.2 kurtarma yalnız gerçekten
        // geçersiz oturum içindir).
        try secureStore.setString("at_new", forKey: .accessToken)
        try secureStore.setString("rt_new", forKey: .refreshToken)
        let handler = FakeRefreshFailureHandler(tokenToReturn: "at_bootstrap")
        let coordinator = TokenRefreshCoordinator(
            apiClient: apiClient,
            secureStore: secureStore,
            failureHandler: handler
        )

        let token = try await coordinator.recoverFromInvalidToken(ifStaleTokenWas: "at_old")

        #expect(token == "at_new")
        #expect(handler.callCount == 0) // yıkıcı kurtarma çağrılmadı
        #expect(try secureStore.string(forKey: .refreshToken) == "rt_new") // Keychain dokunulmadı
    }
}
