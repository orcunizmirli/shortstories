import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import LibraryKit

@MainActor
@Suite("ListemModel (SS-120: segment, boş durum, düzenleme, niyetler)")
struct ListemModelTests {
    private func favoritesService(_ remoting: FakeFavoritesRemoting = FakeFavoritesRemoting()) throws -> FavoritesService {
        try FavoritesService(repository: PersistenceStore(inMemory: true).makeFavoritesRepository(), remoting: remoting)
    }

    private func historyService(
        _ remoting: FakeWatchProgressRemoting = FakeWatchProgressRemoting()
    ) throws -> ContinueWatchingService {
        try ContinueWatchingService(
            repository: PersistenceStore(inMemory: true).makeWatchHistoryRepository(),
            remoting: remoting
        )
    }

    private func makeModel(
        favorites: FavoritesService,
        history: ContinueWatchingService,
        catalog: FakeLibraryCatalog,
        analytics: MockAnalytics,
        delegate: ListemDelegateSpy,
        downloadsEnabled: Bool = false
    ) -> ListemModel {
        ListemModel(
            favoritesService: favorites,
            continueWatchingService: history,
            catalog: catalog,
            analytics: analytics,
            delegate: delegate,
            downloadsEnabled: downloadsEnabled
        )
    }

    // MARK: - Segment görünürlüğü

    @Test func downloadsSegmentHiddenByDefault() throws {
        let model = try makeModel(
            favorites: favoritesService(),
            history: historyService(),
            catalog: FakeLibraryCatalog(),
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )
        #expect(model.visibleSegments == [.favorites, .continueWatching])
        #expect(model.segment == .favorites)
    }

    @Test func downloadsSegmentVisibleWithFlag() throws {
        let model = try makeModel(
            favorites: favoritesService(),
            history: historyService(),
            catalog: FakeLibraryCatalog(),
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy(),
            downloadsEnabled: true
        )
        #expect(model.visibleSegments == [.favorites, .continueWatching, .downloads])
    }

    // MARK: - Boş durumlar

    @Test func emptyFavoritesYieldsEmptyStateAndScreenView() async throws {
        let analytics = MockAnalytics()
        let model = try makeModel(
            favorites: favoritesService(),
            history: historyService(),
            catalog: FakeLibraryCatalog(),
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )
        model.onAppear()
        await model.pendingWork()

        #expect(model.favoritesState == .empty)
        #expect(analytics.eventNames.contains("screen_view"))
    }

    @Test func emptyContinueYieldsEmptyState() async throws {
        let model = try makeModel(
            favorites: favoritesService(),
            history: historyService(),
            catalog: FakeLibraryCatalog(),
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )
        await model.load(.continueWatching)
        #expect(model.continueState == .empty)
    }

    // MARK: - Yükleme + katalog JOIN

    @Test func favoritesLoadJoinsCatalogNewestFirst() async throws {
        let favorites = try favoritesService()
        try await favorites.setFavorite(true, seriesID: SeriesID("s-old"), at: Date(timeIntervalSince1970: 1000))
        try await favorites.setFavorite(true, seriesID: SeriesID("s-new"), at: Date(timeIntervalSince1970: 3000))
        let catalog = FakeLibraryCatalog(infos: [
            SeriesID("s-old"): Fixtures.info("s-old", title: "Eski"),
            SeriesID("s-new"): Fixtures.info("s-new", title: "Yeni")
        ])
        let model = try makeModel(
            favorites: favorites,
            history: historyService(),
            catalog: catalog,
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )

        await model.load(.favorites)

        #expect(model.favoritesState == .loaded)
        #expect(model.favorites.map(\.seriesID) == [SeriesID("s-new"), SeriesID("s-old")])
        #expect(model.favorites.first?.title == "Yeni")
    }

    @Test func continueLoadBuildsItemsWithEpisodeNumbers() async throws {
        let history = try historyService()
        try await history.recordProgress(
            Fixtures.progress(episode: "e-1", series: "s-1", position: 62, duration: 100, at: 2000)
        )
        let catalog = FakeLibraryCatalog(
            infos: [SeriesID("s-1"): Fixtures.info("s-1", title: "İntikam")],
            numbers: [EpisodeID("e-1"): 7]
        )
        let model = try makeModel(
            favorites: favoritesService(),
            history: history,
            catalog: catalog,
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )

        await model.load(.continueWatching)

        #expect(model.continueState == .loaded)
        let item = try #require(model.continueItems.first)
        #expect(item.seriesTitle == "İntikam")
        #expect(item.episodeNumber == 7)
        #expect(item.progressPercent == 62)
    }

    // MARK: - Segment değişimi

    @Test func selectSegmentTracksChangeAndLoads() async throws {
        let analytics = MockAnalytics()
        let model = try makeModel(
            favorites: favoritesService(),
            history: historyService(),
            catalog: FakeLibraryCatalog(),
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )
        model.selectSegment(.continueWatching)
        await model.pendingWork()

        #expect(model.segment == .continueWatching)
        #expect(analytics.eventNames.contains("mylist_segment_changed"))
        #expect(model.continueState == .empty)
    }

