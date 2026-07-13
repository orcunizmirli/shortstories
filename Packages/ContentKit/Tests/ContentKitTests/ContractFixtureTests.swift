import Foundation
import Testing
@testable import ContentKit

/// Contract testleri (05 §12 kural 6): fixture'lar WIRE alan adlarını kullanır ve
/// decode sınırını (Wire DTO'lar) sınar. Davranış testleri domain adlarıyladır
/// (FeedAPITests vd.) — bir wire adı değişikliği yalnız buradaki fixture + mapper'ı oynatır.
struct ContractFixtureTests {
    @Test func feedSayfasiWireAlanlariylaDecodeOlur() throws {
        let page = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page")

        #expect(page.items.count == 2)
        #expect(page.nextCursor == "eyJvZmZzZXQiOiIxMCJ9")
        #expect(page.ttlSec == 300)

        let first = try #require(page.items.first)
        #expect(first.id == "fi_001")
        #expect(first.type == .episode)
        #expect(first.series?.id == "srs_9f2c1a")
        #expect(first.series?.title == "Midnight Heir")
        #expect(first.series?.freeEpisodeCount == 8)
        #expect(first.series?.releaseState == .ongoing)
        #expect(first.episode?.id == "ep_5410be")
        #expect(first.episode?.seriesId == "srs_9f2c1a")
        #expect(first.episode?.index == 1)
        #expect(first.episode?.title == nil) // title yok → null; "Bölüm 1" istemcide üretilir
        #expect(first.episode?.durationSec == 92)
        #expect(first.episode?.access.kind == .free)
        #expect(first.episode?.access.unlockPrice == nil)
        #expect(first.episode?.access.adUnlockEligible == false)
        #expect(first.progress == nil)
        #expect(first.reason == nil)

        let second = try #require(page.items.last)
        #expect(second.episode?.title == "The Reveal")
        #expect(second.episode?.access.kind == .locked)
        #expect(second.episode?.access.unlockPrice == 60)
        #expect(second.episode?.access.adUnlockEligible == true)
        #expect(second.progress?.positionSec == 12.5)
        #expect(second.progress?.completed == false)
        #expect(second.reason == "Romantik izlediğin için")
    }

    @Test func diziDetayiWireAlanlariylaDecodeOlur() throws {
        let series = try Fixtures.decode(SeriesWire.self, from: "series_detail")

        #expect(series.id == "srs_77aa10")
        #expect(series.title == "Crown of Ashes")
        #expect(series.bannerURL == nil)
        #expect(series.episodeCount == 60)
        #expect(series.releasedEpisodeCount == 60)
        #expect(series.freeEpisodeCount == 5)
        #expect(series.releaseState == .completed)
        #expect(series.nextEpisodeAt == nil)
        #expect(series.stats.viewCount == 5_400_000)
        #expect(series.stats.trendingRank == nil)
        #expect(series.genres.first?.id == "gnr_drama")
        #expect(series.genres.first?.iconURL == nil)
        #expect(series.tags.isEmpty)
        #expect(series.localeInfo.audioLanguage == "en")
        #expect(series.localeInfo.subtitleLanguages == ["en", "tr"])
        #expect(series.updatedAt == isoDate("2026-07-01T00:00:00Z"))
    }

    @Test func bolumListesiWireAlanlariylaDecodeOlur() throws {
        let page = try Fixtures.decode(PageWire<EpisodeWire>.self, from: "episodes_page")

        #expect(page.items.count == 5)
        #expect(page.nextCursor == nil)
        #expect(page.ttlSec == nil) // zarfın ttlSec alanı opsiyoneldir (05 §7.1)

        #expect(page.items[0].access.kind == .free)
        #expect(page.items[1].access.kind == .locked)
        #expect(page.items[1].access.unlockPrice == 60)
        #expect(page.items[1].access.adUnlockEligible == true)
        // Genişleme noktası (05 §2.2): locked + unlockPrice null = coin yolu kapalı
        #expect(page.items[2].access.kind == .locked)
        #expect(page.items[2].access.unlockPrice == nil)
        #expect(page.items[3].access.kind == .unlocked)
        // publishedAt null = henüz yayınlanmadı
        #expect(page.items[4].publishedAt == nil)
    }

