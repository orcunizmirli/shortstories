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

    // MARK: - self-review3 regresyonları (sistem-geri sonrası bayat-marker; [AppRoute] gerçek-peek ile çözüldü)

    /// self-review3 MEDIUM: showDetail(s1) → sistem-geri → Arama aç → aramadan s1 seç → DEAD-TAP olmamalı
    /// (eski depth-marker: Arama depth-1'de s1 marker'ını spoof'layıp bastırıyordu). [AppRoute] peek push eder.
    func testShowDetailAfterSystemBackIsNotFalselySuppressed() throws {
        let discover = try makeDiscover()
        discover.showDetail(SeriesID("s1"), source: .kesfet)
        discover.path.removeLast() // sistem-geri (path'i doğrudan mutate eder — coordinator kodu koşmaz)
        discover.showSearch(query: nil) // [Arama]
        discover.showDetail(SeriesID("s1"), source: .arama) // tepe .arama → bastırılmaz → push
        XCTAssertEqual(discover.path.count, 2) // Arama + s1 DiziDetay (dead-tap YOK)
    }

    /// self-review3 MEDIUM: showDetail(s1),showDetail(s2) → sistem-geri (s2 pop) → showDetail(s1) ÇOĞALTMAMALI
    /// (eski marker=(s2,2) → bastırmaz → [s1,s1]). [AppRoute] peek: tepe s1 → bastırır.
    func testShowDetailAfterSystemBackDoesNotDuplicate() throws {
        let discover = try makeDiscover()
        discover.showDetail(SeriesID("s1"), source: .kesfet)
        discover.showDetail(SeriesID("s2"), source: .kesfet)
        discover.path.removeLast() // sistem-geri: s2 pop → tepe s1
        discover.showDetail(SeriesID("s1"), source: .kesfet) // tepe s1 → bastırılır (çoğaltma yok)
        XCTAssertEqual(discover.path.count, 1)
    }

    /// self-review3 LOW: Arama açıkken sistem-geri → DiziDetay aç → search?q= gelince kullanıcının DiziDetay'ını
    /// YIKMAMALI (eski removeLast bayat depth'le yanlış frame'i poplardı). [AppRoute]: Arama stack'te yok → append.
    func testShowSearchQueryForwardAfterSystemBackDoesNotDestroyDetail() throws {
        let discover = try makeDiscover()
        discover.showSearch(query: nil) // [Arama]
        discover.path.removeLast() // sistem-geri: Arama pop → []
        discover.showDetail(SeriesID("s1"), source: .kesfet) // [s1 DiziDetay]
        discover.showSearch(query: "kral") // Arama stack'te yok → append (s1 KORUNUR)
        XCTAssertEqual(discover.path.count, 2)
        guard case .diziDetay = discover.path.first else {
            return XCTFail("s1 DiziDetay korunmalıydı (yıkıcı pop YOK)")
        }
    }
}
