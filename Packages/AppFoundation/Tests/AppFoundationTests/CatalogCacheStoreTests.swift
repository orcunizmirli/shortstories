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
