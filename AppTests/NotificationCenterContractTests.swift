import AppFoundation
import DiscoverKit
import Foundation
import ProfileKit
import XCTest
@testable import ShortSeriesApp

/// SS-144 BildirimMerkezi App entegrasyon sözleşmeleri (kompozisyonsuz). Dört alan:
///  1. Registry-contract: `NotificationCenterModel`'in emit ettiği iki event registry'de KAYITLI olmalı
///     (aksi halde `AppAnalyticsTracker` strictInDebug her açılışta `assertionFailure` tetikler) — ve
///     gerçek model emisyonu bilinen adlarla eşleşmeli (fault üretmemeli).
///  2. Rota köprüsü: `NotificationRouteBridge` ham deep-link String'i push ile AYNI şekilde
///     `DeepLinkRoute`'a çözer; URL'e çevrilemeyen / boş / bilinmeyen path → nil (App `Kesfet` fallback'i).
///  3. Canlı gateway decode: `GET /notifications` cursor sayfa zarfı (`{ items, nextCursor }`) →
///     `NotificationsPage` (05 §7.1); okundu/sil uçları doğru path + gövde ile çağrılır.
///  4. AppRoute genişlemesi: `.bildirimMerkezi` Profil stack push hedefi olarak eklenmiş.
///
/// Bu hedef CI'da KOŞMAZ (App target CI dışı) — lokal doğrulama.
final class NotificationCenterContractTests: XCTestCase {
    // MARK: - 1. Registry-contract (yeni iki event kayıtlı + model emisyonuyla eşleşir)

