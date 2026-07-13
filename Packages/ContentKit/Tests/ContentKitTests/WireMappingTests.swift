import AppFoundation
import Foundation
import Testing
@testable import ContentKit

/// Wire → domain mapper testleri (05 kural 7): domain property adları istemci
/// sözleşmesidir; ID'ler AppFoundation SharedTypes tiplerine sarılır.
struct WireMappingTests {
    @Test func seriesWireDomainModeleMaplenir() throws {
        let wire = try Fixtures.decode(SeriesWire.self, from: "series_detail")

        let series = wire.toDomain()

        #expect(series.id == SeriesID("srs_77aa10"))
        #expect(series.title == "Crown of Ashes")
        #expect(series.coverURL.absoluteString == "https://cdn.shortseries.app/c/srs_77aa10.jpg")
        #expect(series.bannerURL == nil)
        #expect(series.genres == [Genre(id: "gnr_drama", name: "Dram", iconURL: nil)])
        #expect(series.tags.isEmpty)
        #expect(series.episodeCount == 60)
        #expect(series.releasedEpisodeCount == 60)
        #expect(series.freeEpisodeCount == 5)
        #expect(series.releaseState == .completed)
        #expect(series.nextEpisodeAt == nil)
        #expect(series.stats == SeriesStats(viewCount: 5_400_000, favoriteCount: 210_000, trendingRank: nil))
        #expect(series.localeInfo == LocaleInfo(audioLanguage: "en", subtitleLanguages: ["en", "tr"]))
        #expect(series.updatedAt == isoDate("2026-07-01T00:00:00Z"))
    }

    @Test func episodeWireDomainModeleMaplenir() throws {
        let page = try Fixtures.decode(PageWire<EpisodeWire>.self, from: "episodes_page")

        let locked = page.items[1].toDomain()

        #expect(locked.id == EpisodeID("ep_a2"))
        #expect(locked.seriesId == SeriesID("srs_77aa10"))
        #expect(locked.index == 6)
        #expect(locked.title == "The Reveal")
        #expect(locked.durationSec == 90)
        #expect(locked.access == EpisodeAccess(kind: .locked, unlockPrice: 60, adUnlockEligible: true))
        #expect(locked.publishedAt == isoDate("2026-05-06T00:00:00Z"))
    }

    @Test func feedSayfasiDomainSayfayaMaplenirVeCursorKorunur() throws {
        let wire = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page")

        let page = wire.toDomain()

        #expect(page.items.count == 2)
        #expect(page.nextCursor == "eyJvZmZzZXQiOiIxMCJ9")
        #expect(page.ttlSec == 300)
        #expect(page.isLastPage == false)

        let second = try #require(page.items.last)
        #expect(second.id == "fi_002")
        #expect(second.type == .episode)
        #expect(second.series.id == SeriesID("srs_9f2c1a"))
        #expect(second.episode?.id == EpisodeID("ep_5410bf"))
        let progress = try #require(second.progress)
        #expect(progress.episodeId == EpisodeID("ep_5410bf"))
        #expect(progress.seriesId == SeriesID("srs_9f2c1a"))
        #expect(progress.positionSec == 12.5)
        #expect(progress.durationSec == 88.0)
        #expect(progress.completed == false)
        #expect(second.reason == "Romantik izlediğin için")
    }

    /// `.unknown` tipli item render edilmez, ATLANIR (05 §2.12) — mapper sınırında düşer
    /// ve düşüş `droppedItemCount`ta yüzeye çıkar (sessiz kayıp yok).
    @Test func bilinmeyenTipliFeedItemMaplemedeAtlanir() throws {
        let wire = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page_future")

        let page = wire.toDomain()

        #expect(page.items.count == 1)
        #expect(page.items.first?.id == "fi_901")
        #expect(page.droppedItemCount == 1)
        // Bilinmeyen access.kind güvenli tarafta kilitli sayılır (05 §12 kural 4)
        #expect(page.items.first?.episode?.access.isPlayableWithoutUnlock == false)
    }

    /// Mapper düşürdüklerini sayar: bilinmeyen tip + series'siz item → 2 düşer,
    /// geçerli item'lar eksiksiz kalır ve `droppedItemCount` doğrudur.
    @Test func mapperDusenItemlariSayarGecerlilerEksiksizKalir() throws {
        let json = Data("""
        {
          "items": [
            {
              "id": "fi_promo",
              "type": "seriesPromo",
              "series": \(Self.minimalSeriesJSON),
              "episode": null,
              "progress": null,
              "reason": null
            },
            {
              "id": "fi_gelecek",
              "type": "mysteryCard",
              "series": \(Self.minimalSeriesJSON),
              "episode": null,
              "progress": null,
              "reason": null
            },
            {
              "id": "fi_serisiz",
              "type": "episode",
              "series": null,
              "episode": null,
              "progress": null,
              "reason": null
            }
          ],
          "nextCursor": null,
          "ttlSec": 300
        }
        """.utf8)
        let wire = try Fixtures.decoder.decode(PageWire<FeedItemWire>.self, from: json)

        let page = wire.toDomain()

        #expect(page.items.map(\.id) == ["fi_promo"])
        #expect(page.droppedItemCount == 2)
    }

