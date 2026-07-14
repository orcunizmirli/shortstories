import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

@MainActor
@Suite("DiziDetayModel")
struct DiziDetayModelTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let seriesID = SeriesID("srs_abc123")

    private func makeSeries() -> Series {
        Fixtures.series(
            id: "srs_abc123",
            title: "Gece Yarısı",
            tags: ["revenge"],
            episodeCount: 60,
            releasedEpisodeCount: 8,
            freeEpisodeCount: 5,
            releaseState: .ongoing,
            nextEpisodeAt: Date(timeIntervalSince1970: 1_609_459_200)
        )
    }

    /// 1-5 ücretsiz, 6-8 kilitli (70 coin), tümü yayınlanmış.
    private func makeEpisodes() -> [Episode] {
        (1 ... 8).map { index in
            let free = index <= 5
            return Fixtures.episode(
                seriesID: "srs_abc123",
                index: index,
                access: free ? .free : .locked,
                unlockPrice: free ? nil : 70,
                publishedAt: Date(timeIntervalSince1970: 1_600_000_000)
            )
        }
    }

    private func makeModel(
        catalog: SpyCatalog? = nil,
        history: FakeHistory = FakeHistory(),
        favorites: FakeFavorites = FakeFavorites(),
        entitlement: FakeEntitlements = FakeEntitlements(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: DiziDetayDelegateSpy? = nil
    ) -> DiziDetayModel {
        let spy = catalog ?? {
            let spy = SpyCatalog()
            spy.setSeriesDetail(.success(makeSeries()))
            spy.setEpisodes(.success(Page(items: makeEpisodes(), nextCursor: nil, ttlSec: nil)))
            return spy
        }()
        return DiziDetayModel(
            seriesID: seriesID,
            source: .kesfet,
            catalog: spy,
            history: history,
            favorites: favorites,
            entitlement: entitlement,
            analytics: analytics,
            delegate: delegate,
            now: { now }
        )
    }

    // MARK: - Yükleme

    @Test func loadPopulatesStateAndTracksDetailView() async {
        let analytics = MockAnalytics()
        let favorites = FakeFavorites(favorites: [seriesID])
        let model = makeModel(favorites: favorites, analytics: analytics)

        await model.load()

        #expect(model.loadState == .loaded)
        #expect(model.series?.title == "Gece Yarısı")
        #expect(model.episodes.count == 8)
        #expect(model.isFavorite)
        #expect(model.releaseInfo == .ongoingScheduled(nextEpisodeAt: Date(timeIntervalSince1970: 1_609_459_200)))
        let detail = analytics.events.first { $0.name == "series_detail_view" }
        #expect(detail?.parameters["free_episode_count"] == .int(5))
        #expect(detail?.parameters["total_episode_count"] == .int(60))
    }

    @Test func notFoundShowsRemovedState() async {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.failure(.content(.notFound)))
        spy.setEpisodes(.success(Page(items: [], nextCursor: nil, ttlSec: nil)))
        let model = makeModel(catalog: spy)

        await model.load()

        #expect(model.loadState == .removed)
    }

    @Test func offlineShowsOfflineState() async {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.failure(.network(.offline)))
        spy.setEpisodes(.failure(.network(.offline)))
        let model = makeModel(catalog: spy)

        await model.load()

        #expect(model.loadState == .offline)
    }

    // MARK: - CTA türetimi

    @Test func ctaStartWhenNoHistory() async {
        let delegate = DiziDetayDelegateSpy()
        let model = makeModel(delegate: delegate)
        await model.load()

        #expect(model.ctaTarget?.kind == .start)
        #expect(model.ctaTarget?.episodeNumber == 1)
        #expect(!model.ctaLocked)

        model.primaryCTA()
        #expect(delegate.started.first?.episodeNumber == 1)
        #expect(delegate.started.first?.position == 0)
    }

    @Test func ctaResumeUsesHistoryPosition() async {
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 3, positionSec: 42))
        let delegate = DiziDetayDelegateSpy()
        let model = makeModel(history: history, delegate: delegate)
        await model.load()

        #expect(model.ctaTarget == ContinueWatchingTarget(kind: .resume, episodeNumber: 3, startPositionSec: 42))
        model.primaryCTA()
        #expect(delegate.started.first?.episodeNumber == 3)
        #expect(delegate.started.first?.position == 42)
    }

    @Test func ctaLockedTargetOpensUnlockInsteadOfPlaying() async {
        // Tamamlanmış ep5 → hedef ep6 (kilitli, entitlement yok).
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 5, completed: true))
        let delegate = DiziDetayDelegateSpy()
        let analytics = MockAnalytics()
        let model = makeModel(history: history, analytics: analytics, delegate: delegate)
        await model.load()

        #expect(model.ctaTarget?.episodeNumber == 6)
        #expect(model.ctaLocked)

        model.primaryCTA()
        #expect(delegate.started.isEmpty)
        #expect(delegate.unlockIntents.first?.episodeNumber == 6)
        #expect(delegate.unlockIntents.first?.unlockPrice == 70)
        #expect(analytics.events.contains { $0.name == "series_cta_tapped" && $0.parameters["type"] == .string("continue") })
    }

    @Test func vipEntitlementUnlocksCtaTarget() async {
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 5, completed: true))
        let delegate = DiziDetayDelegateSpy()
        let model = makeModel(history: history, entitlement: FakeEntitlements(isVIP: true), delegate: delegate)
        await model.load()

        #expect(model.ctaTarget?.episodeNumber == 6)
        #expect(!model.ctaLocked)
        model.primaryCTA()
        #expect(delegate.started.first?.episodeNumber == 6)
    }

    // MARK: - Bölüm ızgarası

    @Test func cellStatesReflectHistoryAndLocks() async {
        let history = FakeHistory(progress: Fixtures.progress(
            seriesID: "srs_abc123",
            episodeIndex: 3,
            positionSec: 10,
            completed: false
        ))
        let model = makeModel(history: history)
        await model.load()

        #expect(model.cellState(for: model.episodes[0]) == .watched) // ep1 < 3
        #expect(model.cellState(for: model.episodes[2]) == .current) // ep3 = hedef
        #expect(model.cellState(for: model.episodes[3]) == .available) // ep4 açık, izlenmedi
        #expect(model.cellState(for: model.episodes[5]) == .locked(price: 70)) // ep6 kilitli
    }

    @Test func scheduledCellForUnpublishedEpisode() async {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(makeSeries()))
        let scheduled = Fixtures.episode(
            seriesID: "srs_abc123",
            index: 9,
            access: .locked,
            unlockPrice: 70,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        spy.setEpisodes(.success(Page(items: makeEpisodes() + [scheduled], nextCursor: nil, ttlSec: nil)))
        let model = makeModel(catalog: spy)
        await model.load()

        #expect(model.cellState(for: scheduled) == .scheduled)
    }

    @Test func selectAccessibleEpisodePlaysIt() async {
        let delegate = DiziDetayDelegateSpy()
        let analytics = MockAnalytics()
        let model = makeModel(analytics: analytics, delegate: delegate)
        await model.load()

        model.selectEpisode(model.episodes[1]) // ep2, ücretsiz

        #expect(delegate.started.first?.episodeNumber == 2)
        #expect(analytics.events.contains { $0.name == "episode_grid_tapped" && $0.parameters["locked"] == .bool(false) })
    }

    @Test func selectLockedEpisodeOpensUnlock() async {
        let delegate = DiziDetayDelegateSpy()
        let analytics = MockAnalytics()
        let model = makeModel(analytics: analytics, delegate: delegate)
        await model.load()

        model.selectEpisode(model.episodes[6]) // ep7, kilitli

        #expect(delegate.started.isEmpty)
        #expect(delegate.unlockIntents.first?.episodeNumber == 7)
        #expect(analytics.events.contains { $0.name == "episode_grid_tapped" && $0.parameters["locked"] == .bool(true) })
    }

    @Test func selectScheduledEpisodeIsNoOp() async {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(makeSeries()))
        let scheduled = Fixtures.episode(
            seriesID: "srs_abc123",
            index: 9,
            access: .locked,
            unlockPrice: 70,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        spy.setEpisodes(.success(Page(items: [scheduled], nextCursor: nil, ttlSec: nil)))
        let delegate = DiziDetayDelegateSpy()
        let model = makeModel(catalog: spy, delegate: delegate)
        await model.load()

        model.selectEpisode(scheduled)
        #expect(delegate.started.isEmpty)
        #expect(delegate.unlockIntents.isEmpty)
    }

    // MARK: - Favori / paylaş / etiket

    @Test func toggleFavoriteIsOptimisticAndPersists() async {
        let favorites = FakeFavorites()
        let analytics = MockAnalytics()
        let model = makeModel(favorites: favorites, analytics: analytics)
        await model.load()
        #expect(!model.isFavorite)

        await model.toggleFavorite()

        #expect(model.isFavorite)
        #expect(favorites.setCalls.last?.isFavorite == true)
        #expect(analytics.eventNames.contains("favorite_add"))
    }

    @Test func toggleFavoriteRevertsOnError() async {
        let favorites = FakeFavorites(failOnSet: true)
        let model = makeModel(favorites: favorites)
        await model.load()

        await model.toggleFavorite()

        #expect(!model.isFavorite) // geri alındı
    }

    @Test func shareProducesUniversalLink() async {
        let delegate = DiziDetayDelegateSpy()
        let analytics = MockAnalytics()
        let model = makeModel(analytics: analytics, delegate: delegate)
        await model.load()

        model.share()

        #expect(delegate.sharedURLs.first?.absoluteString == "https://shortseries.app/s/srs_abc123")
        #expect(analytics.eventNames.contains("share_tap"))
    }

    @Test func selectTagRoutesToDiscover() async {
        let delegate = DiziDetayDelegateSpy()
        let analytics = MockAnalytics()
        let model = makeModel(analytics: analytics, delegate: delegate)
        await model.load()

        model.selectTag(Tag(id: "revenge", name: "İntikam"))

        #expect(delegate.discoverGenres == ["revenge"])
        #expect(analytics.eventNames.contains("tag_tapped"))
    }

    @Test func loadMoreEpisodesAppends() async {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(makeSeries()))
        spy.setEpisodes(.success(Page(items: makeEpisodes(), nextCursor: "c2", ttlSec: nil)))
        let model = makeModel(catalog: spy)
        await model.load()
        #expect(model.episodes.count == 8)

        // İkinci sayfa
        spy.setEpisodes(.success(Page(
            items: [Fixtures.episode(seriesID: "srs_abc123", index: 9, access: .free)],
            nextCursor: nil,
            ttlSec: nil
        )))
        await model.loadMoreEpisodes()

        #expect(model.episodes.count == 9)
    }

    @Test func episodeBlocksComputedForLongSeries() async {
        let model = makeModel()
        await model.load()
        // episodeCount 60 → iki blok.
        #expect(model.episodeBlocks.map(\.title) == ["1-30", "31-60"])
    }
}
