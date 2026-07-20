import Foundation
import Testing
@testable import AppFoundation

struct CatalogCacheStoreTests {
    private func makeStore() throws -> any CatalogCacheStore {
        try PersistenceStore(inMemory: true).makeCatalogCacheStore()
    }

    @Test func storeThenReadSeries() async throws {
        let store = try makeStore()
        let payload = Data("series-json".utf8)
        try await store.storeSeries(
            id: SeriesID("s-1"),
            payload: payload,
            schemaVersion: 1,
            etag: "abc",
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        let read = try await store.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1)
        #expect(read?.payload == payload)
        #expect(read?.etag == "abc")
        #expect(read?.fetchedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func missingSeriesReturnsNil() async throws {
        let store = try makeStore()
        let read = try await store.cachedSeries(id: SeriesID("nope"), expectedSchemaVersion: 1)
        #expect(read == nil)
    }

    @Test func staleSchemaVersionSilentlyDeletesAndReturnsNil() async throws {
        let store = try makeStore()
        try await store.storeSeries(
            id: SeriesID("s-1"),
            payload: Data("old".utf8),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )

        // İstemci artık v2 bekliyor → eski kayıt sessizce silinir.
        let firstRead = try await store.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 2)
        #expect(firstRead == nil)

        // Kayıt fiilen silinmiş olmalı: aynı sürümle tekrar okumada da yok.
        let secondRead = try await store.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1)
        #expect(secondRead == nil)
    }

    /// WP-F1-G bulgu #10: şema sürümü SADECE eskiyken değil, HER uyumsuzlukta silinmeli
    /// (05 §3.2: "decode edilemiyorsa VEYA sürüm uyumsuzsa sil"). Depolanan sürüm beklenenden
    /// YENİYSE (dev/TestFlight downgrade) payload olduğu gibi dönerse decode patlar → sessizce
    /// sil + `nil` dön.
    @Test func newerStoredSeriesSchemaIsDeletedOnMismatch() async throws {
        let store = try makeStore()
        try await store.storeSeries(
            id: SeriesID("s-1"),
            payload: Data("v2".utf8),
            schemaVersion: 2,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        // İstemci v1 bekliyor (downgrade) → uyumsuz → sessizce silinir.
        #expect(try await store.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1) == nil)
        // Fiilen silinmiş olmalı: depolanan v2 ile tekrar okumada da yok.
        #expect(try await store.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 2) == nil)
    }

    @Test func newerStoredEpisodeListSchemaIsDeletedOnMismatch() async throws {
        let store = try makeStore()
        try await store.storeEpisodeList(
            seriesID: SeriesID("s-1"),
            payload: Data("v4".utf8),
            schemaVersion: 4,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(try await store.cachedEpisodeList(seriesID: SeriesID("s-1"), expectedSchemaVersion: 3) == nil)
        #expect(try await store.cachedEpisodeList(seriesID: SeriesID("s-1"), expectedSchemaVersion: 4) == nil)
    }

    @Test func newerStoredFeedSnapshotSchemaIsDeletedOnMismatch() async throws {
        let store = try makeStore()
        try await store.storeFeedSnapshot(
            key: "forYou",
            payload: Data("v9".utf8),
            schemaVersion: 9,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(try await store.cachedFeedSnapshot(key: "forYou", expectedSchemaVersion: 5) == nil)
        #expect(try await store.cachedFeedSnapshot(key: "forYou", expectedSchemaVersion: 9) == nil)
    }

    @Test func storeThenReadEpisodeList() async throws {
        let store = try makeStore()
        let payload = Data("episodes".utf8)
        try await store.storeEpisodeList(
            seriesID: SeriesID("s-1"),
            payload: payload,
            schemaVersion: 3,
            etag: "e1",
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        let read = try await store.cachedEpisodeList(seriesID: SeriesID("s-1"), expectedSchemaVersion: 3)
        #expect(read?.payload == payload)
    }

    @Test func storeThenReadFeedSnapshot() async throws {
        let store = try makeStore()
        let payload = Data("feed".utf8)
        try await store.storeFeedSnapshot(
            key: "forYou",
            payload: payload,
            schemaVersion: 1,
            fetchedAt: Date(timeIntervalSince1970: 300)
        )
        let read = try await store.cachedFeedSnapshot(key: "forYou", expectedSchemaVersion: 1)
        #expect(read?.payload == payload)

        let stale = try await store.cachedFeedSnapshot(key: "forYou", expectedSchemaVersion: 5)
        #expect(stale == nil)
    }

    @Test func evictionRemovesLeastRecentlyAccessedWhenOverByteBudget() async throws {
        let store = try makeStore()
        // 8 MB × 3 = 24 MB > 20 MB bütçe → en eski erişimli 1 kayıt tahliye edilir.
        let big = Data(count: 8 * 1024 * 1024)
        try await store.storeSeries(
            id: SeriesID("s-old"),
            payload: big,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.storeSeries(
            id: SeriesID("s-mid"),
            payload: big,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        try await store.storeSeries(
            id: SeriesID("s-new"),
            payload: big,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 300)
        )

        let deleted = try await store.evictCatalogCacheIfNeeded()
        #expect(deleted == 1)

        // En eski erişimli (s-old) gitmeli; diğerleri kalmalı.
        #expect(try await store.cachedSeries(id: SeriesID("s-old"), expectedSchemaVersion: 1) == nil)
        #expect(try await store.cachedSeries(id: SeriesID("s-mid"), expectedSchemaVersion: 1) != nil)
        #expect(try await store.cachedSeries(id: SeriesID("s-new"), expectedSchemaVersion: 1) != nil)
    }

    @Test func evictionIsNoopUnderBudget() async throws {
        let store = try makeStore()
        try await store.storeSeries(
            id: SeriesID("s-1"),
            payload: Data("tiny".utf8),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let deleted = try await store.evictCatalogCacheIfNeeded()
        #expect(deleted == 0)
        #expect(try await store.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1) != nil)
    }
}

/// WP-F1-G'de ERTELENEN iki CatalogCache optimizasyonunun (OPT-1 LRU dokunuşu coalesce,
/// OPT-2 blob'suz `sizeBytes` bütçesi) TDD kapsamı. Beyaz-kutu doğrulamalar için somut
/// `CatalogCache`'e iner (`persistedSaveCount`, `storedSeriesSizeBytes` gibi iç API'ler
/// protokol yüzeyinde yoktur).
struct CatalogCacheOptimizationTests {
    private func makeStore() throws -> any CatalogCacheStore {
        try PersistenceStore(inMemory: true).makeCatalogCacheStore()
    }

    private func makeConcreteStore() throws -> CatalogCache {
        let store = try PersistenceStore(inMemory: true).makeCatalogCacheStore()
        return try #require(store as? CatalogCache)
    }

    // MARK: - OPT-1: LRU dokunuşu coalesce (okuma disk-write YAPMAZ)

    /// OPT-1: şema-uyumlu okuma HER seferinde `save()` tetiklememeli (yazma amplifikasyonu yok).
    @Test func schemaMatchedReadDoesNotTriggerDiskSave() async throws {
        let cache = try makeConcreteStore()
        try await cache.storeSeries(
            id: SeriesID("s-1"),
            payload: Data("series".utf8),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let savesAfterStore = await cache.persistedSaveCount

        for _ in 0 ..< 5 {
            #expect(try await cache.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1) != nil)
        }
        // Beş okuma hiç save() yapmamalı.
        #expect(await cache.persistedSaveCount == savesAfterStore)

        // EpisodeList okuma yolu da aynı: save() yok.
        try await cache.storeEpisodeList(
            seriesID: SeriesID("s-1"),
            payload: Data("episodes".utf8),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let savesAfterListStore = await cache.persistedSaveCount
        for _ in 0 ..< 5 {
            #expect(try await cache.cachedEpisodeList(seriesID: SeriesID("s-1"), expectedSchemaVersion: 1) != nil)
        }
        #expect(await cache.persistedSaveCount == savesAfterListStore)
    }

    /// OPT-1: save() etmese de okuma LRU sırasını güncellemeli — okunan kayıt "en yeni erişimli"
    /// olur ve tahliyede korunur; onun yerine bir sonraki en-eski atılır.
    @Test func readUpdatesLRUOrderSoRecentlyReadSurvivesEviction() async throws {
        let store = try makeStore()
        let big = Data(count: 8 * 1024 * 1024) // 8 MB

        // s-a en eski erişimli (100), s-b (200). Toplam 16 MB < 20 MB → tahliye yok.
        try await store.storeSeries(
            id: SeriesID("s-a"),
            payload: big,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.storeSeries(
            id: SeriesID("s-b"),
            payload: big,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 200)
        )

        // s-a okunur → lastAccessAt ≈ şimdi (2020'lerden sonrası): artık EN YENİ erişimli.
        #expect(try await store.cachedSeries(id: SeriesID("s-a"), expectedSchemaVersion: 1) != nil)

        // Üçüncü kayıt → 24 MB > 20 MB → bir tahliye.
        try await store.storeSeries(
            id: SeriesID("s-c"),
            payload: big,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 300)
        )

        let deleted = try await store.evictCatalogCacheIfNeeded()
        #expect(deleted == 1)

        // En-eski-erişimli artık s-b (200); s-a okunduğu için korunur.
        #expect(try await store.cachedSeries(id: SeriesID("s-b"), expectedSchemaVersion: 1) == nil)
        #expect(try await store.cachedSeries(id: SeriesID("s-a"), expectedSchemaVersion: 1) != nil)
        #expect(try await store.cachedSeries(id: SeriesID("s-c"), expectedSchemaVersion: 1) != nil)
    }

    /// OPT-1: bütçe altında bile eviction, okuma yolundan biriken dirty LRU damgalarını tek
    /// save()'te diske coalesce etmeli (silme yok → `deleted == 0`, ama bir save gerçekleşir).
    @Test func evictionCoalescesPendingAccessStampsWhenUnderBudget() async throws {
        let cache = try makeConcreteStore()
        try await cache.storeSeries(
            id: SeriesID("s-1"),
            payload: Data("tiny".utf8),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let base = await cache.persistedSaveCount

        // Okuma dirty damga bırakır ama save() yapmaz.
        #expect(try await cache.cachedSeries(id: SeriesID("s-1"), expectedSchemaVersion: 1) != nil)
        #expect(await cache.persistedSaveCount == base)

        // Bütçe altında eviction: silme yok ama dirty damga tek save()'te diske yazılır.
        #expect(try await cache.evictCatalogCacheIfNeeded() == 0)
        #expect(await cache.persistedSaveCount == base + 1)

        // İkinci kez eviction: artık dirty yok → yeni save() yok (idempotent, gereksiz yazma yok).
        #expect(try await cache.evictCatalogCacheIfNeeded() == 0)
        #expect(await cache.persistedSaveCount == base + 1)
    }

    // MARK: - OPT-2: blob'suz tahliye bütçesi (sizeBytes kolonu)

    /// OPT-2: `store` `sizeBytes`'ı `payload.count`'tan yazar; re-store yeni boyutla tazeler.
    @Test func storeWritesSizeBytesFromPayloadCount() async throws {
        let cache = try makeConcreteStore()

        try await cache.storeSeries(
            id: SeriesID("s-1"),
            payload: Data(count: 1234),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(try await cache.storedSeriesSizeBytes(id: SeriesID("s-1")) == 1234)

        // Aynı id'yi daha büyük payload'la re-store → sizeBytes tazelenir.
        try await cache.storeSeries(
            id: SeriesID("s-1"),
            payload: Data(count: 4096),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(try await cache.storedSeriesSizeBytes(id: SeriesID("s-1")) == 4096)

        try await cache.storeEpisodeList(
            seriesID: SeriesID("s-1"),
            payload: Data(count: 5678),
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(try await cache.storedEpisodeListSizeBytes(seriesID: SeriesID("s-1")) == 5678)
    }

    /// OPT-2: tahliye bütçesi `sizeBytes` toplamından hesaplanır — bütçe (20 MB) yalnız byte
    /// aşımıyla (kayıt sayısı değil) tetiklenir ve gerektiği kadar en-eski kaydı atar.
    @Test func evictionByteBudgetComputedFromSizeBytes() async throws {
        let store = try makeStore()
        // 2 × 11 MB = 22 MB > 20 MB (kayıt sayısı 2 « 500) → yalnız byte-aşımı → 1 tahliye.
        let chunk = Data(count: 11 * 1024 * 1024)
        try await store.storeSeries(
            id: SeriesID("s-old"),
            payload: chunk,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        try await store.storeSeries(
            id: SeriesID("s-new"),
            payload: chunk,
            schemaVersion: 1,
            etag: nil,
            fetchedAt: Date(timeIntervalSince1970: 200)
        )

        #expect(try await store.evictCatalogCacheIfNeeded() == 1)
        #expect(try await store.cachedSeries(id: SeriesID("s-old"), expectedSchemaVersion: 1) == nil)
        #expect(try await store.cachedSeries(id: SeriesID("s-new"), expectedSchemaVersion: 1) != nil)
    }
}
