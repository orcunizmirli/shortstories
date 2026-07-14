import Foundation

/// Tamamlanmış indirmenin özeti (PlayerKit-internal).
struct DownloadedAsset: Sendable, Equatable {
    /// Diskteki asset paketi (AVAssetDownloadTask çıktısı `.movpkg`).
    let localURL: URL
    let sizeInBytes: Int64
}

/// İndirme motorunun dar iç arayüzü: canlısı `HLSAssetDownloader`
/// (AVAssetDownloadTask — HLS URL interception ile CACHE'LENEMEZ, 04 §7.1);
/// birim testleri sahte indiriciyle koşar — CI'da gerçek indirme YOKTUR.
protocol AssetDownloading: Sendable {
    /// Tek rung indirme (04 §7.2): `minimumBitrate` ile 480p rung seçilir.
    func downloadAsset(from url: URL, minimumBitrate: Double) async throws -> DownloadedAsset
    func cancelDownload(from url: URL) async
    func removeLocalAsset(at localURL: URL) async throws
}
