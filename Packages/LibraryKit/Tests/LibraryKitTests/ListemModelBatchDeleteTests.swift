import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import LibraryKit

/// WP-F1-G'de ERTELENEN çoklu-silme optimizasyonu: `removeSelected` N ayrı yerel yazma yerine
/// TEK batch çağrısı (`FavoritesService.removeFavorites`) yapar. Ayrı suite: `ListemModelTests`
/// gövde-uzunluğu sınırını (SS-004 swiftlint) aşmadan tut.
@MainActor
@Suite("ListemModel çoklu silme (WP-F1-G batch opt)")
struct ListemModelBatchDeleteTests {
    /// Çoklu silme TEK batch çağrısı yapar — N ayrı `removeFavorite` yerine tek `removeFavorites`.
    /// Yalnız seçilenler kalkar, düzenleme kapanır, kaldırma başına analitik korunur.
    @Test func removeSelectedIssuesSingleBatchCall() async throws {
        let counting = try CountingFavoritesRepository(base: PersistenceStore(inMemory: true).makeFavoritesRepository())
        let favorites = FavoritesService(repository: counting, remoting: FakeFavoritesRemoting())
        try await favorites.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await favorites.setFavorite(true, seriesID: SeriesID("s-2"), at: Date(timeIntervalSince1970: 2000))
        try await favorites.setFavorite(true, seriesID: SeriesID("s-3"), at: Date(timeIntervalSince1970: 3000))
        let history = try ContinueWatchingService(
            repository: PersistenceStore(inMemory: true).makeWatchHistoryRepository(),
            remoting: FakeWatchProgressRemoting()
        )
        let catalog = FakeLibraryCatalog(infos: [
            SeriesID("s-1"): Fixtures.info("s-1"),
            SeriesID("s-2"): Fixtures.info("s-2"),
            SeriesID("s-3"): Fixtures.info("s-3")
        ])
        let analytics = MockAnalytics()
        let model = ListemModel(
            favoritesService: favorites,
            continueWatchingService: history,
            catalog: catalog,
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )
        await model.load(.favorites)

        model.toggleEditing()
        model.toggleSelection(SeriesID("s-1"))
        model.toggleSelection(SeriesID("s-3"))

        await model.removeSelected()

        // Tek batch çağrısı: tekil `removeFavorite` HİÇ çağrılmadı.
        #expect(counting.removeFavoritesCalls == 1)
        #expect(counting.removeFavoriteCalls == 0)
        #expect(model.favorites.map(\.seriesID) == [SeriesID("s-2")])
        #expect(model.isEditing == false)
        #expect(model.selectedForRemoval.isEmpty)
        #expect(analytics.eventNames.filter { $0 == "favorite_remove" }.count == 2)
    }

    /// Boş seçimde `removeSelected` no-op: hiç repository yazması / analitik olayı üretmez.
    @Test func removeSelectedWithEmptySelectionIsNoOp() async throws {
        let counting = try CountingFavoritesRepository(base: PersistenceStore(inMemory: true).makeFavoritesRepository())
        let favorites = FavoritesService(repository: counting, remoting: FakeFavoritesRemoting())
        let history = try ContinueWatchingService(
            repository: PersistenceStore(inMemory: true).makeWatchHistoryRepository(),
            remoting: FakeWatchProgressRemoting()
        )
        let analytics = MockAnalytics()
        let model = ListemModel(
            favoritesService: favorites,
            continueWatchingService: history,
            catalog: FakeLibraryCatalog(),
            analytics: analytics,
            delegate: ListemDelegateSpy()
        )

        await model.removeSelected()

        #expect(counting.removeFavoritesCalls == 0)
        #expect(counting.removeFavoriteCalls == 0)
        #expect(analytics.eventNames.contains("favorite_remove") == false)
    }
}
