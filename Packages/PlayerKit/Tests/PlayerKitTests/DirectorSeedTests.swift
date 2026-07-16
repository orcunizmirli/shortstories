import AppFoundation
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// FeedPlaybackDirector feed-entry/seed API (SS-062/065): `seed` + `settleInitial`
// seed'lenen içeriği İLK gösterir ve verilen konumdan oynatır; seed yoksa mevcut
// index-0 davranışı değişmez; sonrası mevcut auto-advance akışına devam eder.
// Harness/yardımcılar (makeDirector/collectDecisions) FeedPlaybackDirectorTests.swift'te.

/// `.timeLimit` yalnız gerçek bir teslim-regresyonunda sonsuz asılmayı engelleyen güvenlik
/// tavanıdır; auto-advance beklemesi OLAY-GÜDÜMLÜ'dür (`awaitDecisions`, duvar-saati poll'ü yok).
@Suite("FeedPlaybackDirector — feed-entry/seed", .timeLimit(.minutes(1)))
struct DirectorSeedTests {
    @Test("Seed yok: settleInitial index 0'dan aktive eder (mevcut davranış)")
    func noSeedActivatesFirst() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 5))
        let result = await harness.director.settleInitial(startType: .tap, now: harness.clock.now)

        #expect(result.index == 0)
        guard case let .activated(_, episode) = result.outcome else {
            Issue.record("activated bekleniyordu")
            return
        }
        #expect(episode.id == EpisodeID("e0"))
        #expect(harness.pool.calls.first == .activate(EpisodeID("e0"), feedIndex: 0, resumePosition: nil))
    }

    @Test("Seed edilen bölüm İLK aktive edilir ve konumdan oynar (SS-065)")
    func seedActivatesTargetEpisodeFromPosition() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 5))
        await harness.director.seed(
            FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e3"), startPositionSeconds: 42)
        )
        let result = await harness.director.settleInitial(startType: .tap, now: harness.clock.now)

        #expect(result.index == 3)
        guard case let .activated(_, episode) = result.outcome else {
            Issue.record("activated bekleniyordu")
            return
        }
        #expect(episode.id == EpisodeID("e3"))
        // İlk activate seed edilen indeks + konumla koşar (havuz resumePosition = seek noktası).
        #expect(harness.pool.calls.first == .activate(EpisodeID("e3"), feedIndex: 3, resumePosition: 42))
    }

    @Test("Seed konumu 0: öğenin kendi devam kaydı uygulanır (override yok)")
    func seedWithZeroPositionUsesItemProgress() async throws {
        var items = Fixture.feedItems(count: 5)
        let episode2 = try #require(items[2].episode)
        items[2] = Fixture.feedItem(
            episode: episode2,
            series: items[2].series,
            progress: Fixture.progress(for: episode2, positionSec: 30) // 3 < 30 < 90*0.9
        )
        let harness = await makeDirector(items: items)
        await harness.director.seed(
            FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e2"), startPositionSeconds: 0)
        )
        let result = await harness.director.settleInitial(startType: .tap, now: harness.clock.now)

        #expect(result.index == 2)
        // Konum 0 → FeedResumePolicy devreye girer: kaldığı yerden (30 sn) resume.
        #expect(harness.pool.calls.first == .activate(EpisodeID("e2"), feedIndex: 2, resumePosition: 30))
    }

    @Test("Eşleşmeyen seed: settleInitial varsayılan index 0'a düşer")
    func unmatchableSeedFallsBackToFirst() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        await harness.director.seed(FeedEntry(seriesID: SeriesID("yok"), episodeID: EpisodeID("yok")))
        let result = await harness.director.settleInitial(startType: .tap, now: harness.clock.now)

        #expect(result.index == 0)
        #expect(harness.pool.calls.first == .activate(EpisodeID("e0"), feedIndex: 0, resumePosition: nil))
    }

    @Test("Seed sonrası auto-advance korunur: bölüm bitince sonraki karta geçiş")
    func autoAdvanceContinuesAfterSeed() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 5))

        await harness.director.seed(FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e2")))
        let result = await harness.director.settleInitial(startType: .tap, now: harness.clock.now)
        #expect(result.index == 2)

        harness.pool.backend(for: EpisodeID("e2"))?.emit(.playedToEnd)
        let decisions = await awaitDecisions(1, from: harness.director)
        #expect(decisions == [.advance(toIndex: 3)])
    }

    @Test("Seed bir kez tüketilir: ikinci settleInitial seed'i tekrar uygulamaz")
    func seedIsConsumedOnce() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 5))
        await harness.director.seed(
            FeedEntry(seriesID: SeriesID("s1"), episodeID: EpisodeID("e3"), startPositionSeconds: 42)
        )
        let first = await harness.director.settleInitial(startType: .tap, now: harness.clock.now)
        #expect(first.index == 3)

        // Seed tükendi: ikinci ilk-yerleşim çözümü artık index 0'dır (varsayılan).
        let second = await harness.director.settleInitial(startType: .tap, now: harness.clock.now)
        #expect(second.index == 0)
    }
}