    // MARK: - Düzenleme modu (çoklu silme)

    @Test func editModeMultiDeleteRemovesSelected() async throws {
        let favorites = try favoritesService()
        try await favorites.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await favorites.setFavorite(true, seriesID: SeriesID("s-2"), at: Date(timeIntervalSince1970: 2000))
        let catalog = FakeLibraryCatalog(infos: [
            SeriesID("s-1"): Fixtures.info("s-1"),
            SeriesID("s-2"): Fixtures.info("s-2")
        ])
        let analytics = MockAnalytics()
        let model = try makeModel(
            favorites: favorites,
            history: historyService(),
            catalog: catalog,
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )
        await model.load(.favorites)

        model.toggleEditing()
        model.toggleSelection(SeriesID("s-1"))
        model.toggleSelection(SeriesID("s-2"))
        #expect(model.selectedForRemoval.count == 2)

        await model.removeSelected()

        #expect(model.favorites.isEmpty)
        #expect(model.favoritesState == .empty)
        #expect(model.isEditing == false)
        #expect(analytics.eventNames.filter { $0 == "favorite_remove" }.count == 2)
        #expect(try await favorites.isFavorite(SeriesID("s-1")) == false)
    }

    /// WP-F1-G bulgu #6: `syncAndReload` sunucudan yeni ilerleme merge eder ama yalnız AKTİF
    /// segmenti reload eder. Aktif OLMAYAN segmentin (Devam Et) yükleme kaydı geçersizleşmezse
    /// kullanıcı ona dönünce BAYAT veri görür. Sync sonrası kayıt sıfırlanmalı → sonraki
    /// `selectSegment` taze yükler (retention yüzeyi taze).
    @Test func syncAndReloadRefreshesInactiveSegmentOnNextSelect() async throws {
        let remoting = FakeWatchProgressRemoting()
        let history = try ContinueWatchingService(
            repository: PersistenceStore(inMemory: true).makeWatchHistoryRepository(),
            remoting: remoting
        )
        let catalog = FakeLibraryCatalog(
            infos: [SeriesID("s-1"): Fixtures.info("s-1")],
            numbers: [EpisodeID("e-1"): 3]
        )
        let model = try makeModel(
            favorites: favoritesService(),
            history: history,
            catalog: catalog,
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )

        // Devam Et'i bir kez ziyaret et (boş) → loadedSegments'e girer.
        model.selectSegment(.continueWatching)
        await model.pendingWork()
        #expect(model.continueItems.isEmpty)
        // Aktif segmenti Favoriler'e taşı.
        model.selectSegment(.favorites)
        await model.pendingWork()

        // Sunucu artık yeni bir ilerleme taşıyor; sync bunu yerel depoya merge eder.
        remoting.setServer([Fixtures.progress(episode: "e-1", series: "s-1", position: 30, at: 5000)])
        await model.syncAndReload()

        // Devam Et'e dönünce TAZE veri görünmeli (bayat boş değil).
        model.selectSegment(.continueWatching)
        await model.pendingWork()
        #expect(model.continueItems.map(\.episodeID) == [EpisodeID("e-1")])
    }

    /// WP-F1-G bulgu #7: düzenleme modunda context-menu tek kaldırma, seçili ID'yi
    /// `selectedForRemoval`'dan da düşürmeli; aksi halde "Kaldır (N)" sayacı şişer.
    @Test func removeFavoriteClearsItFromSelectionInEditMode() async throws {
        let favorites = try favoritesService()
        try await favorites.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await favorites.setFavorite(true, seriesID: SeriesID("s-2"), at: Date(timeIntervalSince1970: 2000))
        let catalog = FakeLibraryCatalog(infos: [
            SeriesID("s-1"): Fixtures.info("s-1"),
            SeriesID("s-2"): Fixtures.info("s-2")
        ])
        let model = try makeModel(
            favorites: favorites,
            history: historyService(),
            catalog: catalog,
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )
        await model.load(.favorites)

        model.toggleEditing()
        model.toggleSelection(SeriesID("s-1"))
        model.toggleSelection(SeriesID("s-2"))
        #expect(model.selectedForRemoval.count == 2)

        // Context menüden s-1'i tek tek kaldır: seçim setinden de düşmeli.
        await model.removeFavorite(SeriesID("s-1"))

        #expect(model.selectedForRemoval == [SeriesID("s-2")])
    }

    @Test func removeSingleFavoriteFromContextMenu() async throws {
        let favorites = try favoritesService()
        try await favorites.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        let catalog = FakeLibraryCatalog(infos: [SeriesID("s-1"): Fixtures.info("s-1")])
        let analytics = MockAnalytics()
        let model = try makeModel(
            favorites: favorites,
            history: historyService(),
            catalog: catalog,
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )
        await model.load(.favorites)

        await model.removeFavorite(SeriesID("s-1"))

        #expect(model.favorites.isEmpty)
        let removeEvent = try #require(analytics.events.first { $0.name == "favorite_remove" })
        #expect(removeEvent.parameters["source"] == .string("listem"))
    }
}
