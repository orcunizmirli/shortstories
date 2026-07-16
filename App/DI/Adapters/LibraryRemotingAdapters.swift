import AppFoundation
import Foundation
import LibraryKit

// LibraryKit senkron backend portlarının canlı adaptörleri (SS-121/122/123, 05 §3.3). Portlar
// LibraryKit'te tanımlı (tüketici); App onları AppFoundation `APIClientProtocol`üne (üretici)
// köprüler. Endpoint TANIMLARI kompozisyon kökündedir: bu uçlar hiçbir feature paketine ait değildir
// (Listem/izleme çapraz-keser) ve App tüm modülleri bağlayabilir (R1 istisnası).

// MARK: - Favoriler (PUT/DELETE /me/favorites/{seriesId})

/// LibraryKit `FavoritesRemoting` → `APIClient`. İki uç da idempotenttir; offline'da APIClient
/// `URLError` → `AppError.network(.offline)` eşler ve `FavoritesService` kaydı kuyrukta bırakır.
struct APIFavoritesRemoting: FavoritesRemoting {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func putFavorite(_ seriesID: SeriesID) async throws {
        _ = try await client.send(FavoriteMutationEndpoint(seriesID: seriesID, method: .put))
    }

    func deleteFavorite(_ seriesID: SeriesID) async throws {
        _ = try await client.send(FavoriteMutationEndpoint(seriesID: seriesID, method: .delete))
    }
}

/// `PUT/DELETE /me/favorites/{seriesId}` (05 §4.10). Gövdesizdir; sunucu JSON zarf (`{}`) döndürür
/// (`EmptyResponse`). Otomatik-retry YOK: offline/hatayı `FavoritesService` kuyruğu üstlenir.
private struct FavoriteMutationEndpoint: Endpoint {
    typealias Response = EmptyResponse

    let seriesID: SeriesID
    let method: HTTPMethod

    var path: String {
        "/me/favorites/\(seriesID.rawValue.pathSegmentEscaped)"
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

// MARK: - İzleme ilerlemesi (POST/GET /playback/progress)

/// LibraryKit `WatchProgressRemoting` → `APIClient`. Batch push (`POST`) + birleşik pull (`GET`);
/// `WatchProgressRecord` ↔ wire eşlemesi burada (domain tipi Codable değildir).
struct APIWatchProgressRemoting: WatchProgressRemoting {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func uploadProgress(_ records: [WatchProgressRecord]) async throws {
        _ = try await client.send(
            ProgressUploadEndpoint(entries: records.map(WatchProgressWire.init(record:)))
        )
    }

    func fetchServerProgress() async throws -> [WatchProgressRecord] {
        // `GET /me/history?cursor=` cursor-sayfalıdır (05 §7.1 `{ items, nextCursor }`); port TEK
        // birleşik liste döndürdüğü için tüm sayfalar `nextCursor` boşalana dek takip edilir. Sunucu
        // bozuk davranışına karşı sayfa tavanı (`maxHistoryPages`) sonsuz döngüyü engeller.
        var records: [WatchProgressRecord] = []
        var cursor: String?
        var page = 0
        repeat {
            let response = try await client.send(HistoryFetchEndpoint(cursor: cursor))
            records.append(contentsOf: response.items.map(\.record))
            cursor = response.nextCursor
            page += 1
        } while cursor?.isEmpty == false && page < Self.maxHistoryPages
        return records
    }

    /// Birleşik geçmiş sayfalamasının güvenlik tavanı (cursor asla `null`a düşmezse döngü kırılır).
    private static let maxHistoryPages = 50
}

/// `POST /playback/progress` — bekleyen kayıtları batch yükler (05 §4.4). İstek gövdesi zarf anahtarı
/// **`entries`**'tir (sözleşme §4.4 örneği). 200 yanıtı sunucunun birleşik son durumunu (`{ "merged":
/// [...] }`) taşır ama port `uploadProgress` `Void` döndürdüğü ve `synchronize()` hemen ardından
/// `fetchServerProgress()` ile birleşmeyi zaten çektiği için gövde YOK SAYILIR (`EmptyResponse` her
/// JSON gövdesini içerik okumadan başarılı kabul eder). Idempotent değil ama last-write-wins
/// (`watchedAt`) sunucuda çözülür; otomatik-retry YOK (senkron tur yeniden dener).
private struct ProgressUploadEndpoint: Endpoint {
    typealias Response = EmptyResponse

    let entries: [WatchProgressWire]

    var path: String {
        "/playback/progress"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        ProgressUploadRequestBody(entries: entries)
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// `POST /playback/progress` istek gövdesi (05 §4.4: `{ "entries": [...] }`). Testin encode ile
/// zarf anahtarını (`entries`) doğrulayabilmesi için modül-içi (private değil).
struct ProgressUploadRequestBody: Encodable, Sendable {
    let entries: [WatchProgressWire]
}

/// `GET /me/history?cursor=` — cihazlar arası birleşik izleme geçmişi (05 §4.x uç #28). GET olduğundan
/// idempotent → APIClient varsayılan retry politikasını uygular. `cursor` opak ve URL-safe'tir; boş/nil
/// ise ilk sayfa istenir (05 §7.1).
private struct HistoryFetchEndpoint: Endpoint {
    typealias Response = HistoryListWire

    let cursor: String?

    var path: String {
        "/me/history"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        guard let cursor, !cursor.isEmpty else { return [] }
        return [URLQueryItem(name: "cursor", value: cursor)]
    }
}

/// `WatchProgressRecord`'ın taşıma (Codable) karşılığı — 05 §2.11 alan adları. Tarih stratejisi
/// `APIClient`'ın `.shortSeriesDefault()` ISO 8601 kodlayıcısındandır (tek kaynak).
struct WatchProgressWire: Codable, Sendable {
    let episodeId: String
    let seriesId: String
    let positionSec: Double
    let durationSec: Double
    let completed: Bool
    let watchedAt: Date

    init(record: WatchProgressRecord) {
        episodeId = record.episodeID.rawValue
        seriesId = record.seriesID.rawValue
        positionSec = record.positionSec
        durationSec = record.durationSec
        completed = record.completed
        watchedAt = record.watchedAt
    }

    var record: WatchProgressRecord {
        WatchProgressRecord(
            episodeID: EpisodeID(episodeId),
            seriesID: SeriesID(seriesId),
            positionSec: positionSec,
            durationSec: durationSec,
            completed: completed,
            watchedAt: watchedAt
        )
    }
}

/// `GET /me/history?cursor=` yanıt zarfı (05 §7.1 cursor kalıbı: `{ "items": [...], "nextCursor": ... }`).
/// `nextCursor: null` → son sayfa. Testin sözleşme örneğini decode edebilmesi için modül-içi.
struct HistoryListWire: Decodable, Sendable {
    let items: [WatchProgressWire]
    let nextCursor: String?
}
