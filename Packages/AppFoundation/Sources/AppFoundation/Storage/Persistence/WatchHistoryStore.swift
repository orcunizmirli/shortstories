import Foundation
import SwiftData

/// `WatchHistoryRepository`'nin SwiftData somut uygulaması (03 §9). `@ModelActor` ile
/// yazma/okuma arka plan context'inde, actor'a hapsedilmiş yürütülür (03 §7.3).
/// Feature modülleri bu tipi GÖRMEZ; yalnız `WatchHistoryRepository` protokolünü görür.
@ModelActor
actor WatchHistoryStore: WatchHistoryRepository {
    /// 0 = synced, 1 = pendingUpload (05 §3.2 `WatchProgressEntity.syncState`).
    private enum SyncState {
        static let synced = 0
        static let pendingUpload = 1
    }

    // MARK: - Yazma

    func saveProgress(_ progress: WatchProgressRecord) throws {
        let existing = try fetchEntity(episodeId: progress.episodeID.rawValue)
        // Last-write-wins (05 §3.3): mevcut kayıt daha yeniyse yazma yok sayılır.
        if let existing, existing.watchedAt > progress.watchedAt {
            return
        }
        upsert(progress, into: existing, syncState: SyncState.pendingUpload)
        try modelContext.save()
    }

    func mergeServerProgress(_ records: [WatchProgressRecord]) throws {
        for record in records {
            let existing = try fetchEntity(episodeId: record.episodeID.rawValue)
            // Yerel pendingUpload kaydı daha yeniyse korunur (senkron ONE-WAY yazması ezmez).
            if let existing, Self.isNewerLocalPending(existing, than: record) {
                continue
            }
            upsert(record, into: existing, syncState: SyncState.synced)
        }
        try modelContext.save()
    }

    func markSynced(uploaded records: [WatchProgressRecord]) throws {
        guard !records.isEmpty else { return }
        for record in records {
            guard let entity = try fetchEntity(episodeId: record.episodeID.rawValue) else { continue }
            // Simetrik last-write-wins guard (05 §3.3): yüklenen anlık görüntü uçarken araya
            // giren reentrant yazma `watchedAt`'i ilerlettiyse (entity daha yeni), bu kaydı
            // synced YAPMA — henüz sunucuya gitmemiş yazma pendingUpload kalır, sonraki tur yükler.
            if entity.watchedAt > record.watchedAt {
                continue
            }
            entity.syncState = SyncState.synced
        }
        try modelContext.save()
    }

    // MARK: - Okuma

    func progress(forEpisode episodeID: EpisodeID) throws -> WatchProgressRecord? {
        try fetchEntity(episodeId: episodeID.rawValue).map(Self.record)
    }

    func progress(forSeries seriesID: SeriesID) throws -> [WatchProgressRecord] {
        let target = seriesID.rawValue
        let descriptor = FetchDescriptor<WatchProgressEntity>(
            predicate: #Predicate { $0.seriesId == target }
        )
        return try modelContext.fetch(descriptor).map(Self.record)
    }

    func latestProgress(forSeries seriesID: SeriesID) throws -> WatchProgressRecord? {
        let target = seriesID.rawValue
        // Hedefli sorgu (bulgu #11): store en yeni tek kaydı döndürür — tüm dizi kayıtları
        // belleğe çekilip `.max` edilmez.
        var descriptor = FetchDescriptor<WatchProgressEntity>(
            predicate: #Predicate { $0.seriesId == target },
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first.map(Self.record)
    }

    func continueWatching(limit: Int) throws -> [WatchProgressRecord] {
        var descriptor = FetchDescriptor<WatchProgressEntity>(
            predicate: #Predicate { $0.completed == false },
            sortBy: [SortDescriptor(\.watchedAt, order: .reverse)]
        )
        if limit > 0 {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor).map(Self.record)
    }

    func pendingUploads() throws -> [WatchProgressRecord] {
        let pending = SyncState.pendingUpload
        let descriptor = FetchDescriptor<WatchProgressEntity>(
            predicate: #Predicate { $0.syncState == pending }
        )
        return try modelContext.fetch(descriptor).map(Self.record)
    }

    // MARK: - Yardımcılar

    private func fetchEntity(episodeId: String) throws -> WatchProgressEntity? {
        var descriptor = FetchDescriptor<WatchProgressEntity>(
            predicate: #Predicate { $0.episodeId == episodeId }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func upsert(_ record: WatchProgressRecord, into existing: WatchProgressEntity?, syncState: Int) {
        if let existing {
            existing.seriesId = record.seriesID.rawValue
            existing.positionSec = record.positionSec
            existing.durationSec = record.durationSec
            existing.completed = record.completed
            existing.watchedAt = record.watchedAt
            existing.syncState = syncState
        } else {
            modelContext.insert(WatchProgressEntity(
                episodeId: record.episodeID.rawValue,
                seriesId: record.seriesID.rawValue,
                positionSec: record.positionSec,
                durationSec: record.durationSec,
                completed: record.completed,
                watchedAt: record.watchedAt,
                syncState: syncState
            ))
        }
    }

    /// Yerel kayıt hem `pendingUpload` hem de gelen sunucu kaydından daha yeniyse `true`
    /// (senkron merge bu kaydı ezmez — 05 §3.3 last-write-wins).
    private static func isNewerLocalPending(_ entity: WatchProgressEntity, than record: WatchProgressRecord) -> Bool {
        entity.syncState == SyncState.pendingUpload && entity.watchedAt > record.watchedAt
    }

    private static func record(from entity: WatchProgressEntity) -> WatchProgressRecord {
        WatchProgressRecord(
            episodeID: EpisodeID(entity.episodeId),
            seriesID: SeriesID(entity.seriesId),
            positionSec: entity.positionSec,
            durationSec: entity.durationSec,
            completed: entity.completed,
            watchedAt: entity.watchedAt
        )
    }
}
