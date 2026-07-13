import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

/// İptal edilmiş URLSession task'ını taklit eder: canlı `APIClient.performOnce` iptalde
/// `CancellationError` fırlatır (AppError DEĞİL).
private struct CancellingAPIClient: APIClientProtocol {
    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        throw CancellationError()
    }
}

@MainActor
struct SessionManagerTests {
    private let apiClient = MockAPIClient()
    private let secureStore = MockSecureStore()
    private let manager: SessionManager

    init() {
        manager = SessionManager(
            apiClient: apiClient,
            secureStore: secureStore,
            clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
        )
    }

    private func stubGuestSuccess(userID: String = "usr_ab12cd") throws {
        try apiClient.stub(
            "/auth/guest",
            returning: ["userId": userID, "accessToken": "at_1", "refreshToken": "rt_1"]
        )
    }

    private func seedStoredSession(provider: AuthProvider? = nil, userID: String = "usr_stored") throws {
        try secureStore.setString("at_stored", forKey: .accessToken)
        try secureStore.setString("rt_stored", forKey: .refreshToken)
        let snapshot = StoredSessionSnapshot(userID: userID, provider: provider)
        try secureStore.setData(JSONEncoder().encode(snapshot), forKey: .sessionSnapshot)
    }

    // MARK: - İlk açılış bootstrap'ı

    @Test func ilkDurumUnauthenticated() {
        #expect(manager.state == .unauthenticated)
    }

    @Test func ilkAcilistaMisafirHesabiKurar() async throws {
        try stubGuestSuccess()

        let state = try await manager.bootstrapGuestSessionIfNeeded()

        #expect(state == .guest(userID: "usr_ab12cd"))
        #expect(manager.state == .guest(userID: "usr_ab12cd"))
        #expect(apiClient.receivedPaths == ["/auth/guest"])
    }

    @Test func bootstrapTokenlariVeSnapshotiKeychaineYazar() async throws {
        try stubGuestSuccess()

        try await manager.bootstrapGuestSessionIfNeeded()

        #expect(try secureStore.string(forKey: .accessToken) == "at_1")
        #expect(try secureStore.string(forKey: .refreshToken) == "rt_1")
        let snapshotData = try #require(try secureStore.data(forKey: .sessionSnapshot))
        let snapshot = try JSONDecoder().decode(StoredSessionSnapshot.self, from: snapshotData)
        #expect(snapshot.userID == "usr_ab12cd")
        #expect(snapshot.provider == nil)
    }

    @Test func bootstrapIstegiSozlesmeyeUygunGovdeTasir() async throws {
        try stubGuestSuccess()

        try await manager.bootstrapGuestSessionIfNeeded()

        let endpoint = try #require(apiClient.receivedEndpoints.first as? GuestAuthEndpoint)
        #expect(endpoint.requiresAuth == false)
        #expect(endpoint.method == .post)
        #expect(endpoint.requestBody.platform == "ios")
        #expect(endpoint.requestBody.appVersion == "1.0.0")
        #expect(endpoint.requestBody.locale == "en-US")
        #expect(!endpoint.requestBody.deviceId.isEmpty)
    }

    @Test func deviceIdUretilirKeychaindeSaklanirVeYenidenKullanilir() async throws {
        try stubGuestSuccess()

        try await manager.bootstrapGuestSessionIfNeeded()
        let firstDeviceID = try #require(try secureStore.string(forKey: .deviceID))
        let sentDeviceID = (apiClient.receivedEndpoints.first as? GuestAuthEndpoint)?.requestBody.deviceId
        #expect(sentDeviceID == firstDeviceID)

        // Yeniden yükleme senaryosu: tokenlar silinir, deviceID kalır (05 §4.2).
        try secureStore.removeData(forKey: .accessToken)
        try secureStore.removeData(forKey: .refreshToken)
        try secureStore.removeData(forKey: .sessionSnapshot)
        let secondManager = SessionManager(
            apiClient: apiClient,
            secureStore: secureStore,
            clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
        )
        try await secondManager.bootstrapGuestSessionIfNeeded()

        let lastDeviceID = (apiClient.receivedEndpoints.last as? GuestAuthEndpoint)?.requestBody.deviceId
        #expect(lastDeviceID == firstDeviceID)
    }

