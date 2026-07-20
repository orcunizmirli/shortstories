import AppFoundation
import Foundation
import ProfileKit
import XCTest
@testable import ShortSeriesApp

/// SS-132 HIGH veri-sızıntısı düzeltmesi (05 §3.3 / §575): 409 "mevcut hesabıma geç"
/// (`switchToExistingAccount`) yerel-veri yaşam döngüsünü ZORUNLU sırayla yürütmeli:
/// (a) flush pendingUpload (misafir verisi misafir hesabına, switch ÖNCESİ — misafir token'ı),
/// (b) POST /auth/switch + oturum `.linked`'e yükselir,
/// (c) yerel store SIFIRLA (yeni hesap misafir verisini görmez),
/// (d) refetch tetikle (yeni hesabın sunucu durumu çekilir).
/// Adaptör yalnız orkestrasyonu doğrular; store reset/flush davranışı AppFoundation/LibraryKit'te.
final class AccountSwitchDataFlowTests: XCTestCase {
    private func makeSwitchResponseData(userID: String, provider: String) -> Data {
        let session = #"{"userId":"\#(userID)","accessToken":"at","refreshToken":"rt","provider":"\#(provider)"}"#
        return Data(#"{"session":\#(session),"provider":"\#(provider)"}"#.utf8)
    }

    func testSwitchFlushesBeforeThenResetsThenRefetchesAfterSwitch() async throws {
        let client = StubSwitchAPIClient()
        client.stub("/auth/switch", data: makeSwitchResponseData(userID: "existing-1", provider: "apple"))
        let session = StubSwitchSession(state: .guest(userID: "guest-1"))
        let coordinator = SpyAccountSwitchDataCoordinator(session: session)
        let adapter = APIAccountLinkingService(
            client: client,
            session: session,
            switchDataCoordinator: coordinator
        )

        let conflict = AccountLinkConflict(
            existingAccountMasked: "usr_**ef",
            switchToken: "tok",
            willDiscardGuestData: true
        )
        let summary = try await adapter.switchToExistingAccount(conflict)

        // Zorunlu sıra (§575): flush → reset → refetch.
        XCTAssertEqual(coordinator.callOrder, ["flush", "reset", "refetch"])
        // flush, switch ÖNCESİ misafir oturumuyla koşar (misafir token'ı → misafir hesabı).
        XCTAssertEqual(coordinator.stateAtFlush, .guest(userID: "guest-1"))
        // reset + refetch, switch SONRASI (oturum bağlıya yükseldi) → yeni hesap misafir verisi görmez.
        XCTAssertEqual(coordinator.stateAtReset, .linked(userID: "existing-1", provider: .apple))
        XCTAssertEqual(coordinator.stateAtRefetch, .linked(userID: "existing-1", provider: .apple))
        // Oturum bağlıya yükseldi + özet doğru sağlayıcıyı taşır.
        XCTAssertEqual(session.linkSessionCalls, 1)
        XCTAssertEqual(summary.kind, .linked(provider: .apple))
        XCTAssertEqual(client.receivedPaths, ["/auth/switch"])
    }

    /// Switch GERÇEK hata verirse (ağ/5xx) yerel store SIFIRLANMAZ ve refetch tetiklenmez —
    /// yerel misafir verisi korunur (sıfır-kayıp). flush yine denenmiştir (best-effort, throw etmez).
    func testSwitchFailureFlushesButNeverResetsOrRefetches() async {
        let client = StubSwitchAPIClient()
        client.stub("/auth/switch", error: .network(.offline))
        let session = StubSwitchSession(state: .guest(userID: "guest-1"))
        let coordinator = SpyAccountSwitchDataCoordinator(session: session)
        let adapter = APIAccountLinkingService(
            client: client,
            session: session,
            switchDataCoordinator: coordinator
        )
        let conflict = AccountLinkConflict(existingAccountMasked: "m", switchToken: "tok", willDiscardGuestData: true)

        do {
            _ = try await adapter.switchToExistingAccount(conflict)
            XCTFail("switch hatası fırlamalıydı")
        } catch {
            // beklenen: gerçek hata yüzeye çıkar
        }

        XCTAssertEqual(coordinator.callOrder, ["flush"])
        XCTAssertEqual(session.linkSessionCalls, 0)
    }
}

// MARK: - Test doubles (AppTests `AppFoundationTestSupport`'u linklemez → yerel dar çiftler)

/// Yol ile anahtarlı stub `APIClientProtocol`; canlı `APIClient` ile aynı sınır dönüşümü.
private final class StubSwitchAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<Data, AppError>] = [:]
    private var paths: [String] = []
    private let decoder = JSONDecoder.shortSeriesDefault()

    var receivedPaths: [String] {
        lock.withLock { paths }
    }

    func stub(_ path: String, data: Data) {
        lock.withLock { responses[path] = .success(data) }
    }

    func stub(_ path: String, error: AppError) {
        lock.withLock { responses[path] = .failure(error) }
    }

    func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        let result: Result<Data, AppError>? = lock.withLock {
            paths.append(endpoint.path)
            return responses[endpoint.path]
        }
        guard let result else {
            throw AppError.unexpected(underlying: "StubSwitchAPIClient: '\(endpoint.path)' için stub yok")
        }
        switch result {
        case let .success(data):
            do {
                return try decoder.decode(E.Response.self, from: data)
            } catch {
                throw AppError.network(.decoding)
            }
        case let .failure(error):
            throw error
        }
    }
}

/// `linkSession` çağrısında durumu `.linked`'e yükselten dar `SessionManaging` çifti.
private final class StubSwitchSession: SessionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentState: SessionState
    private(set) var linkSessionCalls = 0

    init(state: SessionState) {
        currentState = state
    }

    var state: SessionState {
        get async { lock.withLock { currentState } }
    }

    var stateUpdates: AsyncStream<SessionState> {
        AsyncStream { $0.finish() }
    }

    @discardableResult
    func bootstrapGuestSessionIfNeeded() async throws -> SessionState {
        lock.withLock { currentState }
    }

    func linkSession(userID: String, provider: AuthProvider, accessToken _: String, refreshToken _: String) async {
        lock.withLock {
            currentState = .linked(userID: userID, provider: provider)
            linkSessionCalls += 1
        }
    }
}

/// Orkestrasyon sırasını + her adımda gözlenen oturum durumunu kaydeden spy koordinatör.
private final class SpyAccountSwitchDataCoordinator: AccountSwitchDataCoordinating, @unchecked Sendable {
    private let session: any SessionManaging
    private let lock = NSLock()
    private(set) var callOrder: [String] = []
    private(set) var stateAtFlush: SessionState?
    private(set) var stateAtReset: SessionState?
    private(set) var stateAtRefetch: SessionState?

    init(session: any SessionManaging) {
        self.session = session
    }

    func flushPendingGuestData() async {
        let observed = await session.state
        lock.withLock { stateAtFlush = observed; callOrder.append("flush") }
    }

    func resetLocalUserData() async {
        let observed = await session.state
        lock.withLock { stateAtReset = observed; callOrder.append("reset") }
    }

    func refetchForNewAccount() async {
        let observed = await session.state
        lock.withLock { stateAtRefetch = observed; callOrder.append("refetch") }
    }
}
