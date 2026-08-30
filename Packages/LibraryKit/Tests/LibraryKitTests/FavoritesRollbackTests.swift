import AppFoundation
import Foundation
import Testing
@testable import LibraryKit

/// FavoritesService KALICI-red rollback (audit LOW, ürün kararı: rollback). Kalıcı 4xx içerik reddinde
/// iyimser yerel yazma GERİ ALINIR (süresiz retry + kalıcı "favorili" yalanı yerine sunucu-tutarlılığı);
/// GEÇİCİ (5xx/timeout) hatalar pending kalır (retry). DELETE 404 idempotent başarı.
@Suite("FavoritesService kalıcı-red rollback")
struct FavoritesRollbackTests {
    private func makeRepo() throws -> any FavoritesRepository {
        try PersistenceStore(inMemory: true).makeFavoritesRepository()
    }

    private func makeService(remoting: FakeFavoritesRemoting) throws -> FavoritesService {
        try FavoritesService(repository: makeRepo(), remoting: remoting)
    }

    @Test func kaliciRedPutIyimserFavoriyiGeriAlir() async throws {
        let remoting = FakeFavoritesRemoting()
        let service = try makeService(remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1))
        remoting.setError(for: SeriesID("s-1"), .network(.server(status: 422))) // KALICI 4xx

        try await service.synchronize()

        #expect(try await service.isFavorite(SeriesID("s-1")) == false) // rollback: favori geri alındı
        #expect(try await service.pendingSyncCount() == 0) // artık pending değil (süresiz retry biter)
    }

    @Test func geciciRedPutPendingBirakir() async throws {
        let remoting = FakeFavoritesRemoting()
        let service = try makeService(remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1))
        remoting.setError(for: SeriesID("s-1"), .network(.server(status: 500))) // GEÇİCİ 5xx

        try await service.synchronize()

        #expect(try await service.isFavorite(SeriesID("s-1"))) // korunur (rollback YOK)
        #expect(try await service.pendingSyncCount() == 1) // pending kalır → ağ dönünce retry
    }

    @Test func deleteNotFoundIdempotentBasari() async throws {
        let remoting = FakeFavoritesRemoting()
        let service = try makeService(remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1))
        try await service.synchronize() // synced
        try await service.setFavorite(false, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 2)) // pendingRemove
        remoting.setError(for: SeriesID("s-1"), .network(.server(status: 404))) // zaten yok

        try await service.synchronize()

        #expect(try await service.isFavorite(SeriesID("s-1")) == false) // idempotent silme başarısı
        #expect(try await service.pendingSyncCount() == 0)
    }

    @Test func kaliciRedDeleteFavoriyiGeriYukler() async throws {
        let remoting = FakeFavoritesRemoting()
        let service = try makeService(remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1))
        try await service.synchronize() // synced
        try await service.setFavorite(false, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 2)) // pendingRemove
        remoting.setError(for: SeriesID("s-1"), .network(.server(status: 403))) // KALICI red

        try await service.synchronize()

        #expect(try await service.isFavorite(SeriesID("s-1"))) // rollback: favori KORUNUR (kaldırma reddedildi)
        #expect(try await service.pendingSyncCount() == 0) // artık pending değil
    }
}
