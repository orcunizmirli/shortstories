import AppFoundation
import Foundation

/// Paylaşım/derin link URL üretimi (SS-083/SS-142). AASA path kalıbı `/s/{seriesId}` ve
/// `/s/{seriesId}/e/{n}` (02 §8.1.1/§8.2) ile birebir; gelen link `DiscoverKit.DeepLinkRoute`
/// tarafından aynı kalıpla çözülür (round-trip). Custom scheme eşleniği `shortseries://`.
enum DeepLinkFactory {
    /// Universal link host'u (AASA yayını SS-176). F1 sabit; xcconfig'e taşınması Faz 2.
    static let webHost = "https://shortseries.app"

    /// Dizi paylaşım linki (`/s/{seriesId}`).
    static func seriesURL(_ seriesID: SeriesID) -> URL {
        URL(string: "\(webHost)/s/\(seriesID.rawValue)") ?? fallback
    }

    /// Bölüm paylaşım linki (`/s/{seriesId}/e/{n}`).
    static func episodeURL(_ seriesID: SeriesID, episodeNumber: Int) -> URL {
        URL(string: "\(webHost)/s/\(seriesID.rawValue)/e/\(episodeNumber)") ?? fallback
    }

    private static let fallback = URL(string: webHost)!
}
