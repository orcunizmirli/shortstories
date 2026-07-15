import Foundation
import SwiftData

/// Tek `ModelContainer`'ın sahibi ve repository/indeks somut uygulamalarının fabrikası
/// (03 §9). Container `ShortSeriesApp` kompozisyon kökünde bir kez kurulur ve
/// Repository'lere init ile verilir; ViewModel/View asla `ModelContext`'e dokunmaz.
///
/// **Concurrency (03 §7.3, §9):** Her repository yüzeyi container'a bağlı bir `@ModelActor`'dır
/// ve `init`'te BİR KEZ kurulur; `makeX` fabrikaları her çağrıda AYNI örneği döndürür. Böylece
/// her tür için TEK bir `ModelContext` (tek serileştirme noktası) olur — aynı store'dan alınan
/// iki repository ayrı context'lerde bayat okuyup birbirinin daha yeni yazmasını EZEMEZ (bulgu
/// #9, cross-context tutarsızlık yapısal olarak imkânsız). Yazma/okuma actor'a hapsedilmiş arka
/// plan context'inde yürür — ana thread'e I/O sokulmaz.
///
/// **`inMemory` (testler):** `true` iken store gerçek disk yerine bellek içinde tutulur;
/// böylece testler yan etkisiz ve izole koşar.
public struct PersistenceStore: Sendable {
    private let container: ModelContainer
    // Tür başına TEK örnek (bulgu #9): fabrikalar bunları döndürür, her çağrıda yeni üretmez.
    private let watchHistory: any WatchHistoryRepository
    private let favorites: any FavoritesRepository
    private let catalogCache: any CatalogCacheStore
    private let assetCache: any AssetCacheIndexing

    /// - Parameter inMemory: `true` ise store diske yazılmaz (test yapılandırması).
    public init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: PersistenceSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PersistenceMigrationPlan.self,
            configurations: configuration
        )
        self.container = container
        watchHistory = WatchHistoryStore(modelContainer: container)
        favorites = FavoritesStore(modelContainer: container)
        catalogCache = CatalogCache(modelContainer: container)
        assetCache = AssetCacheIndex(modelContainer: container)
    }

    /// İzleme geçmişi + "kaldığı yer" deposu (`LibraryKit` tüketir — 03 §9). Store başına tek örnek.
    public func makeWatchHistoryRepository() -> any WatchHistoryRepository {
        watchHistory
    }

    /// Favoriler (Listem) deposu (`LibraryKit` tüketir). Store başına tek örnek.
    public func makeFavoritesRepository() -> any FavoritesRepository {
        favorites
    }

    /// Katalog cache metadata defteri (`ContentKit` tüketir). Store başına tek örnek.
    public func makeCatalogCacheStore() -> any CatalogCacheStore {
        catalogCache
    }

    /// Video cache LRU indeksi (`PlayerKit` tüketir — 04 §7.2). Store başına tek örnek.
    public func makeAssetCacheIndex() -> any AssetCacheIndexing {
        assetCache
    }
}
