import AppFoundation
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// FeedSeedPolicy: seed (feed-entry) → ilk indeks + başlangıç konumu SAF çözümü
// (SS-062/065). Direktör yalnız uygular; eşleşme yoksa nil → varsayılan index 0.

@Suite("FeedSeedPolicy — seed çözümü")
struct FeedSeedPolicyTests {
    @Test("episodeID eşleşmesi: hedef indeks + kırpılmış konum")
    func exactEpisodeMatch() {
        let items = Fixture.feedItems(count: 5) // s1: e0..e4, durationSec 90
        let entry = FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e3"), startPositionSeconds: 42)

        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        #expect(resolution == FeedSeedPolicy.Resolution(index: 3, startPositionSeconds: 42))
    }

    @Test("episodeID yok: dizinin bölüm taşıyan ilk kartı seçilir")
    func seriesOnlyMatchesFirstEpisodeCard() {
        let items = Fixture.feedItems(count: 5)
        let entry = FeedEntry(seriesID: SeriesID("s1"), startPositionSeconds: 10)

        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        #expect(resolution == FeedSeedPolicy.Resolution(index: 0, startPositionSeconds: 10))
    }

    @Test("Eşleşme yoksa nil (feed varsayılan index 0'a döner)")
    func noMatchReturnsNil() {
        let items = Fixture.feedItems(count: 3)
        let entry = FeedEntry(seriesID: SeriesID("bilinmeyen"))
        #expect(FeedSeedPolicy.resolve(entry: entry, in: items) == nil)
    }

    @Test("Konum 0: override nil (öğenin kendi devam kaydı geçerli kalır)")
    func zeroPositionDefersToResumePolicy() {
        let items = Fixture.feedItems(count: 3)
        let entry = FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e1"), startPositionSeconds: 0)

        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        #expect(resolution == FeedSeedPolicy.Resolution(index: 1, startPositionSeconds: nil))
    }

    @Test("Negatif konum FeedEntry init'te 0'a kırpılır → override nil")
    func negativePositionClampsToZero() {
        let entry = FeedEntry(seriesID: SeriesID("s1"), startPositionSeconds: -5)
        #expect(entry.startPositionSeconds == 0)

        let items = Fixture.feedItems(count: 2)
        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        #expect(resolution?.startPositionSeconds == nil)
    }

    @Test("Süreyi aşan konum bölüm süresine kırpılır")
    func positionBeyondDurationIsClamped() {
        let items = Fixture.feedItems(count: 3) // durationSec 90
        let entry = FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e2"), startPositionSeconds: 500)

        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        #expect(resolution == FeedSeedPolicy.Resolution(index: 2, startPositionSeconds: 90))
    }

    @Test("episodeID feed'de yok ama dizi var: dizinin ilk kartına düşer")
    func missingEpisodeFallsBackToSeries() {
        let items = Fixture.feedItems(count: 4)
        let entry = FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e999"), startPositionSeconds: 7)

        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        #expect(resolution == FeedSeedPolicy.Resolution(index: 0, startPositionSeconds: 7))
    }

    @Test("Dizi eşleşmesi bölüm taşıyan kartı promo kartına tercih eder")
    func seriesMatchPrefersEpisodeCardOverPromo() {
        let promo = FeedItem(
            id: "promo-s2",
            type: .seriesPromo,
            episode: nil,
            series: Fixture.series(id: "s2"),
            progress: nil,
            reason: nil
        )
        let s2Episode = Fixture.feedItem(
            episode: Fixture.episode(id: "s2e0", seriesID: "s2", index: 1),
            series: Fixture.series(id: "s2")
        )
        let s1Episode = Fixture.feedItem(
            episode: Fixture.episode(id: "e0", seriesID: "s1", index: 1),
            series: Fixture.series(id: "s1")
        )
        let items = [promo, s2Episode, s1Episode] // promo index 0, s2 bölüm index 1

        let entry = FeedEntry(seriesID: SeriesID("s2"), startPositionSeconds: 12)
        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        #expect(resolution == FeedSeedPolicy.Resolution(index: 1, startPositionSeconds: 12))
    }

    @Test("Yalnız promo kartı olan dizi: o karta düşer (bölüm taşımasa da)")
    func promoOnlySeriesResolvesToPromoCard() {
        let promo = FeedItem(
            id: "promo-s2",
            type: .seriesPromo,
            episode: nil,
            series: Fixture.series(id: "s2"),
            progress: nil,
            reason: nil
        )
        let s1Episode = Fixture.feedItem(
            episode: Fixture.episode(id: "e0", seriesID: "s1", index: 1),
            series: Fixture.series(id: "s1")
        )
        let items = [s1Episode, promo]

        let entry = FeedEntry(seriesID: SeriesID("s2"), startPositionSeconds: 9)
        let resolution = FeedSeedPolicy.resolve(entry: entry, in: items)
        // Bölüm taşımayan kart: süre bilinmediğinden konum kırpılmadan taşınır (settle bölümsüz kalır).
        #expect(resolution == FeedSeedPolicy.Resolution(index: 1, startPositionSeconds: 9))
    }
}
