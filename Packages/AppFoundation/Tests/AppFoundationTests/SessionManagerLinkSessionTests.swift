import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

/// Canlı bağlama yükseltmesi (`linkSession` — 05 §4.2 `POST /auth/link`/`switch` başarısı):
/// misafir durumdan `.linked`e canlı geçiş, `stateUpdates` yayını, Keychain tutarlılığı ve
/// tekrar-idempotentlik.
@MainActor
struct SessionManagerLinkSessionTests {
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

    private func bootstrapGuest(userID: String = "usr_ab12cd") async throws {
        try apiClient.stub(
            "/auth/guest",
            returning: ["userId": userID, "accessToken": "at_1", "refreshToken": "rt_1"]
        )
        try await manager.bootstrapGuestSessionIfNeeded()
    }

    @Test func linkSessionMisafirdenLinkedeYukseltirVeKeychainiGunceller() async throws {
        try await bootstrapGuest()
        #expect(manager.state == .guest(userID: "usr_ab12cd"))

        // Sunucu userId'yi KORUR (aynı hesaba kimlik eklenir); rotasyonlu token'lar döner.
        manager.linkSession(
            userID: "usr_ab12cd",
            provider: .apple,
            accessToken: "at_linked",
            refreshToken: "rt_linked"
        )

        #expect(manager.state == .linked(userID: "usr_ab12cd", provider: .apple))
        // Token + snapshot Keychain'e yazıldı → relaunch `.linked` görür.
        #expect(try secureStore.string(forKey: .accessToken) == "at_linked")
        #expect(try secureStore.string(forKey: .refreshToken) == "rt_linked")
        let snapshotData = try #require(try secureStore.data(forKey: .sessionSnapshot))
        let snapshot = try JSONDecoder().decode(StoredSessionSnapshot.self, from: snapshotData)
        #expect(snapshot == StoredSessionSnapshot(userID: "usr_ab12cd", provider: .apple))
    }

    @Test func linkSessionStateUpdatesYayinlar() async throws {
        try await bootstrapGuest()
        var iterator = manager.stateUpdates.makeAsyncIterator()
        #expect(await iterator.next() == .guest(userID: "usr_ab12cd"))

        manager.linkSession(userID: "usr_ab12cd", provider: .google, accessToken: "at_l", refreshToken: "rt_l")

        #expect(await iterator.next() == .linked(userID: "usr_ab12cd", provider: .google))
    }

    @Test func linkSessionTekrarIdempotenttir() async throws {
        try await bootstrapGuest()
        var iterator = manager.stateUpdates.makeAsyncIterator()
        #expect(await iterator.next() == .guest(userID: "usr_ab12cd"))

        manager.linkSession(userID: "usr_ab12cd", provider: .apple, accessToken: "at_l", refreshToken: "rt_l")
        #expect(await iterator.next() == .linked(userID: "usr_ab12cd", provider: .apple))

        // İkinci ÖZDEŞ çağrı: durum aynı kalır, gereksiz yayın YAPILMAZ.
        manager.linkSession(userID: "usr_ab12cd", provider: .apple, accessToken: "at_l", refreshToken: "rt_l")
        #expect(manager.state == .linked(userID: "usr_ab12cd", provider: .apple))

        // Kanıt: sonraki GERÇEK değişim doğrudan alınır — araya kopya .linked(.apple) GİRMEZ.
        manager.linkSession(userID: "usr_ab12cd", provider: .google, accessToken: "at_l2", refreshToken: "rt_l2")
        #expect(await iterator.next() == .linked(userID: "usr_ab12cd", provider: .google))
    }

    @Test func linkSessionSonrasiBootstrapNoOptur() async throws {
        try await bootstrapGuest()
        manager.linkSession(userID: "usr_ab12cd", provider: .apple, accessToken: "at_l", refreshToken: "rt_l")

        // Bağlı durum authenticated'dır → yeniden bootstrap ağa çıkmaz, `.linked` korunur.
        let state = try await manager.bootstrapGuestSessionIfNeeded()

        #expect(state == .linked(userID: "usr_ab12cd", provider: .apple))
        #expect(apiClient.receivedPaths == ["/auth/guest"])
    }

    @Test func linkSessionProtokolUzerindenCagirilir() async throws {
        try await bootstrapGuest()
        let managing: any SessionManaging = manager

        await managing.linkSession(userID: "usr_ab12cd", provider: .email, accessToken: "at_l", refreshToken: "rt_l")

        #expect(await managing.state == .linked(userID: "usr_ab12cd", provider: .email))
    }
}
