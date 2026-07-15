import Foundation
import Testing
@testable import AppFoundation

struct AssetCacheIndexTests {
    private func makeIndex() throws -> any AssetCacheIndexing {
        try PersistenceStore(inMemory: true).makeAssetCacheIndex()
    }

    private func url(_ name: String) -> URL {
        URL(string: "https://cdn.shortseries.app/\(name).movpkg")!
    }

    @Test func upsertThenReadRoundTrips() async throws {
        let index = try makeIndex()
        let rec = CachedAssetRecord(url: url("a"), sizeInBytes: 123, lastAccessAt: Date(timeIntervalSince1970: 10))
        try await index.upsert(rec)

        let read = try await index.record(for: url("a"))
        #expect(read?.url == url("a"))
        #expect(read?.sizeInBytes == 123)
        #expect(read?.lastAccessAt == Date(timeIntervalSince1970: 10))
    }

    @Test func upsertReplacesExisting() async throws {
        let index = try makeIndex()
        try await index.upsert(CachedAssetRecord(url: url("a"), sizeInBytes: 100, lastAccessAt: Date(timeIntervalSince1970: 10)))
        try await index.upsert(CachedAssetRecord(url: url("a"), sizeInBytes: 999, lastAccessAt: Date(timeIntervalSince1970: 20)))

        let read = try await index.record(for: url("a"))
        #expect(read?.sizeInBytes == 999)
        #expect(try await index.totalSizeInBytes() == 999)
    }

    @Test func totalSizeSumsRecords() async throws {
        let index = try makeIndex()
        try await index.upsert(CachedAssetRecord(url: url("a"), sizeInBytes: 100, lastAccessAt: Date(timeIntervalSince1970: 10)))
        try await index.upsert(CachedAssetRecord(url: url("b"), sizeInBytes: 200, lastAccessAt: Date(timeIntervalSince1970: 20)))
        try await index.upsert(CachedAssetRecord(url: url("c"), sizeInBytes: 300, lastAccessAt: Date(timeIntervalSince1970: 30)))
        #expect(try await index.totalSizeInBytes() == 600)
    }

    @Test func removeDeletesRecord() async throws {
        let index = try makeIndex()
        try await index.upsert(CachedAssetRecord(url: url("a"), sizeInBytes: 100, lastAccessAt: Date(timeIntervalSince1970: 10)))
        try await index.upsert(CachedAssetRecord(url: url("b"), sizeInBytes: 200, lastAccessAt: Date(timeIntervalSince1970: 20)))
        try await index.remove(url("a"))

        #expect(try await index.record(for: url("a")) == nil)
        #expect(try await index.totalSizeInBytes() == 200)
    }

    @Test func markAccessedUpdatesLRUOrdering() async throws {
        let index = try makeIndex()
        try await index.upsert(CachedAssetRecord(url: url("a"), sizeInBytes: 100, lastAccessAt: Date(timeIntervalSince1970: 10)))
        try await index.upsert(CachedAssetRecord(url: url("b"), sizeInBytes: 200, lastAccessAt: Date(timeIntervalSince1970: 20)))
        try await index.upsert(CachedAssetRecord(url: url("c"), sizeInBytes: 300, lastAccessAt: Date(timeIntervalSince1970: 30)))

        // A'ya en yeni erişim damgasını ver → LRU sırası: b, c, a
        try await index.markAccessed(url("a"), at: Date(timeIntervalSince1970: 99))

        let candidates = try await index.evictionCandidates(toFree: 250)
        // b(200) < 250 → c ekle; 200+300 = 500 >= 250 → dur.
        #expect(candidates.map(\.url) == [url("b"), url("c")])
    }

    @Test func evictionCandidatesFollowLRUOrder() async throws {
        let index = try makeIndex()
        try await index.upsert(CachedAssetRecord(url: url("a"), sizeInBytes: 100, lastAccessAt: Date(timeIntervalSince1970: 30)))
        try await index.upsert(CachedAssetRecord(url: url("b"), sizeInBytes: 200, lastAccessAt: Date(timeIntervalSince1970: 10)))
        try await index.upsert(CachedAssetRecord(url: url("c"), sizeInBytes: 300, lastAccessAt: Date(timeIntervalSince1970: 20)))

        // LRU (en eski erişim önce): b(10), c(20), a(30)
        let candidates = try await index.evictionCandidates(toFree: 150)
        // b(200) >= 150 → tek aday.
        #expect(candidates.map(\.url) == [url("b")])
    }

    @Test func evictionCandidatesReturnAllWhenBudgetExceedsTotal() async throws {
        let index = try makeIndex()
        try await index.upsert(CachedAssetRecord(url: url("a"), sizeInBytes: 100, lastAccessAt: Date(timeIntervalSince1970: 10)))
        try await index.upsert(CachedAssetRecord(url: url("b"), sizeInBytes: 200, lastAccessAt: Date(timeIntervalSince1970: 20)))

        let candidates = try await index.evictionCandidates(toFree: 10000)
        #expect(Set(candidates.map(\.url)) == [url("a"), url("b")])
    }

    @Test func missingRecordReturnsNil() async throws {
        let index = try makeIndex()
        #expect(try await index.record(for: url("ghost")) == nil)
    }
}
