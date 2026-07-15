import AppFoundation

/// İzleme ilerlemesi senkron backend portu (SS-122/SS-123, 05 §3.3 `POST /playback/progress`).
/// Canlı implementasyon App kompozisyonunda `APIClientProtocol` üzerine bağlanır; testler fake
/// port ile push/pull birleşmesini doğrular. Çevrimdışıyken `AppError.network(.offline)`
/// fırlatır — bekleyen kayıtlar `pendingUpload` olarak kalır (SS-123 batch retry).
public protocol WatchProgressRemoting: Sendable {
    /// Bekleyen yerel kayıtları sunucuya batch yükler (05 §3.3). Başarıda çağıran `markSynced` yapar.
    func uploadProgress(_ records: [WatchProgressRecord]) async throws

    /// Sunucudaki birleşik geçmişi çeker (cihazlar arası birleşme; en yeni `watchedAt` kazanır).
    func fetchServerProgress() async throws -> [WatchProgressRecord]
}
