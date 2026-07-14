import AppFoundation
@preconcurrency import AVFoundation
import Foundation

/// `AssetDownloading`'in AVFoundation canlısı: `AVAssetDownloadURLSession` +
/// `AVAssetDownloadTask` (04 §7.2 — HLS'de Apple'ın desteklediği TEK cache yolu;
/// resource loader tabanlı HLS interception YASAKTIR, 04 §7.1).
///
/// Bu kabuk CI birim testlerinde KOŞMAZ (testler `FakeDownloader` kullanır);
/// gerçek indirme davranışı SS-043'ün cihaz/QA doğrulamasındadır.
final class HLSAssetDownloader: NSObject, AssetDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var session: AVAssetDownloadURLSession?
    private var continuations: [Int: CheckedContinuation<DownloadedAsset, Error>] = [:]
    private var locations: [Int: URL] = [:]
    private var tasksByURL: [URL: AVAssetDownloadTask] = [:]
    private let configurationIdentifier: String

    init(configurationIdentifier: String = "com.shortseries.playerkit.assetdownload") {
        self.configurationIdentifier = configurationIdentifier
        super.init()
    }

    func downloadAsset(from url: URL, minimumBitrate: Double) async throws -> DownloadedAsset {
        let session = ensureSession()
        let asset = AVURLAsset(url: url)
        guard let task = session.makeAssetDownloadTask(
            asset: asset,
            assetTitle: url.lastPathComponent,
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: Int(minimumBitrate)]
        ) else {
            throw AppError.playback(.assetUnavailable)
        }
        lock.withLock { tasksByURL[url] = task }
        defer { lock.withLock { tasksByURL[url] = nil } }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { continuations[task.taskIdentifier] = continuation }
            task.resume()
        }
    }

    func cancelDownload(from url: URL) async {
        let task = lock.withLock { tasksByURL[url] }
        // İptal edilen indirmenin kısmi cache'i korunur (03 §7.3 kural 2).
        task?.cancel()
    }

    func removeLocalAsset(at localURL: URL) async throws {
        do {
            try FileManager.default.removeItem(at: localURL)
        } catch let error as NSError {
            // Dosya zaten yoksa eviction hedefine ulaşılmıştır; hata değildir.
            let isMissingFile = error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError
            guard isMissingFile else {
                throw AppError.unexpected(underlying: "EpisodeCache dosya silme hatası: \(error.localizedDescription)")
            }
        }
    }

    private func ensureSession() -> AVAssetDownloadURLSession {
        lock.withLock {
            if let session {
                return session
            }
            let configuration = URLSessionConfiguration.background(withIdentifier: configurationIdentifier)
            let created = AVAssetDownloadURLSession(
                configuration: configuration,
                assetDownloadDelegate: self,
                delegateQueue: nil
            )
            session = created
            return created
        }
    }
}

extension HLSAssetDownloader: AVAssetDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        assetDownloadTask: AVAssetDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lock.withLock { locations[assetDownloadTask.taskIdentifier] = location }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, location) = lock.withLock {
            let continuation = continuations.removeValue(forKey: task.taskIdentifier)
            let location = locations.removeValue(forKey: task.taskIdentifier)
            return (continuation, location)
        }
        guard let continuation else { return }
        if error != nil {
            continuation.resume(throwing: AppError.playback(.assetUnavailable))
            return
        }
        guard let location else {
            continuation.resume(throwing: AppError.playback(.assetUnavailable))
            return
        }
        let size = (try? FileManager.default.allocatedSizeOfDirectory(at: location)) ?? 0
        continuation.resume(returning: DownloadedAsset(localURL: location, sizeInBytes: size))
    }
}

private extension FileManager {
    /// `.movpkg` paketi bir dizindir; LRU defteri için ayrılmış boyut toplanır.
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        guard let enumerator = enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
