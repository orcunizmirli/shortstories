import Foundation
import Testing
@testable import AppFoundation

/// WP-F1-G OPT-2 LOW bulgusunun TDD kapsamı: lightweight migration eski cache satırlarına
/// `sizeBytes = 0` back-fill eder → tahliye byte-bütçesine 0 katkı verir (byte-cap o satırlar
/// re-store edilene dek eksik sayar). Düzeltme, ilk şema-uyumlu okumada gerçek `payload.count`'ı
/// LAZY olarak geri yazar; bu yazma OPT-1 dirty-stamp'iyle coalesce olur (okuma başına ayrı disk
/// `save()` YOK — write-on-read regresyonu yok). Beyaz-kutu doğrulamalar için somut `CatalogCache`'e
/// iner (`persistedSaveCount`, `storedSeriesSizeBytes`, `insertMigrationBackfilled*` iç API'ler).
struct CatalogCacheBackfillTests {
    private func makeConcreteStore() throws -> CatalogCache {
        let store = try PersistenceStore(inMemory: true).makeCatalogCacheStore()
        return try #require(store as? CatalogCache)
    }

    /// Series okuma yolu: `sizeBytes == 0` + dolu payload'lı migrasyon satırı ilk okumada gerçek
    /// boyutunu kazanır (RED: mevcut kodda 0 kalır) — ama OPT-1 korunur: okuma disk `save()`
    /// TETİKLEMEZ (`persistedSaveCount` sabit; back-fill dirty-stamp'e coalesce olur).
    @Test func migrationBackfilledSeriesGainsSizeBytesOnFirstReadWithoutDiskSave() async throws {
        let cache = try makeConcreteStore()
        let payload = Data(count: 4096)
        try await cache.insertMigrationBackfilledSeries(
            id: SeriesID("s-1"),
            payload: payload,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        // Migrasyon back-fill durumu: payload dolu ama sizeBytes 0.
        #expect(try await cache.storedSeriesSizeBytes(id: SeriesID("s-1")) == 0)
        let base = await cache.persistedSaveCount

        // İlk okuma sizeBytes'ı payload.count'a onarır ...
        #expect(try await cache.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1)?.payload == payload)
        #expect(try await cache.storedSeriesSizeBytes(id: SeriesID("s-1")) == 4096)
        // ... ama OPT-1 korunur: okuma disk save() yapmaz (dirty-stamp'e coalesce).
        #expect(await cache.persistedSaveCount == base)
    }

    /// Episode-list okuma yolu için aynı back-fill onarımı + OPT-1 korunumu.
    @Test func migrationBackfilledEpisodeListGainsSizeBytesOnFirstReadWithoutDiskSave() async throws {
        let cache = try makeConcreteStore()
        let payload = Data(count: 5678)
        try await cache.insertMigrationBackfilledEpisodeList(
            seriesID: SeriesID("s-1"),
            payload: payload,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(try await cache.storedEpisodeListSizeBytes(seriesID: SeriesID("s-1")) == 0)
        let base = await cache.persistedSaveCount

        #expect(try await cache.cachedEpisodeList(seriesID: SeriesID("s-1"), expectedSchemaVersion: 1)?.payload == payload)
        #expect(try await cache.storedEpisodeListSizeBytes(seriesID: SeriesID("s-1")) == 5678)
        #expect(await cache.persistedSaveCount == base)
    }

    /// Back-fill onarımı tahliye byte-bütçesini düzeltir. `sizeBytes == 0`'lı migrasyon satırları
    /// önce byte-bütçeye 0 katkı verir (record-cap altında → tahliye yok); ilk okumadan SONRA
    /// gerçek boyutlarını kazanır → byte-cap doğru tetiklenir (RED: onarım olmadan okuma sonrası
    /// da 0 sayılır → tahliye 0).
    @Test func evictionByteBudgetCountsBackfilledRowsOnlyAfterRead() async throws {
        let cache = try makeConcreteStore()
        // 2 × 11 MB = 22 MB > 20 MB bütçe (kayıt sayısı 2 « 500).
        let chunk = Data(count: 11 * 1024 * 1024)
        try await cache.insertMigrationBackfilledSeries(
            id: SeriesID("s-old"),
            payload: chunk,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        try await cache.insertMigrationBackfilledSeries(
            id: SeriesID("s-new"),
            payload: chunk,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 200)
        )

        // Okuma ÖNCESİ: sizeBytes 0 → byte-bütçe 0 sayar → (record-cap da altında) tahliye yok.
        #expect(try await cache.evictCatalogCacheIfNeeded() == 0)
        #expect(try await cache.cachedSeries(id: SeriesID("s-old"), expectedSchemaVersion: 1) != nil)
        #expect(try await cache.cachedSeries(id: SeriesID("s-new"), expectedSchemaVersion: 1) != nil)

        // Okuma SONRASI: her satır gerçek boyutunu kazandı → 22 MB > 20 MB → 1 tahliye.
        // s-old daha erken okundu → en-eski-erişimli → o gider, s-new kalır.
        #expect(try await cache.evictCatalogCacheIfNeeded() == 1)
        #expect(try await cache.cachedSeries(id: SeriesID("s-old"), expectedSchemaVersion: 1) == nil)
        #expect(try await cache.cachedSeries(id: SeriesID("s-new"), expectedSchemaVersion: 1) != nil)
    }

    /// Guard: gerçekten boş payload'lı (0 boyut) bir kayıt okunduğunda `sizeBytes` yanlışlıkla
    /// değiştirilmemeli — 0 payload → 0 sizeBytes doğrudur, dokunma.
    @Test func emptyPayloadRowKeepsZeroSizeBytesOnRead() async throws {
        let cache = try makeConcreteStore()
        try await cache.insertMigrationBackfilledSeries(
            id: SeriesID("s-1"),
            payload: Data(),
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(try await cache.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1)?.payload == Data())
        #expect(try await cache.storedSeriesSizeBytes(id: SeriesID("s-1")) == 0)
    }
}
