import Foundation
import Testing
@testable import ContentKit

/// Audit MEDIUM/LOW (decode-robustness): present-but-invalid TEK bir eleman TÜM diziyi (ve dolayısıyla
/// tüm /discover veya feed sayfası zarfını) düşürmemeli — Keşfet/Feed komple boşalmamalı. `LossyArray`
/// eleman-bazlı decode eder; bozuk eleman atlanır, kalanı akar.
struct LossyDecodeTests {
    private struct Item: Decodable, Equatable {
        let n: Int
    }

    private struct Box: Decodable {
        let xs: [Item]
        init(from decoder: Decoder) throws {
            xs = try decoder.container(keyedBy: CodingKeys.self).decodeLossyArray(Item.self, forKey: .xs)
        }

        enum CodingKeys: String, CodingKey { case xs }
    }

    @Test func bozukElemanAtlanirDigerleriKorunur() throws {
        // {"n":"oops"} bozuk (Int değil) → atlanır; geçerli 1 ve 3 korunur (tüm dizi düşmez).
        let json = #"{"xs":[{"n":1},{"n":"oops"},{"n":3}]}"#
        let box = try JSONDecoder().decode(Box.self, from: Data(json.utf8))
        #expect(box.xs == [Item(n: 1), Item(n: 3)])
    }

    @Test func alanYokVeyaNullBosDoner() throws {
        #expect(try JSONDecoder().decode(Box.self, from: Data(#"{}"#.utf8)).xs.isEmpty)
        #expect(try JSONDecoder().decode(Box.self, from: Data(#"{"xs":null}"#.utf8)).xs.isEmpty)
    }

    @Test func discoverBozukBannerTumEkraniDusurmez() throws {
        // b2'nin startsAt'i geçersiz → BannerWire decode throw eder; lossy onu atlar, b1 görünür.
        // Fix'ten önce decodeIfPresent([BannerWire]) TÜM diziyi (ve /discover'ı) düşürürdü → Keşfet boş.
        let json = """
        {"banners":[
          {"id":"b1","imageURL":"https://cdn.test/b1.jpg","deeplink":"shortseries://x","startsAt":"2026-07-01T00:00:00Z","endsAt":"2026-08-01T00:00:00Z"},
          {"id":"b2","imageURL":"https://cdn.test/b2.jpg","deeplink":"shortseries://y","startsAt":"GECERSIZ_TARIH","endsAt":"2026-08-01T00:00:00Z"}
        ],"collections":[]}
        """
        let wire = try Fixtures.decoder.decode(DiscoverWire.self, from: Data(json.utf8))
        #expect(wire.banners.count == 1)
        #expect(wire.banners.first?.id == "b1")
    }
}
