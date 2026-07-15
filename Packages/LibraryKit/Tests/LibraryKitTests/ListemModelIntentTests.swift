import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import LibraryKit

@MainActor
@Suite("ListemModel — gizleme + navigasyon niyetleri (SS-120)")
struct ListemModelIntentTests {
    private func favoritesService() throws -> FavoritesService {
        try FavoritesService(
            repository: PersistenceStore(inMemory: true).makeFavoritesRepository(),
            remoting: FakeFavoritesRemoting()
        )
    }

    private func historyService() throws -> ContinueWatchingService {
        try ContinueWatchingService(
            repository: PersistenceStore(inMemory: true).makeWatchHistoryRepository(),
            remoting: FakeWatchProgressRemoting()
        )
    }

    private func makeModel(
        favorites: FavoritesService,
        history: ContinueWatchingService,
        catalog: FakeLibraryCatalog,
        analytics: MockAnalytics,
        delegate: ListemDelegateSpy
    ) -> ListemModel {
        ListemModel(
            favoritesService: favorites,
            continueWatchingService: history,
            catalog: catalog,
            analytics: analytics,
            delegate: delegate
        )
    }

    // MARK: - Devam Et gizleme (sola kaydır → "Kaldır")

    @Test func hideContinueItemRemovesAndTracks() async throws {
        let history = try historyService()
        try await history.recordProgress(Fixtures.progress(episode: "e-1", series: "s-1", at: 1000))
        let catalog = FakeLibraryCatalog(
            infos: [SeriesID("s-1"): Fixtures.info("s-1")],
            numbers: [EpisodeID("e-1"): 3]
        )
        let analytics = MockAnalytics()
        let model = try makeModel(
            favorites: favoritesService(),
            history: history,
            catalog: catalog,
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )
        await model.load(.continueWatching)
        let item = try #require(model.continueItems.first)

        model.hideContinueItem(item)

        #expect(model.continueItems.isEmpty)
        #expect(model.continueState == .empty)
        #expect(analytics.eventNames.contains("mylist_item_removed"))

        // Gizlenen kayıt yeniden yüklemede de görünmez (oturum içi is_hidden).
        await model.load(.continueWatching)
        #expect(model.continueItems.isEmpty)
    }

    // MARK: - Navigasyon niyetleri (delegate → App)

    @Test func openContinueEmitsAnalyticsAndResumeIntent() async throws {
        let history = try historyService()
        try await history.recordProgress(
            Fixtures.progress(episode: "e-1", series: "s-1", position: 62, duration: 100, at: 1000)
        )
        let catalog = FakeLibraryCatalog(
            infos: [SeriesID("s-1"): Fixtures.info("s-1")],
            numbers: [EpisodeID("e-1"): 7]
        )
        let analytics = MockAnalytics()
        let delegate = ListemDelegateSpy()
        let model = try makeModel(
            favorites: favoritesService(),
            history: history,
            catalog: catalog,
            analytics: analytics,
            delegate: delegate
        )
        await model.load(.continueWatching)
        let item = try #require(model.continueItems.first)

        model.openContinue(item)

        #expect(delegate.resumed == [
            .init(seriesID: SeriesID("s-1"), episodeID: EpisodeID("e-1"), position: 62)
        ])
        let event = try #require(analytics.events.first { $0.name == "continue_watching_tapped" })
        #expect(event.parameters["episode_number"] == .int(7))
        #expect(event.parameters["progress_pct"] == .int(62))
    }

    /// WP-F1-G bulgu #8: `continue_watching_tapped` bölüm numarası bilinmiyorken (katalog JOIN
    /// vermedi) `episode_number=0` GÖNDERMEMELİ — 0 geçersiz 1-tabanlı numaradır, huniyi kirletir.
    /// Parametre tamamen atlanır.
    @Test func continueTappedOmitsEpisodeNumberWhenUnknown() async throws {
        let history = try historyService()
        try await history.recordProgress(
            Fixtures.progress(episode: "e-1", series: "s-1", position: 50, duration: 100, at: 1000)
        )
        // Katalog bölüm numarası VERMEZ → episodeNumber nil.
        let catalog = FakeLibraryCatalog(infos: [SeriesID("s-1"): Fixtures.info("s-1")])
        let analytics = MockAnalytics()
        let model = try makeModel(
            favorites: favoritesService(),
            history: history,
            catalog: catalog,
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )
        await model.load(.continueWatching)
        let item = try #require(model.continueItems.first)
        #expect(item.episodeNumber == nil)

        model.openContinue(item)

        let event = try #require(analytics.events.first { $0.name == "continue_watching_tapped" })
        #expect(event.parameters["episode_number"] == nil)
        #expect(event.parameters["progress_pct"] == .int(50))
        #expect(event.parameters["series_id"] == .string("s-1"))
    }

    @Test func openFavoritePlaysAndTracks() async throws {
        let favorites = try favoritesService()
        try await favorites.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        let catalog = FakeLibraryCatalog(infos: [SeriesID("s-1"): Fixtures.info("s-1")])
        let analytics = MockAnalytics()
        let delegate = ListemDelegateSpy()
        let model = try makeModel(
            favorites: favorites,
            history: historyService(),
            catalog: catalog,
            analytics: analytics,
            delegate: delegate
        )
        await model.load(.favorites)
        let item = try #require(model.favorites.first)

        model.openFavorite(item)

        #expect(delegate.played == [SeriesID("s-1")])
        #expect(analytics.eventNames.contains("favorite_opened"))
    }

    @Test func unavailableFavoriteOpensDetailInsteadOfPlaying() async throws {
        let favorites = try favoritesService()
        try await favorites.setFavorite(true, seriesID: SeriesID("s-gone"), at: Date(timeIntervalSince1970: 1000))
        let analytics = MockAnalytics()
        let delegate = ListemDelegateSpy()
        // Katalog bu diziyi döndürmez → kaldırılmış (isAvailable=false).
        let model = try makeModel(
            favorites: favorites,
            history: historyService(),
            catalog: FakeLibraryCatalog(),
            analytics: analytics,
            delegate: delegate
        )
        await model.load(.favorites)
        let item = try #require(model.favorites.first)
        #expect(item.isAvailable == false)

        model.openFavorite(item)

        // Kaldırılmış içerik oynatılmaz; detaya yönlendirilir (§4.12).
        #expect(delegate.openedDetails == [SeriesID("s-gone")])
        #expect(delegate.played.isEmpty)
        #expect(analytics.eventNames.contains("favorite_opened") == false)
    }

    @Test func emptyStateCTAsRouteToDiscoverAndHome() throws {
        let delegate = ListemDelegateSpy()
        let model = try makeModel(
            favorites: favoritesService(),
            history: historyService(),
            catalog: FakeLibraryCatalog(),
            analytics: MockAnalytics(),
            delegate: delegate
        )
        model.openDiscover()
        model.openHome()
        #expect(delegate.discoverRequested == 1)
        #expect(delegate.homeRequested == 1)
    }
}