    @Test func playbackAuthorizeClearYanitiDecodeOlur() throws {
        let wire = try Fixtures.decode(PlaybackAuthorizationWire.self, from: "playback_authorize")

        #expect(wire.episodeId == "ep_5410be")
        #expect(wire.playbackURL.absoluteString
            == "https://cdn.shortseries.app/hls/ep_5410be/master.m3u8?tk=eyJ...&exp=1783190400")
        #expect(wire.expiresAt == isoDate("2026-07-11T12:00:00Z"))
        #expect(wire.drm == nil)
    }

    @Test func playbackAuthorizeFairplayYanitiDecodeOlur() throws {
        let wire = try Fixtures.decode(PlaybackAuthorizationWire.self, from: "playback_authorize_fairplay")

        let drm = try #require(wire.drm)
        #expect(drm.scheme == .fairplay)
        #expect(drm.licenseURL.absoluteString == "https://drm.shortseries.app/fps/license")
        #expect(drm.certificateURL.absoluteString == "https://drm.shortseries.app/fps/cert")
        #expect(drm.licenseToken == "lt_abc...")
    }

    @Test func kesfetYanitiWireAlanlariylaDecodeOlur() throws {
        let wire = try Fixtures.decode(DiscoverWire.self, from: "discover")

        #expect(wire.banners.count == 1)
        let banner = try #require(wire.banners.first)
        #expect(banner.id == "bnr_summer01")
        #expect(banner.deeplink.absoluteString == "shortseries://series/srs_9f2c1a")
        #expect(banner.title == "Summer Binge")
        #expect(banner.startsAt == isoDate("2026-07-01T00:00:00Z"))
        #expect(banner.endsAt == isoDate("2026-08-01T00:00:00Z"))

        #expect(wire.collections.count == 2)
        #expect(wire.collections[0].kind == .trending)
        #expect(wire.collections[0].nextCursor == "eyJ2IjoxLCJrIjoiY29sX3RyZW5kaW5nIn0")
        #expect(wire.collections[0].seriesList.first?.id == "srs_9f2c1a")
        #expect(wire.collections[1].kind == .top10)
        #expect(wire.collections[1].nextCursor == nil)
    }

    @Test func koleksiyonSayfasiDecodeOlur() throws {
        let page = try Fixtures.decode(PageWire<SeriesWire>.self, from: "collection_page")

        #expect(page.items.count == 1)
        #expect(page.items.first?.id == "srs_77aa10")
        #expect(page.nextCursor == nil)
        #expect(page.ttlSec == 600)
    }

    /// Kabul kriteri 6 (05 §6): bilinmeyen enum/alan içeren "geleceğe dönük yanıt"
    /// decode hatası üretmez; bilinmeyen enum değerleri `.unknown`a düşer (05 §12 kural 4).
    @Test func gelecegeDonukYanitDecodeHatasiUretmez() throws {
        let page = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page_future")

        #expect(page.items.count == 2)
        #expect(page.items[0].type == .unknown) // "surpriseCard"
        #expect(page.items[0].series?.releaseState == .unknown) // "paused"
        #expect(page.items[1].episode?.access.kind == .unknown) // "vipOnly"
    }

    /// `seriesPromo` sözleşmede tanımlı bir item tipidir (05 §2.12): episode yükü
    /// olmadan, dolu `series` bağlamıyla decode olur.
    @Test func seriesPromoItemWireAlanlariylaDecodeOlur() throws {
        let page = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page_promo")

        let promo = try #require(page.items.first)
        #expect(promo.id == "fi_promo01")
        #expect(promo.type == .seriesPromo)
        #expect(promo.episode == nil)
        #expect(promo.series?.id == "srs_77aa10")
        #expect(promo.reason == "Tamamlanmış diziler arasında öne çıkıyor")
    }

    /// Sunucu RFC 3339 tarihlerini fractional-seconds'lı da gönderebilir
    /// ("…T09:31:02.123Z"); decode sınırı iki biçimi de kabul eder.
    @Test func fractionalSecondsTarihliYanitDecodeOlur() throws {
        let page = try Fixtures.decode(PageWire<FeedItemWire>.self, from: "feed_page_promo")

        let progress = try #require(page.items.last?.progress)
        #expect(progress.watchedAt == isoDate("2026-07-11T09:31:02.123Z"))
    }

    /// `banners`/`collections` alanı olmayan (veya null gelen) Keşfet yanıtı decode
    /// hatası üretmez — boş listeye düşer; koleksiyonlar geçerliyken Keşfet çökmez.
    @Test func bannersAlaniOlmayanKesfetYanitiDecodeOlur() throws {
        let json = Data(#"{ "collections": [] }"#.utf8)

        let wire = try Fixtures.decoder.decode(DiscoverWire.self, from: json)

        #expect(wire.banners.isEmpty)
        #expect(wire.collections.isEmpty)
    }

    @Test func nullBannerVeKoleksiyonAlanlariBosListeyeDuser() throws {
        let json = Data(#"{ "banners": null, "collections": null }"#.utf8)

        let wire = try Fixtures.decoder.decode(DiscoverWire.self, from: json)

        #expect(wire.banners.isEmpty)
        #expect(wire.collections.isEmpty)
    }

    /// 05 §12 kural 4'ün sınır hali: enum alanı null ya da string-olmayan bir değerle
    /// gelirse de decode hatası üretmez, `.unknown`a düşer.
    @Test func nullVeyaStringOlmayanEnumDegeriUnknownaDuser() throws {
        let json = Data(#"[null, 42, "episode", "seriesPromo"]"#.utf8)

        let types = try Fixtures.decoder.decode([FeedItem.ItemType].self, from: json)

        #expect(types == [.unknown, .unknown, .episode, .seriesPromo])
    }
}
