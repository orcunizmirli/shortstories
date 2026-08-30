import AppFoundation
import AppFoundationTestSupport
import DiscoverKit
import XCTest
@testable import ShortSeriesApp

/// Keşfet nav idempotency/deep-link (audit LOW, DiscoverCoordinator): NavigationPath introspect
/// edilemediğinden showDetail/showSearch tekrar-önleme marker/derinlik ile yapılır. (a) aynı diziye
/// ikinci push özdeş DiziDetay ÇOĞALTMAMALI; (b) Arama zaten açıkken gelen universal-link `search?q=`
/// query'si DÜŞMEMELİ (pop+repush ile ön-doldurma). Bu hedef CI'da KOŞMAZ (App target CI dışı).
@MainActor
final class DiscoverNavigationTests: XCTestCase {
    private func makeDiscover() throws -> DiscoverCoordinator {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        return TabCoordinator(composition: composition).discover
    }

    /// (a) Aynı dizi HÂLÂ tepedeyken ikinci push özdeş DiziDetay çoğaltmaz (deep-link/çift-tap idempotent).
    func testShowDetailIsIdempotentForSameSeriesAtTop() throws {
        let discover = try makeDiscover()
        discover.showDetail(SeriesID("s1"), source: .kesfet)
        discover.showDetail(SeriesID("s1"), source: .kesfet)
        XCTAssertEqual(discover.path.count, 1) // tek DiziDetay (çoğaltma yok)
    }

    /// Farklı diziler her zaman yığılır (genel push kırılmaz).
    func testShowDetailStacksDistinctSeries() throws {
        let discover = try makeDiscover()
        discover.showDetail(SeriesID("s1"), source: .kesfet)
        discover.showDetail(SeriesID("s2"), source: .kesfet)
        XCTAssertEqual(discover.path.count, 2)
    }

    /// (b) Arama açıkken (üstünde DiziDetay varken) gelen query → pop+repush (Arama ön-doldurulmuş açılır).
    func testShowSearchWithQueryWhenAramaOpenRepushes() throws {
        let discover = try makeDiscover()
        discover.showSearch(query: nil) // Arama açılır (count 1)
        discover.showDetail(SeriesID("s1"), source: .arama) // count 2
        XCTAssertEqual(discover.path.count, 2)

        discover.showSearch(query: "kral") // Arama açık + query → pop(DiziDetay+Arama)+repush → count 1
        XCTAssertEqual(discover.path.count, 1) // FIX'siz: guard return → count 2 kalırdı
    }

    /// Arama açıkken query YOKSA no-op (çift-Arama önleme korunur).
    func testShowSearchWithoutQueryWhenAramaOpenIsNoOp() throws {
        let discover = try makeDiscover()
        discover.showSearch(query: nil)
        discover.showSearch(query: nil) // Arama zaten açık, query yok → no-op
        XCTAssertEqual(discover.path.count, 1)
    }
}
