import AppFoundation
import DiscoverKit
import XCTest
@testable import ShortSeriesApp

/// Paylaşım/derin link üretiminin (SS-083/SS-142) çözümleyiciyle round-trip doğrulaması: App'in
/// ürettiği universal link, `DiscoverKit.DeepLinkResolver`'ın beklediği AASA path kalıbıyla (02
/// §8.2 `/s/{id}`, `/s/{id}/e/{n}`) birebir eşleşmeli — aksi halde paylaşılan link açılmaz.
final class DeepLinkFactoryTests: XCTestCase {
    private let seriesID = SeriesID("srs_abc123")

    func testSeriesShareLinkRoundTrips() {
        let url = DeepLinkFactory.seriesURL(seriesID)
        XCTAssertEqual(url.absoluteString, "https://shortseries.app/s/srs_abc123")
        XCTAssertEqual(DeepLinkRoute(url: url), .series(id: seriesID))
    }

    func testEpisodeShareLinkRoundTrips() {
        let url = DeepLinkFactory.episodeURL(seriesID, episodeNumber: 7)
        XCTAssertEqual(url.absoluteString, "https://shortseries.app/s/srs_abc123/e/7")
        XCTAssertEqual(DeepLinkRoute(url: url), .episode(seriesId: seriesID, number: 7))
    }
}
