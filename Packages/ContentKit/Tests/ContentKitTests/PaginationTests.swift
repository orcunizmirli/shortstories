import Foundation
import Testing
@testable import ContentKit

/// Cursor sayfalama zarfı kuralları (05 §7.1).
struct PaginationTests {
    @Test func nextCursorNullSonSayfadir() {
        let page = Page<Int>(items: [1, 2], nextCursor: nil, ttlSec: nil)

        #expect(page.isLastPage)
    }

    @Test func nextCursorDoluysaSonSayfaDegildir() {
        let page = Page<Int>(items: [1], nextCursor: "eyJ2IjoxfQ", ttlSec: 300)

        #expect(!page.isLastPage)
    }

    /// Boş items + null cursor geçerli bir "boş liste" yanıtıdır (05 §7.1).
    @Test func bosListeNullCursorGecerlidir() throws {
        let json = Data(#"{ "items": [], "nextCursor": null }"#.utf8)

        let wire = try Fixtures.decoder.decode(PageWire<SeriesWire>.self, from: json)

        #expect(wire.items.isEmpty)
        #expect(wire.nextCursor == nil)
        #expect(wire.ttlSec == nil)
    }

    /// Savunmacı sınır (audit LOW): sunucu son sayfada opak-cursor sözleşmesini ihlal edip
    /// `"nextCursor":""` (boş string) dönerse decodeIfPresent bunu "" (NON-nil) korurdu → isLastPage
    /// false → çağıran `cursor=""` ile aynı sayfayı tekrar ister (sonsuz/yinelenen sayfalama). Boş
    /// string nil'e normalize edilir → son sayfa.
    @Test func bosStringNextCursorNilOlarakNormalizeEdilir() throws {
        let json = Data(#"{ "items": [], "nextCursor": "" }"#.utf8)

        let wire = try Fixtures.decoder.decode(PageWire<SeriesWire>.self, from: json)

        #expect(wire.nextCursor == nil) // "" → nil (son sayfa; sonsuz döngü yok)
    }

    /// Boşluk-yalnızca cursor da (`"   "`) opak-cursor değildir → nil'e normalize.
    @Test func whitespaceNextCursorNilOlarakNormalizeEdilir() throws {
        let json = Data(#"{ "items": [], "nextCursor": "   " }"#.utf8)

        let wire = try Fixtures.decoder.decode(PageWire<SeriesWire>.self, from: json)

        #expect(wire.nextCursor == nil)
    }
}
