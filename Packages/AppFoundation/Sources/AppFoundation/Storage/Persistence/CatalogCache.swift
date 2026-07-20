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
///
/// **LRU dokunuşu coalesce (WP-F1-G OPT-1):** okuma yolu `lastAccessAt`'i yalnız *bellek-içi*
/// günceller (dirty damga) ve `save()` ETMEZ — yazma amplifikasyonunu önler. Damga, bir sonraki
/// `save()`'te (store veya eviction) diske coalesce edilir; tahliye sıralaması bellekteki güncel
/// `lastAccessAt`'i gördüğünden en-eski-erişimliyi doğru seçer. Uçuşta kaybolan damgalar cache
/// için tolere edilir (yalnız LRU sırasını hafifçe bayatlatır, veri kaybı değil).
///
/// **Blob'suz tahliye bütçesi (WP-F1-G OPT-2):** eviction bütçeyi `sizeBytes` kolonundan
/// hesaplar ve `propertiesToFetch` ile `payload` blob'larını belleğe ÇEKMEZ.
@ModelActor
actor CatalogCache: CatalogCacheStore {
    /// Diske yapılan `save()` sayısı (OPT-1 tanısı/testi: okuma yolu bunu ARTIRMAMALI).
    private(set) var persistedSaveCount = 0

    /// `modelContext.save()` sarmalayıcısı — coalesce edilmiş yazma sayımını tek noktada tutar.
    private func persist() throws {
        try modelContext.save()
        persistedSaveCount += 1
    }

    /// OPT-2 LOW migrasyon back-fill onarımı (write-on-read YOK): `sizeBytes == 0` ama payload
    /// dolu ise (lightweight migration back-fill) `assign`'i gerçek `payload.count` ile çağırır.
    /// Yalnız bellek-içi damgalar; disk `save()` OPT-1 dirty-stamp'iyle bir sonraki save()'e
    /// coalesce olur. `payload` gerçekten boşsa (0 boyut) dokunmaz.
    private func backfillSizeBytesIfNeeded(sizeBytes: Int, payload: Data, assign: (Int) -> Void) {
        guard sizeBytes == 0, !payload.isEmpty else { return }
        assign(payload.count)
    }

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
            try persist()
            return nil
        }
        // OPT-2 LOW (migrasyon back-fill onarımı): lightweight migration eski satırlara
        // `sizeBytes = 0` yazar → tahliye byte-bütçesine 0 katkı verir (byte-cap o satırlar
        // re-store edilene dek eksik sayar). İlk şema-uyumlu okumada gerçek boyutu geri yaz.
        // Bu yazma OPT-1 dirty-stamp'iyle birleşir (okuma başına ayrı disk save() YOK — bir
        // sonraki save()'e `lastAccessAt` ile coalesce). Payload gerçekten boşsa dokunma.
        backfillSizeBytesIfNeeded(sizeBytes: entity.sizeBytes, payload: entity.payload) {
            entity.sizeBytes = $0
        }
        // OPT-1: LRU dokunuşu yalnız bellek-içi (dirty damga); save() YOK. Bir sonraki
        // store/eviction save()'inde diske coalesce edilir.
        entity.lastAccessAt = Date()
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
            existing.sizeBytes = payload.count
        } else {
            modelContext.insert(CachedSeriesEntity(
                seriesId: target,
                payload: payload,
                payloadSchemaVersion: schemaVersion,
                etag: etag,
                fetchedAt: fetchedAt,
                lastAccessAt: fetchedAt,
                sizeBytes: payload.count
            ))
        }
        try persist()
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
            try persist()
            return nil
        }
        // OPT-2 LOW: bkz. cachedSeries — migrasyon back-fill onarımı, OPT-1 dirty-stamp'e coalesce.
        backfillSizeBytesIfNeeded(sizeBytes: entity.sizeBytes, payload: entity.payload) {
            entity.sizeBytes = $0
        }
        // OPT-1: bkz. cachedSeries — bellek-içi dirty damga, save() yok.
        entity.lastAccessAt = Date()
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
            existing.sizeBytes = payload.count
        } else {
            modelContext.insert(CachedEpisodeListEntity(
                seriesId: target,
                payload: payload,
                payloadSchemaVersion: schemaVersion,
                etag: etag,
                fetchedAt: fetchedAt,
                lastAccessAt: fetchedAt,
                sizeBytes: payload.count
            ))
        }
        try persist()
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
            try persist()
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
        try persist()
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

        /// OPT-2: bütçe `payload.count` yerine `sizeBytes` kolonundan okunur — blob yüklenmez.
        var sizeBytes: Int {
            switch self {
            case let .series(entity): entity.sizeBytes
            case let .episodeList(entity): entity.sizeBytes
            }
        }
    }

    @discardableResult
    func evictCatalogCacheIfNeeded() throws -> Int {
        // OPT-2: yalnız LRU/bütçe metadata'sı çekilir (`seriesId`, `lastAccessAt`, `sizeBytes`);
        // `payload` blob'ları `propertiesToFetch` ile YÜKLENMEZ. `.delete(entity)` de payload'a
        // dokunmaz, dolayısıyla tüm tahliye yolu blob-okumasızdır.
        var seriesDescriptor = FetchDescriptor<CachedSeriesEntity>()
        seriesDescriptor.propertiesToFetch = [\.seriesId, \.lastAccessAt, \.sizeBytes]
        let seriesEntities = try modelContext.fetch(seriesDescriptor)

        var listDescriptor = FetchDescriptor<CachedEpisodeListEntity>()
        listDescriptor.propertiesToFetch = [\.seriesId, \.lastAccessAt, \.sizeBytes]
        let listEntities = try modelContext.fetch(listDescriptor)

        var candidates = seriesEntities.map(CatalogCandidate.series)
            + listEntities.map(CatalogCandidate.episodeList)

        var remainingRecords = candidates.count
        var remainingBytes = candidates.reduce(Int64(0)) { $0 + Int64($1.sizeBytes) }

        func overBudget() -> Bool {
            remainingRecords > PersistenceBudgets.catalogMaxRecords || remainingBytes > PersistenceBudgets.catalogMaxBytes
        }
        guard overBudget() else {
            // OPT-1: bütçe aşımı yok ama okuma yolundan biriken LRU damgaları dirty olabilir →
            // burada tek save()'te diske coalesce et (silme yok, `deleted == 0`).
            if modelContext.hasChanges {
                try persist()
            }
            return 0
        }

        // En eski erişimli önce (LRU) — bellek-içi güncel `lastAccessAt` (OPT-1 damgası dâhil).
        candidates.sort { $0.lastAccessAt < $1.lastAccessAt }

        var deleted = 0
        for candidate in candidates {
            guard overBudget() else { break }
            switch candidate {
            case let .series(entity): modelContext.delete(entity)
            case let .episodeList(entity): modelContext.delete(entity)
            }
            remainingRecords -= 1
            remainingBytes -= Int64(candidate.sizeBytes)
            deleted += 1
        }
        // Silmeler + coalesce edilmiş LRU damgaları tek save()'te diske yazılır.
        try persist()
        return deleted
    }

    // MARK: - Tanı erişimi (test/diagnostik)

    /// Bir series kaydının blob'suz `sizeBytes` kolonunu döndürür (OPT-2 doğrulaması). `payload`
    /// `propertiesToFetch` ile fault bırakılır — bütçe hesabının blob yüklemediğini de örnekler.
    func storedSeriesSizeBytes(id: SeriesID) throws -> Int? {
        let target = id.rawValue
        var descriptor = FetchDescriptor<CachedSeriesEntity>(
            predicate: #Predicate { $0.seriesId == target }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.sizeBytes]
        return try modelContext.fetch(descriptor).first?.sizeBytes
    }

    /// Bir episode-list kaydının blob'suz `sizeBytes` kolonu (OPT-2 doğrulaması).
    func storedEpisodeListSizeBytes(seriesID: SeriesID) throws -> Int? {
        let target = seriesID.rawValue
        var descriptor = FetchDescriptor<CachedEpisodeListEntity>(
            predicate: #Predicate { $0.seriesId == target }
        )
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.sizeBytes]
        return try modelContext.fetch(descriptor).first?.sizeBytes
    }

    /// Test/diagnostik (OPT-2 LOW back-fill onarımı): OPT-2 `sizeBytes` kolonu EKLENMEDEN önce
    /// yazılmış, lightweight migration ile `sizeBytes = 0` back-fill edilmiş bir series satırını
    /// simüle eder. `store*` KULLANMAZ — çünkü store doğru `payload.count`'ı yazardı; buradaki
    /// amaç payload dolu ama `sizeBytes == 0` olan migrasyon durumunu ham insert ile kurmaktır.
    func insertMigrationBackfilledSeries(id: SeriesID, payload: Data, schemaVersion: Int, fetchedAt: Date) throws {
        modelContext.insert(CachedSeriesEntity(
            seriesId: id.rawValue,
            payload: payload,
            payloadSchemaVersion: schemaVersion,
            etag: nil,
            fetchedAt: fetchedAt,
            lastAccessAt: fetchedAt,
            sizeBytes: 0
        ))
        try persist()
    }

    /// Test/diagnostik: `insertMigrationBackfilledSeries`'in episode-list eşdeğeri.
    func insertMigrationBackfilledEpisodeList(seriesID: SeriesID, payload: Data, schemaVersion: Int, fetchedAt: Date) throws {
        modelContext.insert(CachedEpisodeListEntity(
            seriesId: seriesID.rawValue,
            payload: payload,
            payloadSchemaVersion: schemaVersion,
            etag: nil,
            fetchedAt: fetchedAt,
            lastAccessAt: fetchedAt,
            sizeBytes: 0
        ))
        try persist()
    }
}