    /// Hiç düşüş olmayan sayfada sayaç 0'dır.
    @Test func dususOlmayanSayfadaSayacSifirdir() throws {
        let page = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page").toDomain()

        #expect(page.items.count == 2)
        #expect(page.droppedItemCount == 0)
    }

    /// `.episode` tipi episode yükü olmadan gelirse sözleşme ihlalidir; item güvenle düşürülür.
    /// `series` DOLU tutulur ki sınanan dal gerçekten `type == .episode && episode == nil`
    /// olsun (series'siz düşme ayrı daldır ve `seriesYukuOlmayanItemDusurulur` sınar).
    @Test func episodeYukuOlmayanEpisodeItemDusurulur() throws {
        let json = Data("""
        {
          "id": "fi_bad",
          "type": "episode",
          "series": \(Self.minimalSeriesJSON),
          "episode": null,
          "progress": null,
          "reason": null
        }
        """.utf8)

        let wire = try Fixtures.decoder.decode(FeedItemWire.self, from: json)

        #expect(wire.series != nil) // dal önkoşulu: series bağlamı mevcut
        #expect(wire.toDomain() == nil)
    }

    /// `series` bağlamı olmayan item sözleşme sapmasıdır (05 §2.12'de zorunlu);
    /// lenient decode bilinçlidir — item mapping'de düşer, sayfanın kalanı akar.
    @Test func seriesYukuOlmayanItemDusurulur() throws {
        let json = Data("""
        {
          "id": "fi_bad2",
          "type": "episode",
          "series": null,
          "episode": null,
          "progress": null,
          "reason": null
        }
        """.utf8)

        let wire = try Fixtures.decoder.decode(FeedItemWire.self, from: json)

        #expect(wire.toDomain() == nil)
    }

    /// `seriesPromo` episode yükü taşımadan domain'e maplenir ve DÜŞMEZ (05 §2.12).
    @Test func seriesPromoItemDomaineMaplenirVeDusmez() throws {
        let wire = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page_promo")

        let page = wire.toDomain()

        #expect(page.items.count == 2)
        #expect(page.droppedItemCount == 0)
        let promo = try #require(page.items.first)
        #expect(promo.id == "fi_promo01")
        #expect(promo.type == .seriesPromo)
        #expect(promo.episode == nil)
        #expect(promo.series.id == SeriesID("srs_77aa10"))
    }

    /// Test JSON'ları için geçerli asgari SeriesWire bloğu (fixture'larla aynı şema).
    private static let minimalSeriesJSON = """
    {
      "id": "srs_test01",
      "title": "Test Series",
      "synopsis": "Test",
      "coverURL": "https://cdn.shortseries.app/c/srs_test01.jpg",
      "bannerURL": null,
      "genres": [],
      "tags": [],
      "episodeCount": 1,
      "releasedEpisodeCount": 1,
      "freeEpisodeCount": 1,
      "releaseState": "ongoing",
      "nextEpisodeAt": null,
      "stats": { "viewCount": 1, "favoriteCount": 1, "trendingRank": null },
      "localeInfo": { "audioLanguage": "en", "subtitleLanguages": ["en"] },
      "updatedAt": "2026-07-10T09:30:00Z"
    }
    """

    @Test func playbackWireDomainModeleMaplenir() throws {
        let clear = try Fixtures.decode(PlaybackAuthorizationWire.self, from: "playback_authorize")
        let fairplay = try Fixtures.decode(PlaybackAuthorizationWire.self, from: "playback_authorize_fairplay")

        let clearAuth = clear.toDomain()
        let fairplayAuth = fairplay.toDomain()

        #expect(clearAuth.episodeId == EpisodeID("ep_5410be"))
        #expect(clearAuth.drm == nil)
        #expect(clearAuth.expiresAt == isoDate("2026-07-11T12:00:00Z"))

        let drm = try #require(fairplayAuth.drm)
        #expect(drm.scheme == .fairplay)
        #expect(drm.licenseToken == "lt_abc...")
    }

    @Test func discoverWireDomainModeleMaplenir() throws {
        let wire = try Fixtures.decode(DiscoverWire.self, from: "discover")

        let discover = wire.toDomain()

        #expect(discover.banners.count == 1)
        #expect(discover.banners.first?.id == "bnr_summer01")
        #expect(discover.collections.count == 2)
        #expect(discover.collections[0].kind == .trending)
        #expect(discover.collections[0].seriesList.first?.id == SeriesID("srs_9f2c1a"))
        #expect(discover.collections[1].kind == .top10)
        #expect(discover.collections[1].nextCursor == nil)
    }
}
