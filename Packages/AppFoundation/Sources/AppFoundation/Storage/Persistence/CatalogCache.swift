import Foundation
import SwiftData

/// `CatalogCacheStore`'un SwiftData somut uygulaması (03 §9, 05 §3.1–§3.2). `@ModelActor`
/// ile arka plan context'ine hapsedilmiştir. `ContentKit` yalnız protokolü görür.
///
/// **Cache şema evrimi (05 §3.2 birebir):** okuma anında `payloadSchemaVersion` istemcinin
/// beklediğinden FARKLIYSA (eski VEYA yeni — dev/TestFlight downgrade dâhil) kayıt sessizce
/// silinir ve `nil` döner; migration YAZILMAZ. "Decode edilemiyorsa VEYA sürüm uyumsuzsa sil"
/// kuralının sürüm ayağıdır (bulgu #10).
///
/// **LRU tahliye (05 §3.2):** `CachedSeriesEntity` + `CachedEpisodeListEntity` toplamı
/// `PersistenceBudgets.catalogMaxRecords` / `catalogMaxBytes`'ı aşınca `lastAccessAt` en eski
/// olan önce silinir. `FeedSnapshotEntity` LRU'ya dahil değildir (tekil, `key` başına snapshot).
@ModelActor
actor CatalogCache: CatalogCacheStore {
    // MARK: - Series

    func cachedSeries(id: SeriesID, expectedSchemaVersion: Int) throws -> CachedPayload? {
        let target = id.rawValue
        var descriptor = FetchDescriptor<CachedSeriesEntity>(
            predicate: #Predicate { $0.seriesId == target }
        )
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        // Her sürüm uyumsuzluğunda sil (bulgu #10): eski VEYA yeni depolanan payload decode
        // edilemez → sessizce silinir, çağıran sunucudan tazeler.
        if entity.payloadSchemaVersion != expectedSchemaVersion {
            modelContext.delete(entity)
            try modelContext.save()
            return nil
        }
        // TODO: (WP-F1-G review, ertelendi) her okuma `lastAccessAt` için bir `save()` yapar
        // (LRU dokunuşu). Yüksek okuma hacminde bu yazmalar coalesce edilebilir (ör. dirty
        // damgalama + periyodik/uygulama-arka-plan flush). Ayrı optimizasyon kalemi.
        entity.lastAccessAt = Date()
        try modelContext.save()
        return CachedPayload(payload: entity.payload, etag: entity.etag, fetchedAt: entity.fetchedAt)
    }

    func storeSeries(id: SeriesID, payload: Data, schemaVersion: Int, etag: String?, fetchedAt: Date) throws {
        let target = id.rawValue
        var descriptor = FetchDescriptor<CachedSeriesEntity>(
            predicate: #Predicate { $0.seriesId == target }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.payload = payload
            existing.payloadSchemaVersion = schemaVersion
            existing.etag = etag
            existing.fetchedAt = fetchedAt
            existing.lastAccessAt = fetchedAt
        } else {
            modelContext.insert(CachedSeriesEntity(
                seriesId: target,
                payload: payload,
                payloadSchemaVersion: schemaVersion,
                etag: etag,
                fetchedAt: fetchedAt,
                lastAccessAt: fetchedAt
            ))
        }
        try modelContext.save()
    }

    // MARK: - Episode list

    func cachedEpisodeList(seriesID: SeriesID, expectedSchemaVersion: Int) throws -> CachedPayload? {
        let target = seriesID.rawValue
        var descriptor = FetchDescriptor<CachedEpisodeListEntity>(
            predicate: #Predicate { $0.seriesId == target }
        )
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        if entity.payloadSchemaVersion != expectedSchemaVersion {
            modelContext.delete(entity)
            try modelContext.save()
            return nil
        }
        entity.lastAccessAt = Date()
        try modelContext.save()
        return CachedPayload(payload: entity.payload, etag: entity.etag, fetchedAt: entity.fetchedAt)
    }

    func storeEpisodeList(seriesID: SeriesID, payload: Data, schemaVersion: Int, etag: String?, fetchedAt: Date) throws {
        let target = seriesID.rawValue
        var descriptor = FetchDescriptor<CachedEpisodeListEntity>(
            predicate: #Predicate { $0.seriesId == target }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.payload = payload
            existing.payloadSchemaVersion = schemaVersion
            existing.etag = etag
            existing.fetchedAt = fetchedAt
            existing.lastAccessAt = fetchedAt
        } else {
            modelContext.insert(CachedEpisodeListEntity(
                seriesId: target,
                payload: payload,
                payloadSchemaVersion: schemaVersion,
                etag: etag,
                fetchedAt: fetchedAt,
                lastAccessAt: fetchedAt
            ))
        }
        try modelContext.save()
    }

    // MARK: - Feed snapshot

    func cachedFeedSnapshot(key: String, expectedSchemaVersion: Int) throws -> CachedPayload? {
        var descriptor = FetchDescriptor<FeedSnapshotEntity>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        guard let entity = try modelContext.fetch(descriptor).first else { return nil }
        if entity.payloadSchemaVersion != expectedSchemaVersion {
            modelContext.delete(entity)
            try modelContext.save()
            return nil
        }
        return CachedPayload(payload: entity.payload, etag: nil, fetchedAt: entity.fetchedAt)
    }

    func storeFeedSnapshot(key: String, payload: Data, schemaVersion: Int, fetchedAt: Date) throws {
        var descriptor = FetchDescriptor<FeedSnapshotEntity>(
            predicate: #Predicate { $0.key == key }
        )
        descriptor.fetchLimit = 1
        if let existing = try modelContext.fetch(descriptor).first {
            existing.payload = payload
            existing.payloadSchemaVersion = schemaVersion
            existing.fetchedAt = fetchedAt
        } else {
            modelContext.insert(FeedSnapshotEntity(
                key: key,
                payload: payload,
                payloadSchemaVersion: schemaVersion,
                fetchedAt: fetchedAt
            ))
        }
        try modelContext.save()
    }

    // MARK: - LRU tahliye

    /// Series ve EpisodeList kayıtlarını tek LRU sırasında değerlendirmek için ortak görünüm.
    private enum CatalogCandidate {
        case series(CachedSeriesEntity)
        case episodeList(CachedEpisodeListEntity)

        var lastAccessAt: Date {
            switch self {
            case let .series(entity): entity.lastAccessAt
            case let .episodeList(entity): entity.lastAccessAt
            }
        }

        var bytes: Int {
            switch self {
            case let .series(entity): entity.payload.count
            case let .episodeList(entity): entity.payload.count
            }
        }
    }

    @discardableResult
    func evictCatalogCacheIfNeeded() throws -> Int {
        // TODO: (WP-F1-G review, ertelendi) tahliye bütçe hesabı için TÜM `payload` blob'larını
        // belleğe çeker (`entity.payload.count`). Entity'ye ayrı `sizeBytes` kolonu ekleyip yalnız
        // onu fetch etmek blob okumasını ortadan kaldırır — ancak yeni kolon migration gerektirir,
        // bu yüzden ayrı iş kalemi.
        let seriesEntities = try modelContext.fetch(FetchDescriptor<CachedSeriesEntity>())
        let listEntities = try modelContext.fetch(FetchDescriptor<CachedEpisodeListEntity>())

        var candidates = seriesEntities.map(CatalogCandidate.series)
            + listEntities.map(CatalogCandidate.episodeList)

        var remainingRecords = candidates.count
        var remainingBytes = candidates.reduce(Int64(0)) { $0 + Int64($1.bytes) }

        func overBudget() -> Bool {
            remainingRecords > PersistenceBudgets.catalogMaxRecords || remainingBytes > PersistenceBudgets.catalogMaxBytes
        }
        guard overBudget() else { return 0 }

        // En eski erişimli önce (LRU).
        candidates.sort { $0.lastAccessAt < $1.lastAccessAt }

        var deleted = 0
        for candidate in candidates {
            guard overBudget() else { break }
            switch candidate {
            case let .series(entity): modelContext.delete(entity)
            case let .episodeList(entity): modelContext.delete(entity)
            }
            remainingRecords -= 1
            remainingBytes -= Int64(candidate.bytes)
            deleted += 1
        }
        if deleted > 0 {
            try modelContext.save()
        }
        return deleted
    }
}
