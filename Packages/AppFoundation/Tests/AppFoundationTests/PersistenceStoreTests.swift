import Foundation
import Testing
@testable import AppFoundation

/// `PersistenceStore` tek `ModelContainer` sahibidir (03 §9). In-memory yapılandırma
/// testler için gerçek disk yerine kullanılır; migration planı (V1) ile kurulur.
struct PersistenceStoreTests {
    @Test func inMemoryContainerBuildsWithMigrationPlan() throws {
        // Throw etmemesi, `VersionedSchema` + `SchemaMigrationPlan`'ın tutarlı olduğunu doğrular.
        let store = try PersistenceStore(inMemory: true)
        // Fabrikalar bağımsız repository yüzeyleri üretir.
        _ = store.makeWatchHistoryRepository()
        _ = store.makeFavoritesRepository()
        _ = store.makeCatalogCacheStore()
        _ = store.makeAssetCacheIndex()
    }

    @Test func repositoriesShareTheSameContainer() async throws {
        // Aynı store'dan üretilen iki WatchHistory yüzeyi aynı altta yatan veriyi görür.
        let store = try PersistenceStore(inMemory: true)
        let writer = store.makeWatchHistoryRepository()
        let reader = store.makeWatchHistoryRepository()

        let record = WatchProgressRecord(
            episodeID: EpisodeID("ep-1"),
            seriesID: SeriesID("s-1"),
            positionSec: 12,
            durationSec: 100,
            completed: false,
            watchedAt: Date(timeIntervalSince1970: 1000)
        )
        try await writer.saveProgress(record)

        let read = try await reader.progress(forEpisode: EpisodeID("ep-1"))
        #expect(read?.positionSec == 12)
    }

    /// WP-F1-G bulgu #9: fabrikalar TEK örneği (tek serileştirme noktası / tek `ModelContext`)
    /// döndürmeli. Her `makeX` yeni bir `@ModelActor` üretirse aynı store'dan alınan iki
    /// repository ayrı context'lerde bayat okuyup birbirinin daha yeni yazmasını ezebilir.
    /// Aynı örnek ⇒ cross-context tutarsızlık YAPISAL olarak imkânsız.
    @Test func factoriesReturnSameInstancePerStore() throws {
        let store = try PersistenceStore(inMemory: true)

        #expect(store.makeWatchHistoryRepository() as AnyObject === store.makeWatchHistoryRepository() as AnyObject)
        #expect(store.makeFavoritesRepository() as AnyObject === store.makeFavoritesRepository() as AnyObject)
        #expect(store.makeCatalogCacheStore() as AnyObject === store.makeCatalogCacheStore() as AnyObject)
        #expect(store.makeAssetCacheIndex() as AnyObject === store.makeAssetCacheIndex() as AnyObject)
    }

    /// Farklı store örnekleri ayrı container/actor tutar (izolasyon korunur).
    @Test func distinctStoresReturnDistinctInstances() throws {
        let storeA = try PersistenceStore(inMemory: true)
        let storeB = try PersistenceStore(inMemory: true)
        #expect(storeA.makeWatchHistoryRepository() as AnyObject !== storeB.makeWatchHistoryRepository() as AnyObject)
    }
}