    func testNotificationEventsAreRegistered() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("notification_center_opened"), .valid)
        XCTAssertEqual(AnalyticsEventRegistry.validate("notification_item_tapped"), .valid)
    }

    /// Model gerçek emisyonu (open + item tap) registry ile eşleşir → `AppAnalyticsTracker` fault
    /// üretmez. Model doğrudan sürülür (fake gateway + spy analytics); parametre anahtarları (§3.6)
    /// `unread_count` / `type` / `route` beklenir.
    @MainActor
    func testModelEmissionMatchesRegistryWithoutFault() async {
        let spy = SpyAnalytics()
        let notification = Self.makeNotification(id: "n1", route: "shortseries://series/srs_abc123", isRead: false)
        let gateway = FakeNotificationsGateway(page: NotificationsPage(items: [notification], nextCursor: nil))
        let model = NotificationCenterModel(gateway: gateway, analytics: spy, delegate: nil)

        // Public `load()` doğrudan sürülür (deterministik await; `pendingWork()` ProfileKit-internal).
        await model.load()
        model.open(notification)

        // İlk yükleme çözülünce `notification_center_opened {unread_count}` bir kez atılmış olmalı.
        let opened = spy.events.first { $0.name == "notification_center_opened" }
        XCTAssertNotNil(opened, "ilk yükleme çözülünce notification_center_opened atılmalı")
        XCTAssertEqual(opened?.parameters["unread_count"], .int(1))

        // Satır dokunuşu `notification_item_tapped {type, route}` atmalı.
        let tapped = spy.events.first { $0.name == "notification_item_tapped" }
        XCTAssertEqual(tapped?.parameters["type"], .string("new_episode"))
        XCTAssertEqual(tapped?.parameters["route"], .string("shortseries://series/srs_abc123"))

        // Emit edilen HER ad registry'de bilinmeli (strictInDebug crash regresyonu guard'ı).
        for event in spy.events {
            XCTAssertEqual(
                AnalyticsEventRegistry.validate(event.name), .valid,
                "model '\(event.name)' emit etti ama registry'de kayıtlı değil (strictInDebug crash)"
            )
        }
    }

    // MARK: - 2. Rota köprüsü (dolu route → dispatch adayı, boş/geçersiz → Kesfet fallback)

    func testRouteBridgeResolvesValidCustomSchemeRoute() {
        XCTAssertEqual(
            NotificationRouteBridge.route(from: "shortseries://series/srs_abc123"),
            .series(id: SeriesID("srs_abc123"))
        )
        XCTAssertEqual(
            NotificationRouteBridge.route(from: "shortseries://notifications"),
            .notifications
        )
        XCTAssertEqual(
            NotificationRouteBridge.route(from: "https://shortseries.app/s/srs_abc123/e/3"),
            .episode(seriesId: SeriesID("srs_abc123"), number: 3)
        )
    }

    /// Boş / whitespace / URL'e çevrilemeyen / bilinmeyen path → nil (App `Kesfet` fallback'ini uygular).
    func testRouteBridgeReturnsNilForInvalidRoutes() {
        XCTAssertNil(NotificationRouteBridge.route(from: ""))
        XCTAssertNil(NotificationRouteBridge.route(from: "   "))
        XCTAssertNil(NotificationRouteBridge.route(from: "shortseries://unknown-surface"))
        // Biçimsiz içerik ID'si (regex geçmez) → nil (path injection savunması, §8.4 kural 4).
        XCTAssertNil(NotificationRouteBridge.route(from: "shortseries://series/NOT_AN_ID"))
    }

    // MARK: - 3. Canlı gateway decode (GET /notifications sayfa zarfı + mutasyon uçları)

    func testGatewayFetchDecodesCursorPageEnvelope() async throws {
        let client = StubAPIClient()
        let json = """
        { "items": [
            { "id": "ntf_1", "type": "new_episode", "title": "Yeni bölüm",
              "body": "3. bölüm yayında", "createdAt": "2026-07-11T09:31:02Z",
              "route": "shortseries://series/srs_abc123/episode/3", "isRead": false },
            { "id": "ntf_2", "type": "brand_new_server_type", "title": "Duyuru",
              "body": "Kampanya", "createdAt": "2026-07-10T08:00:00Z", "route": "", "isRead": true }
          ], "nextCursor": "eyJvZmZzZXQiOiIyMCJ9" }
        """
        client.stub("/notifications", data: Data(json.utf8))
        let gateway = APINotificationsGateway(client: client)

        let page = try await gateway.fetch(cursor: nil)

        XCTAssertEqual(page.items.count, 2)
        XCTAssertEqual(page.items.first?.id, NotificationID("ntf_1"))
        XCTAssertEqual(page.items.first?.type, .newEpisode)
        XCTAssertFalse(page.isLastPage)
        XCTAssertEqual(page.nextCursor, "eyJvZmZzZXQiOiIyMCJ9")
        // İleri-uyumluluk: bilinmeyen sunucu tipi düşürülmez → `.unknown`.
        XCTAssertEqual(page.items.last?.type, .unknown)
    }

    func testGatewayFetchTreatsNullCursorAsLastPage() async throws {
        let client = StubAPIClient()
        client.stub("/notifications", data: Data(#"{ "items": [], "nextCursor": null }"#.utf8))
        let page = try await APINotificationsGateway(client: client).fetch(cursor: nil)
        XCTAssertTrue(page.items.isEmpty)
        XCTAssertTrue(page.isLastPage)
    }

    /// Bozuk sunucu son sayfayı `nextCursor: ""` (null yerine) döndürürse boş cursor `nil`'e normalize
    /// edilir → `isLastPage` true. Aksi halde `canLoadMore` true kalır ama istek boş cursor'u sayfa-1
    /// sayar → scroll-to-bottom sayfa-1'i sonsuz yeniden çeker (kardeş adaptör `!isEmpty` konvansiyonu).
    func testGatewayFetchNormalizesEmptyCursorToNil() async throws {
        let client = StubAPIClient()
        client.stub("/notifications", data: Data(#"{ "items": [], "nextCursor": "" }"#.utf8))
        let page = try await APINotificationsGateway(client: client).fetch(cursor: nil)
        XCTAssertNil(page.nextCursor)
        XCTAssertTrue(page.isLastPage)
    }

    /// Yalnız-boşluk cursor da son sayfa sayılır (trim → boş → nil).
    func testGatewayFetchNormalizesWhitespaceCursorToNil() async throws {
        let client = StubAPIClient()
        client.stub("/notifications", data: Data(#"{ "items": [], "nextCursor": "   " }"#.utf8))
        let page = try await APINotificationsGateway(client: client).fetch(cursor: nil)
        XCTAssertNil(page.nextCursor)
        XCTAssertTrue(page.isLastPage)
    }

    func testGatewayFetchAppendsCursorQueryParameter() async throws {
        let client = StubAPIClient()
        client.stub("/notifications", data: Data(#"{ "items": [], "nextCursor": null }"#.utf8))
        _ = try await APINotificationsGateway(client: client).fetch(cursor: "abc123")
        XCTAssertEqual(client.receivedQueries.first?.first, URLQueryItem(name: "cursor", value: "abc123"))
    }

    func testGatewayMutationsHitExpectedPaths() async throws {
        let client = StubAPIClient()
        client.stub("/notifications/read", data: Data("{}".utf8))
        client.stub("/notifications/read-all", data: Data("{}".utf8))
        client.stub("/notifications/ntf_9", data: Data("{}".utf8))
        let gateway = APINotificationsGateway(client: client)

        try await gateway.markRead(ids: [NotificationID("ntf_1"), NotificationID("ntf_2")])
        try await gateway.markAllRead()
        try await gateway.delete(id: NotificationID("ntf_9"))

        XCTAssertTrue(client.receivedPaths.contains("/notifications/read"))
        XCTAssertTrue(client.receivedPaths.contains("/notifications/read-all"))
        XCTAssertTrue(client.receivedPaths.contains("/notifications/ntf_9"))
    }

    /// Boş `ids` ile `markRead` ağ isteği YAPMAZ (gereksiz POST guard'ı).
    func testGatewayMarkReadNoopsForEmptyIDs() async throws {
        let client = StubAPIClient()
        try await APINotificationsGateway(client: client).markRead(ids: [])
        XCTAssertTrue(client.receivedPaths.isEmpty)
    }

    func testGatewayFetchPropagatesOfflineError() async {
        let client = StubAPIClient()
        client.stub("/notifications", error: .network(.offline))
        do {
            _ = try await APINotificationsGateway(client: client).fetch(cursor: nil)
            XCTFail("offline hatası fırlatmalı")
        } catch let error as AppError {
            XCTAssertEqual(error, .network(.offline))
        } catch {
            XCTFail("beklenmeyen hata tipi: \(error)")
        }
    }

    // MARK: - 4. AppRoute genişlemesi

    func testAppRouteBildirimMerkeziIsHashable() {
        XCTAssertEqual(AppRoute.bildirimMerkezi, AppRoute.bildirimMerkezi)
        XCTAssertNotEqual(AppRoute.bildirimMerkezi, AppRoute.ayarlar)
    }

    // MARK: - Fixtures

    private static func makeNotification(id: String, route: String, isRead: Bool) -> AppNotification {
        AppNotification(
            id: NotificationID(id),
            type: .newEpisode,
            title: "Yeni bölüm",
            body: "3. bölüm yayında",
            createdAt: Date(timeIntervalSince1970: 1_752_226_262),
            route: route,
            isRead: isRead
        )
    }
}

// MARK: - Test doubles

/// Yerel stub `APIClientProtocol` — AppTests target'ı `AppFoundationTestSupport`'u linklemediğinden
/// (yalnız `ShortSeriesApp` bağımlılığı) MockAPIClient yerine dar bir yerel çift kullanılır. Yol ile
/// anahtarlı stub; canlı `APIClient` ile aynı `JSONDecoder.shortSeriesDefault()` sınır dönüşümü.
private final class StubAPIClient: APIClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: Result<Data, AppError>] = [:]
    private var paths: [String] = []
    private var queries: [[URLQueryItem]] = []
    private let decoder = JSONDecoder.shortSeriesDefault()

    var receivedPaths: [String] {
        lock.withLock { paths }
    }

    var receivedQueries: [[URLQueryItem]] {
        lock.withLock { queries }
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
            queries.append(endpoint.query)
            return responses[endpoint.path]
        }
        guard let result else {
            throw AppError.unexpected(underlying: "StubAPIClient: '\(endpoint.path)' için stub yok")
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

private struct FakeNotificationsGateway: NotificationsGateway {
    let page: NotificationsPage

    func fetch(cursor _: String?) async throws -> NotificationsPage {
        page
    }

    func markRead(ids _: [NotificationID]) async throws {}
    func markAllRead() async throws {}
    func delete(id _: NotificationID) async throws {}
}

private final class SpyAnalytics: AnalyticsTracking, @unchecked Sendable {
    struct Event {
        let name: String
        let parameters: [String: AnalyticsValue]
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    var events: [Event] {
        lock.withLock { recorded }
    }

    func track(_ name: String, parameters: [String: AnalyticsValue]) {
        lock.withLock { recorded.append(Event(name: name, parameters: parameters)) }
    }
}
