import AppFoundation
import Foundation
@testable import PlayerKit

// MARK: - Cache sahteleri (EpisodeCacheStore testleri)

final class FakeCacheIndex: AssetCacheIndexing, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [URL: CachedAssetRecord] = [:]

    var allRecords: [CachedAssetRecord] {
        lock.withLock { Array(records.values) }
    }

    func record(for url: URL) async throws -> CachedAssetRecord? {
        lock.withLock { records[url] }
    }

    func upsert(_ record: CachedAssetRecord) async throws {
        lock.withLock { records[record.url] = record }
    }

    func markAccessed(_ url: URL, at date: Date) async throws {
        lock.withLock {
            guard let existing = records[url] else { return }
            records[url] = CachedAssetRecord(url: url, sizeInBytes: existing.sizeInBytes, lastAccessAt: date)
        }
    }

    func remove(_ url: URL) async throws {
        lock.withLock { records[url] = nil }
    }

    func totalSizeInBytes() async throws -> Int64 {
        lock.withLock { records.values.reduce(0) { $0 + $1.sizeInBytes } }
    }

    func evictionCandidates(toFree bytes: Int64) async throws -> [CachedAssetRecord] {
        lock.withLock {
            var freed: Int64 = 0
            var result: [CachedAssetRecord] = []
            for record in records.values.sorted(by: { $0.lastAccessAt < $1.lastAccessAt }) {
                guard freed < bytes else { break }
                result.append(record)
                freed += record.sizeInBytes
            }
            return result
        }
    }
}

final class FakeDownloader: AssetDownloading, @unchecked Sendable {
    struct Download: Equatable, Sendable {
        let remoteURL: URL
        let minimumBitrate: Double
    }

    private let lock = NSLock()
    private var startedDownloads: [Download] = []
    private var removed: [URL] = []
    private var assetSize: Int64

    init(assetSizeInBytes: Int64 = 1000) {
        assetSize = assetSizeInBytes
    }

    var downloads: [Download] {
        lock.withLock { startedDownloads }
    }

    var removedLocalURLs: [URL] {
        lock.withLock { removed }
    }

    func downloadAsset(from url: URL, minimumBitrate: Double) async throws -> DownloadedAsset {
        let count = lock.withLock {
            startedDownloads.append(Download(remoteURL: url, minimumBitrate: minimumBitrate))
            return startedDownloads.count
        }
        let size = lock.withLock { assetSize }
        return DownloadedAsset(
            localURL: URL(string: "file:///cache/asset-\(count).movpkg")!,
            sizeInBytes: size
        )
    }

    func cancelDownload(from url: URL) async {}

    func removeLocalAsset(at localURL: URL) async throws {
        lock.withLock { removed.append(localURL) }
    }
}
