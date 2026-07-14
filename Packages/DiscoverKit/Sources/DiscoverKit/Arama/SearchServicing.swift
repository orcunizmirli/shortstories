import AppFoundation
import ContentKit

/// Otomatik tamamlama önerisi (05 §4.8 `GET /search/suggest`). İki tip: dizi eşleşmesi
/// (mini poster + ad → doğrudan `DiziDetay`) ve sorgu önerisi (dokununca sonuç moduna geçer).
public struct SearchSuggestion: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case series
        case query
    }

    public let text: String
    public let kind: Kind
    /// Yalnız `.series` için dolu; sorgu önerisinde nil.
    public let seriesID: SeriesID?

    public init(text: String, kind: Kind, seriesID: SeriesID?) {
        self.text = text
        self.kind = kind
        self.seriesID = seriesID
    }

    public var id: String {
        "\(kind.rawValue):\(text):\(seriesID?.rawValue ?? "")"
    }
}

/// Arama servisi (05 §4.8): otomatik tamamlama + sonuç ızgarası + popüler aramalar.
/// ContentKit'te karşılığı olmadığından (CatalogServicing arama içermez) DiscoverKit'te
/// tanımlanır; canlı implementasyon `SearchAPI` AppFoundation `APIClientProtocol`ünü kullanır.
public protocol SearchServicing: Sendable {
    /// `GET /search/suggest?q=` — min 2 karakter (çağıran garanti eder), debounce çağıranda.
    func suggest(query: String) async throws -> [SearchSuggestion]

    /// `GET /search?q=&cursor=` — sonuç ızgarası (cursor sayfalama, 05 §7.1).
    func search(query: String, cursor: String?) async throws -> Page<Series>

    /// `GET /search/popular` — Arama boş durumu popüler aramaları.
    func popular() async throws -> [String]
}
