import Foundation
import SwiftData

/// `AssetCacheIndexing`'in (mevcut protokol — 03 §9, 04 §7.2) SwiftData somut uygulaması;
/// ~200 MB video cache LRU defterinin (`CachedAssetRecordEntity`) sahibidir. `PlayerKit`
/// yalnız protokolü görür.
///
/// **Köprüleme:** Protokol kimliği `CachedAssetRecord.url`'dür; entity'nin benzersiz anahtarı
/// `episodeId`'dir (05 §3.2 birebir). `url.absoluteString` benzersiz anahtar olarak saklanır;
/// böylece hem uzak (https) hem yerel (file) URL'ler kayıpsız round-trip eder. Protokol
/// `watchCompleted` alanını taşımadığından yeni kayıtlar `false` ile açılır (eviction
/// önceliklendirmesi, kararı yürüten `PlayerKit.EpisodeCacheStore`'a bırakılır — 05 §3.2).
///
/// TODO: SS-043 — `url.absoluteString`'i `episodeId` benzersiz anahtarı olarak kullanmak
/// semantik bir kötüye kullanımdır (URL ≠ bölüm kimliği); ayrı `assetURL`/`episodeId` alanları
/// için protokol + entity yeniden tasarımı gerekir (WP-F1-G review'da ertelendi: entity redesign
/// + migration kapsamı SS-043).
@ModelActor
actor AssetCacheIndex: AssetCacheIndexing {
    func record(for url: URL) throws -> CachedAssetRecord? {
        try fetchEntity(key: url.absoluteString).map(Self.record)
    }

    func upsert(_ record: CachedAssetRecord) throws {
        let key = record.url.absoluteString
        let localPath = record.url.isFileURL ? record.url.path : key
        if let existing = try fetchEntity(key: key) {
            existing.localAssetPath = localPath
            existing.sizeBytes = record.sizeInBytes
            existing.lastAccessAt = record.lastAccessAt
        } else {
            modelContext.insert(CachedAssetRecordEntity(
                episodeId: key,
                localAssetPath: localPath,
                sizeBytes: record.sizeInBytes,
                lastAccessAt: record.lastAccessAt,
                watchCompleted: false
            ))
        }
        try modelContext.save()
    }

    func markAccessed(_ url: URL, at date: Date) throws {
        guard let existing = try fetchEntity(key: url.absoluteString) else { return }
        existing.lastAccessAt = date
        try modelContext.save()
    }

    func remove(_ url: URL) throws {
        guard let existing = try fetchEntity(key: url.absoluteString) else { return }
        modelContext.delete(existing)
        try modelContext.save()
    }

    func totalSizeInBytes() throws -> Int64 {
        let entities = try modelContext.fetch(FetchDescriptor<CachedAssetRecordEntity>())
        return entities.reduce(Int64(0)) { $0 + $1.sizeBytes }
    }

    func evictionCandidates(toFree bytes: Int64) throws -> [CachedAssetRecord] {
        guard bytes > 0 else { return [] }
        let descriptor = FetchDescriptor<CachedAssetRecordEntity>(
            sortBy: [SortDescriptor(\.lastAccessAt, order: .forward)]
        )
        var freed: Int64 = 0
        var result: [CachedAssetRecord] = []
        for entity in try modelContext.fetch(descriptor) {
            if freed >= bytes {
                break
            }
            result.append(Self.record(from: entity))
            freed += entity.sizeBytes
        }
        return result
    }

    // MARK: - Yardımcılar

    private func fetchEntity(key: String) throws -> CachedAssetRecordEntity? {
        var descriptor = FetchDescriptor<CachedAssetRecordEntity>(
            predicate: #Predicate { $0.episodeId == key }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func record(from entity: CachedAssetRecordEntity) -> CachedAssetRecord {
        let url = URL(string: entity.episodeId) ?? URL(fileURLWithPath: entity.localAssetPath)
        return CachedAssetRecord(url: url, sizeInBytes: entity.sizeBytes, lastAccessAt: entity.lastAccessAt)
    }
}
