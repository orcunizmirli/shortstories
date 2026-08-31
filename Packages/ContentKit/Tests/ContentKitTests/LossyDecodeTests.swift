import Foundation
import Testing
@testable import ContentKit

/// Audit MEDIUM/LOW (decode-robustness): present-but-invalid TEK bir eleman TÜM diziyi (ve dolayısıyla
/// tüm /discover veya feed sayfası zarfını) düşürmemeli — Keşfet/Feed komple boşalmamalı. `LossyArray`
/// eleman-bazlı decode eder; bozuk eleman atlanır, kalanı akar.
struct LossyDecodeTests {
    @Test func bozukElemanAtlanirDigerleriKorunur() throws {
        // {"num":"oops"} bozuk (Int değil) → atlanır; geçerli 1 ve 3 korunur (tüm dizi düşmez).
        let json = #"{"xs":[{"num":1},{"num":"oops"},{"num":3}]}"#
        let box = try JSONDecoder().decode(LossyBox.self, from: Data(json.utf8))
        #expect(box.xs == [LossyItem(num: 1), LossyItem(num: 3)])
    }

    @Test func alanYokVeyaNullBosDoner() throws {
        #expect(try JSONDecoder().decode(LossyBox.self, from: Data(#"{}"#.utf8)).xs.isEmpty)
        #expect(try JSONDecoder().decode(LossyBox.self, from: Data(#"{"xs":null}"#.utf8)).xs.isEmpty)
    }

    @Test func discoverBozukBannerTumEkraniDusurmez() throws {
        // b2'nin startsAt'i geçersiz → BannerWire decode throw eder; lossy onu atlar, b1 görünür.
        // Fix'ten önce decodeIfPresent([BannerWire]) TÜM diziyi (ve /discover'ı) düşürürdü → Keşfet boş.
        let validBanner = """
        {"id":"b1","imageURL":"https://cdn.test/b1.jpg","deeplink":"shortseries://x",\
        "startsAt":"2026-07-01T00:00:00Z","endsAt":"2026-08-01T00:00:00Z"}
        """
        let invalidBanner = """
        {"id":"b2","imageURL":"https://cdn.test/b2.jpg","deeplink":"shortseries://y",\
        "startsAt":"GECERSIZ_TARIH","endsAt":"2026-08-01T00:00:00Z"}
        """
        let json = "{\"banners\":[\(validBanner),\(invalidBanner)],\"collections\":[]}"
        let wire = try Fixtures.decoder.decode(DiscoverWire.self, from: Data(json.utf8))
        #expect(wire.banners.count == 1)
        #expect(wire.banners.first?.id == "b1")
    }

    @Test func seriesBozukGenreTumSeriyiDusurmez() throws {
        // Audit MEDIUM (decode-robustness / 05 §12/4): SeriesWire genres/tags STRICT decode ediliyordu →
        // tek bozuk alt-eleman (zorunlu alanı eksik genre/tag) TÜM seriyi düşürüyordu. Liste yolunda
        // (lossy) geçerli seri komple kaybolur; detay yolunda (/series/{id}, lossy DEĞİL) tam-ekran hata.
        // Fix: genres/tags LOSSY (bozuk alt-eleman atlanır); çekirdek alanlar (title/cover/erişim) strict.
        let json = """
        {
          "id": "srs_x", "title": "Geçerli Seri", "synopsis": "s",
          "coverURL": "https://cdn.test/c.jpg", "bannerURL": null,
          "genres": [{"id":"g1","name":"Aşk","iconURL":null},{"id":"g2"}],
          "tags": [{"id":"t1","name":"İntikam"},{"name":"eksik_id"}],
          "episodeCount": 10, "releasedEpisodeCount": 5, "freeEpisodeCount": 3,
          "releaseState": "ongoing", "nextEpisodeAt": null,
          "stats": {"viewCount":1,"favoriteCount":1,"trendingRank":null},
          "localeInfo": {"audioLanguage":"en","subtitleLanguages":["en"]},
          "updatedAt": "2026-07-10T09:30:00Z"
        }
        """
        let wire = try Fixtures.decoder.decode(SeriesWire.self, from: Data(json.utf8))
        #expect(wire.id == "srs_x") // seri düşmedi — çekirdek alanlar korundu
        #expect(wire.title == "Geçerli Seri")
        #expect(wire.genres.count == 1) // bozuk g2 (name eksik) atlandı, g1 korundu
        #expect(wire.genres.first?.id == "g1")
        #expect(wire.tags.count == 1) // bozuk (id eksik) atlandı, t1 korundu
        #expect(wire.tags.first?.id == "t1")
    }

