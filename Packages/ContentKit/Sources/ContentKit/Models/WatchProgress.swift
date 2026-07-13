import AppFoundation
import Foundation

/// İzleme ilerlemesi (05 §2.11). Feed item'larında başlangıç konumu olarak taşınır;
/// çakışma çözümü sunucudadır (en yeni `watchedAt` kazanır, 05 §3.3).
public struct WatchProgress: Codable, Hashable, Sendable {
    public let episodeId: EpisodeID
    public let seriesId: SeriesID
    /// 0 ≤ değer ≤ `durationSec`.
    public let positionSec: Double
    public let durationSec: Double
    /// >= %90 izlendi (server kuralı da aynı).
    public let completed: Bool
    /// Son izleme anı (cihaz saati, sunucu düzeltir).
    public let watchedAt: Date

    public init(
        episodeId: EpisodeID,
        seriesId: SeriesID,
        positionSec: Double,
        durationSec: Double,
        completed: Bool,
        watchedAt: Date
    ) {
        self.episodeId = episodeId
        self.seriesId = seriesId
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.completed = completed
        self.watchedAt = watchedAt
    }
}
