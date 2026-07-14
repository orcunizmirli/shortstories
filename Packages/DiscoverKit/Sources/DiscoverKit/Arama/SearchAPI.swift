import AppFoundation
import ContentKit
import Foundation

/// `SearchServicing`in canlı implementasyonu (05 §4.8). Wire→domain eşleme decode sınırında:
/// `SeriesID` `RawRepresentable` olduğundan sunucunun düz string `id`si domain `Series`e sorunsuz
/// decode olur (bkz. AppFoundation Identifiers). Sonuç zarfı `{results, nextCursor}` → `Page<Series>`.
public struct SearchAPI: SearchServicing {
    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func suggest(query: String) async throws -> [SearchSuggestion] {
        let response = try await client.send(SearchSuggestEndpoint(queryText: query))
        return response.suggestions.map { $0.toDomain() }
    }

    public func search(query: String, cursor: String?) async throws -> Page<Series> {
        let response = try await client.send(SearchEndpoint(queryText: query, cursor: cursor))
        return Page(items: response.results, nextCursor: response.nextCursor, ttlSec: nil)
    }

    public func popular() async throws -> [String] {
        try await client.send(SearchPopularEndpoint()).queries
    }
}

// MARK: - Wire zarfları (05 §4.8)

/// `{ suggestions: [ { text, type, seriesId } ] }`.
struct SearchSuggestResponse: Decodable, Sendable {
    let suggestions: [SuggestionWire]
}

struct SuggestionWire: Decodable, Sendable {
    let text: String
    let type: String
    let seriesId: String?

    /// `type == "series"` + dolu `seriesId` = dizi önerisi; aksi halde (bilinmeyen tip dahil)
    /// sorgu önerisi olarak ele alınır (ileri uyumluluk).
    func toDomain() -> SearchSuggestion {
        if type == "series", let seriesId {
            return SearchSuggestion(text: text, kind: .series, seriesID: SeriesID(seriesId))
        }
        return SearchSuggestion(text: text, kind: .query, seriesID: nil)
    }
}

/// `{ results: [Series], nextCursor: "..." }`.
struct SearchResultsResponse: Decodable, Sendable {
    let results: [Series]
    let nextCursor: String?
}

/// `{ queries: ["ceo romance", ...] }`.
struct SearchPopularResponse: Decodable, Sendable {
    let queries: [String]
}

// MARK: - Endpoint tanımları (03 §8.1: Endpoint tanımları feature'da yaşar)

/// `GET /search/suggest?q=`. Tek deneme değil — GET idempotent, varsayılan retry; otomatik
/// tamamlama isteği debounce'la seyrekleştirilir (çağıran sorumluluğu).
struct SearchSuggestEndpoint: Endpoint {
    typealias Response = SearchSuggestResponse

    let queryText: String

    var path: String {
        "/search/suggest"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        [URLQueryItem(name: "q", value: queryText)]
    }
}

/// `GET /search?q=&cursor=` — sonuç ızgarası (cursor sayfalama).
struct SearchEndpoint: Endpoint {
    typealias Response = SearchResultsResponse

    let queryText: String
    let cursor: String?

    var path: String {
        "/search"
    }

    var method: HTTPMethod {
        .get
    }

    var query: [URLQueryItem] {
        var items = [URLQueryItem(name: "q", value: queryText)]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        return items
    }
}

/// `GET /search/popular` — Arama boş durumu.
struct SearchPopularEndpoint: Endpoint {
    typealias Response = SearchPopularResponse

    var path: String {
        "/search/popular"
    }

    var method: HTTPMethod {
        .get
    }
}
