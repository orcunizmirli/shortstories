import Foundation

/// Cache'lenmiş bir payload'ın okuma sonucu (Series/Episode snapshot'ı). `payload` opaktır —
/// decode/encode `ContentKit`'in sorumluluğudur; cache katmanı yalnız `Data` + tazelik
/// metadata'sı taşır.
public struct CachedPayload: Sendable, Equatable {
    public let payload: Data
    public let etag: String?
    public let fetchedAt: Date

    public init(payload: Data, etag: String?, fetchedAt: Date) {
        self.payload = payload
        self.etag = etag
        self.fetchedAt = fetchedAt
    }
}

/// Katalog cache metadata defterinin (Series/Episode/Feed snapshot'ları) feature yüzeyi
/// (03 §9, 05 §3.1–§3.2). `ContentKit` (SS-030+) soğuk açılış ve çevrimdışı raflar için
/// yalnız bu protokolü görür.
///
/// **Cache şema evrimi kuralı (05 §3.2 birebir):** okuma anında `payloadSchemaVersion`
/// beklenenden ESKİYSE kayıt **sessizce silinir ve `nil` döner** (çağıran sunucudan tazeler).
/// Cache entity'leri için SwiftData migration YAZILMAZ — cache her zaman yeniden üretilebilir.
///
/// **LRU tahliye (05 §3.2):** `CachedSeriesEntity` + `CachedEpisodeListEntity` toplamı
/// `PersistenceBudgets.catalogMaxRecords` veya `catalogMaxBytes`'ı aşarsa `lastAccessAt`
/// sırasıyla (en eski erişim önce) silinir. `WatchProgress`/`Favorite` kullanıcı verisi
/// ASLA tahliye edilmez.
public protocol CatalogCacheStore: Sendable {
    /// Dizinin cache snapshot'ı; şema eskiyse sessizce silinip `nil` döner. Okuma
    /// `lastAccessAt`'i tazeler (LRU).
    func cachedSeries(id: SeriesID, expectedSchemaVersion: Int) async throws -> CachedPayload?
    func storeSeries(id: SeriesID, payload: Data, schemaVersion: Int, etag: String?, fetchedAt: Date) async throws

    /// Dizinin bölüm listesi snapshot'ı (05 §3.2: `access` alanı BAYAT kabul edilir).
    func cachedEpisodeList(seriesID: SeriesID, expectedSchemaVersion: Int) async throws -> CachedPayload?
    func storeEpisodeList(
        seriesID: SeriesID,
        payload: Data,
        schemaVersion: Int,
        etag: String?,
        fetchedAt: Date
    ) async throws

    /// Feed son sayfa snapshot'ı (05 §3.2 `FeedSnapshotEntity`; tek kayıt, `key` ör. "forYou").
    /// Şema eskiyse sessizce silinip `nil` döner.
    func cachedFeedSnapshot(key: String, expectedSchemaVersion: Int) async throws -> CachedPayload?
    func storeFeedSnapshot(key: String, payload: Data, schemaVersion: Int, fetchedAt: Date) async throws

    /// LRU tahliyeyi çalıştırır; bütçe aşımı yoksa no-op. Silinen kayıt sayısını döner.
    @discardableResult
    func evictCatalogCacheIfNeeded() async throws -> Int
}

/// Yerel depolama bütçeleri (05 §3.2, 03 §9). Katalog cache sınırı tahliyeyi tetikler;
/// video cache bütçesi `AssetCacheIndexing` eviction kararında kullanılır (04 §7.2).
public enum PersistenceBudgets {
    /// `CachedSeriesEntity` + `CachedEpisodeListEntity` toplam kayıt sınırı (05 §3.2).
    public static let catalogMaxRecords = 500
    /// Katalog cache toplam payload bayt sınırı (05 §3.2: 20 MB).
    public static let catalogMaxBytes: Int64 = 20 * 1024 * 1024
    /// Disk video cache bütçesi (03 §9, KANON §2: ~200 MB LRU).
    public static let assetCacheBytes: Int64 = 200 * 1024 * 1024
}