    @Test func seriesEksikGenresTagsAlaniBosOlur() throws {
        // genres/tags alanı backend'de HİÇ yoksa (omit) STRICT decode throw ederdi → tüm seri düşerdi;
        // lossy karşılığı eksik/null alanı [] yapar.
        let json = """
        {
          "id": "srs_y", "title": "T", "synopsis": "s",
          "coverURL": "https://cdn.test/c.jpg", "bannerURL": null,
          "episodeCount": 1, "releasedEpisodeCount": 1, "freeEpisodeCount": 1,
          "releaseState": "ongoing", "nextEpisodeAt": null,
          "stats": {"viewCount":1,"favoriteCount":1,"trendingRank":null},
          "localeInfo": {"audioLanguage":"en","subtitleLanguages":["en"]},
          "updatedAt": "2026-07-10T09:30:00Z"
        }
        """
        let wire = try Fixtures.decoder.decode(SeriesWire.self, from: Data(json.utf8))
        #expect(wire.genres.isEmpty)
        #expect(wire.tags.isEmpty)
    }

    @Test func yanlisTipCollectionsAlaniDiscoveriDusurmez() throws {
        // audit LOW (#5): "collections" ARRAY yerine OBJE gelirse (sunucu/proxy bug) eski kod unkeyedContainer'da
        // throw edip TÜM /discover'ı düşürürdü → Keşfet boş ekran. Fix: yanlış-tip alan yutulur, collections [].
        let json = #"{"banners":[],"collections":{}}"#
        let wire = try Fixtures.decoder.decode(DiscoverWire.self, from: Data(json.utf8))
        #expect(wire.collections.isEmpty)
        #expect(wire.banners.isEmpty)
    }

    @Test func bozukNonCoreTarihSeriyiDusurmez() throws {
        // audit (#2): non-core tarih (nextEpisodeAt UI etiketi, updatedAt cache metadata) BOZUK gelirse eski
        // STRICT decode TÜM (çekirdeği geçerli) seriyi düşürürdü (detayda tam-ekran hata). Fix: bozuk → nil /
        // distantPast; seri düşmez.
        let json = """
        {
          "id": "srs_d", "title": "Geçerli", "synopsis": "s",
          "coverURL": "https://cdn.test/c.jpg", "bannerURL": null,
          "genres": [], "tags": [],
          "episodeCount": 3, "releasedEpisodeCount": 2, "freeEpisodeCount": 1,
          "releaseState": "ongoing", "nextEpisodeAt": "yakinda",
          "stats": {"viewCount":1,"favoriteCount":1,"trendingRank":null},
          "localeInfo": {"audioLanguage":"en","subtitleLanguages":["en"]},
          "updatedAt": "soon"
        }
        """
        let wire = try Fixtures.decoder.decode(SeriesWire.self, from: Data(json.utf8))
        #expect(wire.id == "srs_d") // çekirdek geçerli → seri düşmedi
        #expect(wire.nextEpisodeAt == nil) // bozuk tarih → nil
        #expect(wire.updatedAt == .distantPast) // bozuk cache-timestamp → sentinel (çok bayat)
    }

    @Test func decodeAsamasiDusenItemDroppedCountaGirer() throws {
        // audit (#1/#4/#6): LossyArray decode-aşamasında bozuk item'ı sessizce düşürüyordu ve droppedItemCount
        // 0 raporluyordu → "sessiz kayıp yok" invariantı decode-aşamasında ihlaldi. Fix: decode-düşüşü sayaca girer.
        let valid = """
        {"id":"e1","seriesId":"srs","index":1,"durationSec":60,"thumbnailURL":"https://cdn.test/e1.jpg",\
        "access":{"kind":"free","unlockPrice":null,"adUnlockEligible":false}}
        """
        // durationSec (zorunlu) EKSİK → EpisodeWire decode throw → LossyArray atlar.
        let broken = """
        {"id":"e2","seriesId":"srs","index":2,"thumbnailURL":"https://cdn.test/e2.jpg",\
        "access":{"kind":"free","unlockPrice":null,"adUnlockEligible":false}}
        """
        let json = "{\"items\":[\(valid),\(broken)],\"nextCursor\":null,\"ttlSec\":300}"
        let page = try Fixtures.decoder.decode(PageWire<EpisodeWire>.self, from: Data(json.utf8)).toDomain()
        #expect(page.items.count == 1) // e2 düştü
        #expect(page.droppedItemCount == 1) // decode-aşaması düşüşü sayaca girdi (eskiden 0)
    }
}

private struct LossyItem: Decodable, Equatable {
    let num: Int
}

private struct LossyBox: Decodable {
    let xs: [LossyItem]

    init(from decoder: Decoder) throws {
        xs = try decoder.container(keyedBy: CodingKeys.self).decodeLossyArray(LossyItem.self, forKey: .xs)
    }

    enum CodingKeys: String, CodingKey {
        case xs
    }
}
