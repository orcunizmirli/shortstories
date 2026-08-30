import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import LibraryKit

/// Audit MEDIUM: örtüşen iki loadFavorites sıra-dışı commit'lerse (eski yükleme sonra biter), yeni-
/// silinmiş bir favori BAYAT listeyle dirilir. Generation guard eski (jetonu eskimiş) commit'i düşürür.
@MainActor
struct ListemFavoritesRaceTests {
    @Test func overlappingLoadFavoritesDoesNotResurrectRemoved() async throws {
        let repo = try PersistenceStore(inMemory: true).makeFavoritesRepository()
        let seriesX = SeriesID("x")
        let seriesY = SeriesID("y")
        try await repo.addFavorite(seriesX, at: Date())
        try await repo.addFavorite(seriesY, at: Date())
        let service = try FavoritesService(repository: repo, remoting: FakeFavoritesRemoting())
        let gate = SeriesInfoGate()
        let catalog = GatedCatalog(
            base: FakeLibraryCatalog(infos: [seriesX: Fixtures.info("x"), seriesY: Fixtures.info("y")]),
            gate: gate
        )
        let history = try ContinueWatchingService(
            repository: PersistenceStore(inMemory: true).makeWatchHistoryRepository(),
            remoting: FakeWatchProgressRemoting()
        )
        let model = ListemModel(
            favoritesService: service,
            continueWatchingService: history,
            catalog: catalog,
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )

        async let loadA: Void = model.load(.favorites) // favorites [x,y] okur, seriesInfo BLOKLANIR
        await gate.waitForArrival()
        try await repo.removeFavorite(seriesX) // store → [y]
        // B tam biter (seriesInfo gate'i geçer, [y] commit eder) — A hâlâ bloklu.
        await model.load(.favorites)
        #expect(model.favorites.count == 1) // B'den sonra: yalnız y

        await gate.open() // A serbest → A EN SON commit eder; guard eskimiş jetonu düşürür
        await loadA

        // Guard olmadan A bayat [x,y]'yi yazıp y'yi silineni DİRİLTİRDİ (count 2); guard ile düşürülür.
        #expect(model.favorites.count == 1)
    }

    @Test func overlappingLoadContinueDoesNotResurrectCompleted() async throws {
        // Audit MEDIUM (loadFavorites simetriği): örtüşen iki loadContinue sıra-dışı commit'lerse, sync ile
        // tamamlanıp Devam Et'ten düşen bir bölüm bayat listeyle dirilir. Generation guard eskimişi düşürür.
        let history = try ContinueWatchingService(
            repository: PersistenceStore(inMemory: true).makeWatchHistoryRepository(),
            remoting: FakeWatchProgressRemoting()
        )
        try await history.recordProgress(Fixtures.progress(episode: "e1", series: "s1", at: 100))
        try await history.recordProgress(Fixtures.progress(episode: "e2", series: "s2", at: 200))
        let gate = SeriesInfoGate()
        let catalog = GatedCatalog(
            base: FakeLibraryCatalog(infos: [SeriesID("s1"): Fixtures.info("s1"), SeriesID("s2"): Fixtures.info("s2")]),
            gate: gate
        )
        let favorites = try FavoritesService(
            repository: PersistenceStore(inMemory: true).makeFavoritesRepository(),
            remoting: FakeFavoritesRemoting()
        )
        let model = ListemModel(
            favoritesService: favorites,
            continueWatchingService: history,
            catalog: catalog,
            analytics: MockAnalytics(),
            delegate: ListemDelegateSpy()
        )

        async let loadA: Void = model.load(.continueWatching) // [e1,e2] okur, seriesInfo BLOKLANIR
        await gate.waitForArrival()
        // e1 tamamlandı → Devam Et'ten düşer (yalnız incomplete gösterilir).
        try await history.recordProgress(Fixtures.progress(episode: "e1", series: "s1", completed: true, at: 9000))
        await model.load(.continueWatching) // B: taze [e2] okur ve commit eder (A hâlâ bloklu)
        #expect(model.continueItems.count == 1)

        await gate.open() // A serbest → A EN SON commit; guard eskimiş jetonu düşürür
        await loadA

        // Guard olmadan A bayat [e1,e2]'yi yazıp tamamlanan e1'i DİRİLTİRDİ; guard ile düşürülür.
        #expect(model.continueItems.count == 1)
        #expect(!model.continueItems.contains { $0.episodeID == EpisodeID("e1") })
    }
}

// MARK: - İlk seriesInfo çağrısını bloklayan kapı (sonrakiler geçer) + gated katalog

private actor SeriesInfoGate {
    private var firstArrived = false
    private var released = false
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var arrivalWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if firstArrived {
            return
        } // ilk çağrı zaten geldi → sonrakiler hemen geçer
        firstArrived = true
        arrivalWaiter?.resume()
        arrivalWaiter = nil
        if released {
            return
        }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitForArrival() async {
        if firstArrived {
            return
        }
        await withCheckedContinuation { arrivalWaiter = $0 }
    }

    func open() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private final class GatedCatalog: LibraryCatalogReading, @unchecked Sendable {
    private let base: FakeLibraryCatalog
    private let gate: SeriesInfoGate

    init(base: FakeLibraryCatalog, gate: SeriesInfoGate) {
        self.base = base
        self.gate = gate
    }

    func seriesInfo(ids: [SeriesID]) async -> [SeriesID: LibrarySeriesInfo] {
        await gate.wait()
        return await base.seriesInfo(ids: ids)
    }

    func episodeNumbers(ids: [EpisodeID]) async -> [EpisodeID: Int] {
        await base.episodeNumbers(ids: ids)
    }
}
