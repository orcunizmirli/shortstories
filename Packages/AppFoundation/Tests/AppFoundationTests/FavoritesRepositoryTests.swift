import Foundation
import Testing
@testable import AppFoundation

struct FavoritesRepositoryTests {
    private func makeRepo() throws -> any FavoritesRepository {
        try PersistenceStore(inMemory: true).makeFavoritesRepository()
    }

    @Test func addThenIsFavorite() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        #expect(try await repo.isFavorite(SeriesID("s-1")))
        #expect(try await repo.isFavorite(SeriesID("s-2")) == false)
    }

    @Test func favoritesSortedByRecency() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-old"), at: Date(timeIntervalSince1970: 1000))
        try await repo.addFavorite(SeriesID("s-new"), at: Date(timeIntervalSince1970: 3000))
        try await repo.addFavorite(SeriesID("s-mid"), at: Date(timeIntervalSince1970: 2000))

        let list = try await repo.favorites()
        #expect(list.map(\.seriesID) == [SeriesID("s-new"), SeriesID("s-mid"), SeriesID("s-old")])
    }

    @Test func addQueuesPendingAdd() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        let pending = try await repo.pendingSync()
        #expect(pending == [PendingFavoriteSync(seriesID: SeriesID("s-1"), state: .pendingAdd)])
    }

    @Test func removingUnsyncedPendingAddDeletesImmediately() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await repo.removeFavorite(SeriesID("s-1"))

        #expect(try await repo.isFavorite(SeriesID("s-1")) == false)
        // Hiç senkronlanmamış kayıt doğrudan silindiği için kuyruk boş.
        #expect(try await repo.pendingSync().isEmpty)
    }

    @Test func removingSyncedFavoriteQueuesPendingRemove() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await repo.confirmAdd(SeriesID("s-1")) // synced

        try await repo.removeFavorite(SeriesID("s-1"))
        // pendingRemove olan kayıt artık favori sayılmaz.
        #expect(try await repo.isFavorite(SeriesID("s-1")) == false)
        #expect(try await repo.favorites().isEmpty)
        #expect(try await repo.pendingSync() == [PendingFavoriteSync(seriesID: SeriesID("s-1"), state: .pendingRemove)])
    }

    @Test func reAddingPendingRemoveGoesBackToPendingAdd() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await repo.confirmAdd(SeriesID("s-1"))
        try await repo.removeFavorite(SeriesID("s-1")) // pendingRemove
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 4000)) // geri ekle

        #expect(try await repo.isFavorite(SeriesID("s-1")))
        #expect(try await repo.pendingSync() == [PendingFavoriteSync(seriesID: SeriesID("s-1"), state: .pendingAdd)])
    }

    @Test func confirmAddClearsPending() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await repo.confirmAdd(SeriesID("s-1"))
        #expect(try await repo.pendingSync().isEmpty)
        #expect(try await repo.isFavorite(SeriesID("s-1")))
    }

    @Test func confirmRemovalDeletesRecord() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await repo.confirmAdd(SeriesID("s-1"))
        try await repo.removeFavorite(SeriesID("s-1")) // pendingRemove
        try await repo.confirmRemoval(SeriesID("s-1"))

        #expect(try await repo.isFavorite(SeriesID("s-1")) == false)
        #expect(try await repo.pendingSync().isEmpty)
        #expect(try await repo.favorites().isEmpty)
    }

    /// Batch kaldırma (02 §4.12 çoklu silme): TEK çağrıda karışık durumları `removeFavorite` ile
    /// AYNI semantikte işler — `pendingAdd` doğrudan silinir, `synced` `pendingRemove` olur, listede
    /// olmayan ID no-op; verilmeyen favori dokunulmadan kalır.
    @Test func removeFavoritesBatchHandlesMixedStatesInOnePass() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-add"), at: Date(timeIntervalSince1970: 1000)) // pendingAdd
        try await repo.addFavorite(SeriesID("s-synced"), at: Date(timeIntervalSince1970: 2000))
        try await repo.confirmAdd(SeriesID("s-synced")) // synced
        try await repo.addFavorite(SeriesID("s-keep"), at: Date(timeIntervalSince1970: 3000))
        try await repo.confirmAdd(SeriesID("s-keep")) // synced, dokunulmayacak

        try await repo.removeFavorites([SeriesID("s-add"), SeriesID("s-synced"), SeriesID("s-missing")])

        // pendingAdd doğrudan silindi → kuyrukta yok; synced → pendingRemove; keep dokunulmadı.
        #expect(try await repo.isFavorite(SeriesID("s-add")) == false)
        #expect(try await repo.isFavorite(SeriesID("s-synced")) == false)
        #expect(try await repo.isFavorite(SeriesID("s-keep")))
        #expect(try await repo.favorites().map(\.seriesID) == [SeriesID("s-keep")])
        #expect(try await repo.pendingSync() == [PendingFavoriteSync(seriesID: SeriesID("s-synced"), state: .pendingRemove)])
    }

    /// Boş kümede batch kaldırma no-op (throw etmez, kayıtları değiştirmez).
    @Test func removeFavoritesEmptySetIsNoOp() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await repo.removeFavorites([])
        #expect(try await repo.isFavorite(SeriesID("s-1")))
        #expect(try await repo.favorites().map(\.seriesID) == [SeriesID("s-1")])
    }

    /// SS-132 veri-izolasyonu (05 §3.3 hesap değişimi): `deleteAll()` TÜM favori kayıtlarını
    /// (synced + pendingAdd + pendingRemove) siler. Misafir→mevcut hesaba geçişte store sıfırlanır
    /// → yeni hesap önceki misafirin favorilerini GÖRMEZ ve bekleyen işlemler yeni hesaba SIZMAZ.
    @Test func deleteAllRemovesEverySyncStateRecord() async throws {
        let repo = try makeRepo()
        try await repo.addFavorite(SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000)) // pendingAdd
        try await repo.addFavorite(SeriesID("s-2"), at: Date(timeIntervalSince1970: 2000))
        try await repo.confirmAdd(SeriesID("s-2")) // synced
        try await repo.removeFavorite(SeriesID("s-2")) // pendingRemove
        #expect(try await repo.pendingSync().isEmpty == false)

        try await repo.deleteAll()

        #expect(try await repo.favorites().isEmpty)
        #expect(try await repo.isFavorite(SeriesID("s-1")) == false)
        #expect(try await repo.isFavorite(SeriesID("s-2")) == false)
        #expect(try await repo.pendingSync().isEmpty)
    }

    /// Boş store'da `deleteAll()` idempotenttir (throw etmez, no-op).
    @Test func deleteAllOnEmptyStoreIsNoOp() async throws {
        let repo = try makeRepo()
        try await repo.deleteAll()
        #expect(try await repo.favorites().isEmpty)
    }
}
