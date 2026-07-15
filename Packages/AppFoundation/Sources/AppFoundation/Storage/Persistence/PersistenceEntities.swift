import Foundation
import SwiftData

// Yerel şemanın TEK doğruluk kaynağı 05-veri-modeli-api.md §3.2'dir; entity adları ve
// alanları buradaki tanımlarla BİREBİR eşleşir. Tüm `@Model` tipleri paket-internal'dır:
// feature modülleri bunları GÖRMEZ, yalnız repository/indeks protokollerini görür (03 §9).
//
// `import SwiftData` YALNIZ `Storage/Persistence/` altında geçer (03 §9, CI yasak-import lint'i).

// MARK: - Kullanıcı verisi (tahliye EDİLMEZ; migration bu entity'ler için yazılır)

@Model
final class WatchProgressEntity {
    @Attribute(.unique) var episodeId: String
    var seriesId: String
    var positionSec: Double
    var durationSec: Double
    var completed: Bool
    var watchedAt: Date
    /// 0 = synced, 1 = pendingUpload (05 §3.2).
    var syncState: Int

    init(
        episodeId: String,
        seriesId: String,
        positionSec: Double,
        durationSec: Double,
        completed: Bool,
        watchedAt: Date,
        syncState: Int
    ) {
        self.episodeId = episodeId
        self.seriesId = seriesId
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.completed = completed
        self.watchedAt = watchedAt
        self.syncState = syncState
    }
}

@Model
final class FavoriteEntity {
    @Attribute(.unique) var seriesId: String
    var addedAt: Date
    /// 0 = synced, 1 = pendingAdd, 2 = pendingRemove (05 §3.2).
    var syncState: Int

    init(seriesId: String, addedAt: Date, syncState: Int) {
        self.seriesId = seriesId
        self.addedAt = addedAt
        self.syncState = syncState
    }
}

// MARK: - Cache (yeniden üretilebilir; LRU tahliye edilir, migration YAZILMAZ)

@Model
final class CachedSeriesEntity {
    @Attribute(.unique) var seriesId: String
    /// Series JSON snapshot (Codable ile encode).
    var payload: Data
    /// Cache şema evrimi (05 §3.2): eskiyse kayıt sessizce silinir, migration yazılmaz.
    var payloadSchemaVersion: Int
    var etag: String?
    var fetchedAt: Date
    /// LRU tahliye sıralama anahtarı.
    var lastAccessAt: Date

    init(
        seriesId: String,
        payload: Data,
        payloadSchemaVersion: Int,
        etag: String?,
        fetchedAt: Date,
        lastAccessAt: Date
    ) {
        self.seriesId = seriesId
        self.payload = payload
        self.payloadSchemaVersion = payloadSchemaVersion
        self.etag = etag
        self.fetchedAt = fetchedAt
        self.lastAccessAt = lastAccessAt
    }
}

@Model
final class CachedEpisodeListEntity {
    @Attribute(.unique) var seriesId: String
    /// [Episode] snapshot — `access` alanı BAYAT kabul edilir (05 §3.2).
    var payload: Data
    var payloadSchemaVersion: Int
    var etag: String?
    var fetchedAt: Date
    /// LRU tahliye (CachedSeriesEntity ile aynı politika).
    var lastAccessAt: Date

    init(
        seriesId: String,
        payload: Data,
        payloadSchemaVersion: Int,
        etag: String?,
        fetchedAt: Date,
        lastAccessAt: Date
    ) {
        self.seriesId = seriesId
        self.payload = payload
        self.payloadSchemaVersion = payloadSchemaVersion
        self.etag = etag
        self.fetchedAt = fetchedAt
        self.lastAccessAt = lastAccessAt
    }
}

@Model
final class FeedSnapshotEntity {
    @Attribute(.unique) var key: String
    /// [FeedItem] ilk sayfa snapshot'ı.
    var payload: Data
    var payloadSchemaVersion: Int
    var fetchedAt: Date

    init(key: String, payload: Data, payloadSchemaVersion: Int, fetchedAt: Date) {
        self.key = key
        self.payload = payload
        self.payloadSchemaVersion = payloadSchemaVersion
        self.fetchedAt = fetchedAt
    }
}

@Model
final class CachedAssetRecordEntity {
    /// Video cache defterinin (~200 MB LRU) benzersiz anahtarı (04 §7.2, SS-043).
    @Attribute(.unique) var episodeId: String
    /// AVAssetDownloadTask çıktısının yerel konumu.
    var localAssetPath: String
    var sizeBytes: Int64
    /// ~200 MB LRU tahliyesinin sıralama anahtarı.
    var lastAccessAt: Date
    /// İzlenmiş bölümler eviction'da önceliklidir (05 §3.2).
    var watchCompleted: Bool

    init(episodeId: String, localAssetPath: String, sizeBytes: Int64, lastAccessAt: Date, watchCompleted: Bool) {
        self.episodeId = episodeId
        self.localAssetPath = localAssetPath
        self.sizeBytes = sizeBytes
        self.lastAccessAt = lastAccessAt
        self.watchCompleted = watchCompleted
    }
}
