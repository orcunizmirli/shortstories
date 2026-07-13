import AppFoundation
import Foundation

// ContentKit Endpoint tanımları (03 §8.1: Endpoint tanımları feature'da yaşar; taşıma
// katmanı AppFoundation'dadır). Path'ler versiyon öneki İÇERMEZ — /v1 baseURL'dedir.
// Retry beyanları 03 §8.3 tablosuna, cache beyanları 05 §7.2 tablosuna göredir; cache
// policy uygulaması AppFoundation cache katmanı (SS-020) gelene kadar sözleşme olarak taşınır.

extension String {
    /// Path segmenti yüzde-kaçlama (tek nokta): sunucu ID'leri path'e HAM interpolasyonla
    /// girmez. İzinli küme `urlPathAllowed` EKSİ "/" — böylece "a/b" gibi bir ID
    /// "a%2Fb" olur ve path hiyerarşisini bozamaz; boşluk vb. de kaçlanır.
    ///
    /// Boş ID'de davranış: precondition YOK — istek yine kurulur ("/series/" gibi),
    /// sunucu doğal 404 döner; istemci çökmez.
    var pathSegmentEscaped: String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}

/// `GET /feed?cursor=&limit=` (05 §4.3). Tek deneme: başarısızlık akışı kesmez (03 §8.3).
/// HTTP cache yok — tazelik yanıt gövdesindeki `ttlSec` ile yönetilir (05 §7.2).
struct FeedEndpoint: Endpoint {
    typealias Response = PageWire<FeedItemWire>

    let cursor: String?
    let limit: Int?

    var path: String {
        "/feed"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        if let limit {
            items.append(URLQueryItem(name: "limit", value: String(limit)))
        }
        return items
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// `GET /series/{id}` (05 §4.1 #7 — DiziDetay). ETag/If-None-Match + SwiftData snapshot
/// davranışı cache katmanında (05 §7.2); burada sözleşme beyanı.
struct SeriesDetailEndpoint: Endpoint {
    typealias Response = SeriesWire

    let seriesId: SeriesID

    var path: String {
        "/series/\(seriesId.rawValue.pathSegmentEscaped)"
    }

    var method: HTTPMethod {
        .get
    }

    var cachePolicy: APICachePolicy {
        .cacheFirst(ttl: .seconds(300))
    }
}

/// `GET /series/{id}/episodes?cursor=` (05 §4.1 #8 — BolumListesi, DiziDetay ızgara).
struct EpisodeListEndpoint: Endpoint {
    typealias Response = PageWire<EpisodeWire>

    let seriesId: SeriesID
    let cursor: String?

    var path: String {
        "/series/\(seriesId.rawValue.pathSegmentEscaped)/episodes"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
    }

    var cachePolicy: APICachePolicy {
        .cacheFirst(ttl: .seconds(300))
    }
}

/// `GET /discover` (05 §4.1 #9 — Kesfet rafları): stale-while-revalidate (05 §7.2).
struct DiscoverEndpoint: Endpoint {
    typealias Response = DiscoverWire

    var path: String {
        "/discover"
    }

    var method: HTTPMethod {
        .get
    }

    var cachePolicy: APICachePolicy {
        .staleWhileRevalidate
    }
}

/// `GET /collections/{id}?cursor=` (05 §4.1 #10 — raf "tümünü gör").
struct CollectionPageEndpoint: Endpoint {
    typealias Response = PageWire<SeriesWire>

    let collectionId: String
    let cursor: String?

    var path: String {
        "/collections/\(collectionId.pathSegmentEscaped)"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
    }

    var cachePolicy: APICachePolicy {
        .staleWhileRevalidate
    }
}

/// `POST /playback/authorize` (05 §4.4). Otomatik retry YOK (03 §8.3); süre dolumu
/// kurtarması player tarafındadır (05 §8.1). Yanıt `no-store` (05 §7.2).
struct PlaybackAuthorizeEndpoint: Endpoint {
    typealias Response = PlaybackAuthorizationWire

    struct RequestBody: Encodable, Sendable {
        let episodeId: String
    }

    let episodeId: EpisodeID

    var path: String {
        "/playback/authorize"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        RequestBody(episodeId: episodeId.rawValue)
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}
