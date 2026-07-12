import Foundation

/// Disk video cache'inin (~200 MB LRU — kanon §2) metadata kaydı;
/// `CachedAssetRecordEntity`'nin (03 §9) taşıma-bağımsız karşılığı.
public struct CachedAssetRecord: Sendable, Equatable {
    public let url: URL
    public let sizeInBytes: Int64
    public let lastAccessAt: Date

    public init(url: URL, sizeInBytes: Int64, lastAccessAt: Date) {
        self.url = url
        self.sizeInBytes = sizeInBytes
        self.lastAccessAt = lastAccessAt
    }
}

/// Video cache LRU defterinin arayüzü (03 §9). F0'da STUB — somut SwiftData uygulaması
/// `AppFoundation/Storage/Persistence`'a F1'de (PlayerKit dilimi) gelir; `PlayerKit`
/// yalnız bu protokol üzerinden erişir.
public protocol AssetCacheIndexing: Sendable {
    func record(for url: URL) async throws -> CachedAssetRecord?
    func upsert(_ record: CachedAssetRecord) async throws
    func markAccessed(_ url: URL, at date: Date) async throws
    func remove(_ url: URL) async throws
    func totalSizeInBytes() async throws -> Int64
    /// LRU sırasıyla (en eski erişim önce), toplam boyutu `bytes`'a ulaşana dek
    /// tahliye adayı döndürür.
    func evictionCandidates(toFree bytes: Int64) async throws -> [CachedAssetRecord]
}
