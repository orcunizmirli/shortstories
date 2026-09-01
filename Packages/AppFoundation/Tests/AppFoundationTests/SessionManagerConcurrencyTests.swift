import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

/// Audit MEDIUM: uçuştaki auth operasyonları (misafir bootstrap / token refresh) session-generation ile
/// fence edilmeli + linkSession torn-write güvenli sıra. Eşzamanlı bir link/switch, uçuştaki misafir
/// yanıtının linked oturumu ezip hesabı sessizce misafire indirgemesine yol açıyordu (WalletKit
/// account-epoch ile aynı sınıf). Deterministik gate (wall-clock YOK → CI flake yok).
@MainActor
struct SessionManagerConcurrencyTests {
    /// Continuation-tabanlı kapı: `send` `entered`'ı açar sonra `proceed`'i bekler → test tam olarak
    /// "istek uçuşta" anında araya girebilir.
    private final class GatedAPIClient: APIClientProtocol, @unchecked Sendable {
        let inner: MockAPIClient
        private let entered = OneShotGate()
        private let proceed = OneShotGate()
        init(_ inner: MockAPIClient) {
            self.inner = inner
        }

        func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
            entered.open()
            await proceed.wait()
            return try await inner.send(endpoint)
        }

        func awaitEntered() async {
            await entered.wait()
        }

        func allow() {
            proceed.open()
        }
    }

    private final class OneShotGate: @unchecked Sendable {
        private let lock = NSLock()
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func open() {
            let resume = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                opened = true
                defer { waiters.removeAll() }
                return waiters
            }
            for waiter in resume {
                waiter.resume()
            }
        }

        func wait() async {
            await withCheckedContinuation { cont in
                let now = lock.withLock { () -> Bool in
                    if opened {
                        return true
                    }
                    waiters.append(cont)
                    return false
                }
                if now {
                    cont.resume()
                }
            }
        }
    }

    private func makeManager(_ apiClient: any APIClientProtocol, _ store: any SecureStoring) -> SessionManager {
        SessionManager(
            apiClient: apiClient,
            secureStore: store,
            clientInfo: SessionClientInfo(platform: "ios", appVersion: "1.0.0", locale: "en-US")
        )
    }

    // MARK: - Finding 3: linkSession torn-write (refresh-first) saatli bombayı önler

    @Test func linkSessionRefreshYazimiKoparsaAccessYazilmaz() async throws {
        // Refresh yazımı koparsa "yeni access + eski refresh" saatli bombası oluşmamalı → access ESKİ kalır.
        let inner = MockAPIClient()
        try inner.stub("/auth/guest", returning: ["userId": "g1", "accessToken": "at_1", "refreshToken": "rt_1"])
        let store = WriteFailingSecureStore(failWriteFor: .refreshToken)
        let mgr = makeManager(inner, store)
        try await mgr.bootstrapGuestSessionIfNeeded() // at_1 / rt_1 seed

        store.arm() // sonraki refreshToken yazımı koparacak
        mgr.linkSession(userID: "g1", provider: .apple, accessToken: "at_linked", refreshToken: "rt_linked")

        // Kalıcılaştırma koptu → kimlik yükseltilmez; state (rolled-back) guest token'la tutarlı kalır
        // (auth hunt MEDIUM: state ile Keychain'deki token ayrışmaz → UI ↔ sunucu-kimliği tutarlı).
        #expect(mgr.state == .guest(userID: "g1"))
        // Access ESKİ kalmalı (refresh koptuğu için yazılmadı) → saatli bomba yok.
        #expect(try store.string(forKey: .accessToken) == "at_1")
        #expect(try store.string(forKey: .refreshToken) == "rt_1")
    }

    // MARK: - Finding 2: uçuştaki misafir bootstrap linked oturumu ezmemeli

    @Test func inFlightGuestBootstrapLinkedOturumuEzmez() async throws {
        let inner = MockAPIClient()
        try inner.stub("/auth/guest", returning: ["userId": "guestX", "accessToken": "at_g", "refreshToken": "rt_g"])
        let store = MockSecureStore()
        let gated = GatedAPIClient(inner)
        let mgr = makeManager(gated, store)

        let bootstrap = Task { try await mgr.bootstrapGuestSessionIfNeeded() }
        await gated.awaitEntered() // /auth/guest uçuşta (gate'te asılı)

        // Link araya girer: generation bump + linked token'lar + .linked.
        mgr.linkSession(userID: "user456", provider: .apple, accessToken: "at_linked", refreshToken: "rt_linked")

        gated.allow() // misafir yanıtı şimdi çözülür
        _ = try? await bootstrap.value

        // Misafir yanıtı BAYAT → linked oturum korunur, misafire indirgenMEZ.
        #expect(mgr.state == .linked(userID: "user456", provider: .apple))
        #expect(try store.string(forKey: .accessToken) == "at_linked")
        #expect(try store.string(forKey: .refreshToken) == "rt_linked")
    }

    // MARK: - Finding 1: refresh uçuştayken link access'i rotasyonlarsa refresh yanıtı ezmez

    /// `send` sırasında Keychain access token'ını rotasyonlar (eşzamanlı `linkSession`'ı deterministik
    /// taklit) — sonra normal yanıtı döndürür.
    private final class RotatingDuringRefreshClient: APIClientProtocol, @unchecked Sendable {
        let inner = MockAPIClient()
        let store: MockSecureStore
        let rotateTo: String
        init(store: MockSecureStore, rotateTo: String) {
            self.store = store
            self.rotateTo = rotateTo
        }

        func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
            try? store.setString(rotateTo, forKey: .accessToken) // link araya girdi: access rotasyonlandı
            return try await inner.send(endpoint)
        }
    }

    @Test func refreshUcustaykenLinkAccessiRotasyonlarsaYanitEzilmez() async throws {
        let store = MockSecureStore()
        try store.setString("at_old", forKey: .accessToken)
        try store.setString("rt_old", forKey: .refreshToken)
        let client = RotatingDuringRefreshClient(store: store, rotateTo: "at_linked")
        try client.inner.stub("/auth/refresh", returning: ["accessToken": "at_new", "refreshToken": "rt_new"])
        let coordinator = TokenRefreshCoordinator(apiClient: client, secureStore: store)

        let token = try await coordinator.refreshAccessToken()

        #expect(token == "at_linked") // güncel linked access döner, at_new DEĞİL
        #expect(try store.string(forKey: .accessToken) == "at_linked") // ezilmedi
        #expect(try store.string(forKey: .refreshToken) == "rt_old") // refresh yanıtı DÜŞÜRÜLDÜ
    }
}