    @Test func bootstrapBasarisizligiGuestBootstrapFailedFirlatir() async throws {
        apiClient.stub("/auth/guest", throwing: .network(.offline))

        await #expect(throws: AppError.auth(.guestBootstrapFailed)) {
            try await manager.bootstrapGuestSessionIfNeeded()
        }
        #expect(manager.state == .unauthenticated)
    }

    // MARK: - Keychain'den devam

    @Test func keychaindeMisafirOturumuVarsaAgaCikmadanDevamEder() async throws {
        try seedStoredSession()

        let state = try await manager.bootstrapGuestSessionIfNeeded()

        #expect(state == .guest(userID: "usr_stored"))
        #expect(apiClient.receivedPaths.isEmpty)
    }

    @Test func keychaindeBagliHesapVarsaLinkedOlarakDevamEder() async throws {
        try seedStoredSession(provider: .apple, userID: "usr_linked")

        let state = try await manager.bootstrapGuestSessionIfNeeded()

        #expect(state == .linked(userID: "usr_linked", provider: .apple))
        #expect(apiClient.receivedPaths.isEmpty)
    }

    @Test func tokenVarAmaSnapshotYoksaYenidenBootstrapYapar() async throws {
        try secureStore.setString("at_yalniz", forKey: .accessToken)
        try stubGuestSuccess()

        let state = try await manager.bootstrapGuestSessionIfNeeded()

        #expect(state == .guest(userID: "usr_ab12cd"))
        #expect(apiClient.receivedPaths == ["/auth/guest"])
    }

    // MARK: - Tekrarlanan / eşzamanlı bootstrap

    @Test func hesapZatenKuruluysaNoOp() async throws {
        try stubGuestSuccess()

        try await manager.bootstrapGuestSessionIfNeeded()
        try await manager.bootstrapGuestSessionIfNeeded()

        #expect(apiClient.receivedPaths == ["/auth/guest"])
    }

    @Test func esZamanliBootstrapTekIstekYapar() async throws {
        try stubGuestSuccess()

        async let first = manager.bootstrapGuestSessionIfNeeded()
        async let second = manager.bootstrapGuestSessionIfNeeded()
        let states = try await [first, second]

        #expect(states == [.guest(userID: "usr_ab12cd"), .guest(userID: "usr_ab12cd")])
        #expect(apiClient.receivedPaths == ["/auth/guest"])
    }

    // MARK: - stateUpdates

    @Test func stateUpdatesMevcutDurumlaBaslarVeDegisimYayinlar() async throws {
        try stubGuestSuccess()
        var iterator = manager.stateUpdates.makeAsyncIterator()

        #expect(await iterator.next() == .unauthenticated)

        try await manager.bootstrapGuestSessionIfNeeded()

        #expect(await iterator.next() == .guest(userID: "usr_ab12cd"))
    }

    @Test func protokolUzerindenDurumOkunur() async throws {
        try stubGuestSuccess()
        let managing: any SessionManaging = manager

        try await managing.bootstrapGuestSessionIfNeeded()

        #expect(await managing.state == .guest(userID: "usr_ab12cd"))
    }

    // MARK: - Refresh zinciri koptuğunda (05 §4.2)

    @Test func misafirOturumdaRefreshDusunceSessizceYenidenBootstrapEder() async throws {
        try seedStoredSession(userID: "usr_eski")
        try await manager.bootstrapGuestSessionIfNeeded()
        try stubGuestSuccess(userID: "usr_yeni")

        let token = await manager.handleRefreshFailure()

        #expect(token == "at_1")
        #expect(manager.state == .guest(userID: "usr_yeni"))
        #expect(apiClient.receivedPaths == ["/auth/guest"])
        #expect(try secureStore.string(forKey: .accessToken) == "at_1")
        #expect(try secureStore.string(forKey: .refreshToken) == "rt_1")
    }

    @Test func hicOturumYokkenRefreshDusunceMisafirKurar() async throws {
        try stubGuestSuccess()

        let token = await manager.handleRefreshFailure()

        #expect(token == "at_1")
        #expect(manager.state == .guest(userID: "usr_ab12cd"))
    }

    @Test func misafirYenidenBootstrapDaDuserseNilDoner() async throws {
        try seedStoredSession()
        try await manager.bootstrapGuestSessionIfNeeded()
        apiClient.stub("/auth/guest", throwing: .network(.offline))

        let token = await manager.handleRefreshFailure()

        #expect(token == nil)
    }

    @Test func bagliHesaptaRefreshDusunceLoggedOutOlurVeTokenlarSilinir() async throws {
        try seedStoredSession(provider: .google, userID: "usr_linked")
        try await manager.bootstrapGuestSessionIfNeeded()

        let token = await manager.handleRefreshFailure()

        #expect(token == nil)
        #expect(manager.state == .loggedOut(previousUserID: "usr_linked", provider: .google))
        #expect(apiClient.receivedPaths.isEmpty)
        #expect(try secureStore.string(forKey: .accessToken) == nil)
        #expect(try secureStore.string(forKey: .refreshToken) == nil)
        // Snapshot bilinçli KORUNUR: relaunch'ta loggedOut kaydı olarak okunur (05/03:
        // bağlı hesapta misafire dönülmez, yeniden giriş Profil'den).
        let snapshotData = try #require(try secureStore.data(forKey: .sessionSnapshot))
        let snapshot = try JSONDecoder().decode(StoredSessionSnapshot.self, from: snapshotData)
        #expect(snapshot == StoredSessionSnapshot(userID: "usr_linked", provider: .google))
    }

    @Test func loggedOutSonrasiYenidenBootstrapMisafirKurmaz() async throws {
        try seedStoredSession(provider: .google, userID: "usr_linked")
        try await manager.bootstrapGuestSessionIfNeeded()
        _ = await manager.handleRefreshFailure()

        let state = try await manager.bootstrapGuestSessionIfNeeded()

        #expect(state == .loggedOut(previousUserID: "usr_linked", provider: .google))
        #expect(manager.state == .loggedOut(previousUserID: "usr_linked", provider: .google))
        #expect(apiClient.receivedPaths.isEmpty)
    }

    @Test func loggedOutKaydiRelaunchtaKorunurVeMisafirKurulmaz() async throws {
        try seedStoredSession(provider: .apple, userID: "usr_linked")
        try await manager.bootstrapGuestSessionIfNeeded()
        _ = await manager.handleRefreshFailure()

        // Relaunch: aynı Keychain, yeni SessionManager örneği.
        let relaunched = SessionManager(
            apiClient: apiClient,
            secureStore: secureStore,
            clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
        )
        let state = try await relaunched.bootstrapGuestSessionIfNeeded()

        #expect(state == .loggedOut(previousUserID: "usr_linked", provider: .apple))
        #expect(relaunched.state == .loggedOut(previousUserID: "usr_linked", provider: .apple))
        #expect(apiClient.receivedPaths.isEmpty)
    }

    @Test func bootstrapEdilmemisBagliSnapshotDaLoggedOutaDuser() async throws {
        try seedStoredSession(provider: .email, userID: "usr_linked")

        let token = await manager.handleRefreshFailure()

        #expect(token == nil)
        #expect(manager.state == .loggedOut(previousUserID: "usr_linked", provider: .email))
    }

    // MARK: - İptal (CancellationError hataya dönüşmez)

    @Test func iptalEdilenBootstrapGuestBootstrapFailedUretmez() async {
        let cancellingManager = SessionManager(
            apiClient: CancellingAPIClient(),
            secureStore: secureStore,
            clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
        )

        await #expect(throws: CancellationError.self) {
            try await cancellingManager.bootstrapGuestSessionIfNeeded()
        }
        #expect(cancellingManager.state == .unauthenticated)
    }

    @Test func loggedOutDurumundaDeviceIdKorunur() async throws {
        try stubGuestSuccess()
        try await manager.bootstrapGuestSessionIfNeeded()
        let deviceID = try secureStore.string(forKey: .deviceID)
        // Hesap bağlanmış gibi snapshot'ı güncelle, sonra refresh düşür.
        try seedStoredSession(provider: .apple, userID: "usr_ab12cd")

        _ = await manager.handleRefreshFailure()

        #expect(try secureStore.string(forKey: .deviceID) == deviceID)
    }
}

struct SessionStateTests {
    @Test func loggedOutKimliksizVeYetkisizdir() {
        let state = SessionState.loggedOut(previousUserID: "usr_1", provider: .apple)

        #expect(state.userID == nil)
        #expect(!state.isAuthenticated)
    }
}
