import AppFoundation
import Foundation

/// "Devam Et" kartının görüntüleme modeli — SAF (02 §4.12: mini poster + dizi adı +
/// "Bölüm 7 · %62" + ilerleme çubuğu + son izleme zamanı). `WatchProgressRecord` (tek kaynak,
/// SS-122) + opsiyonel katalog JOIN'inden türetilir.
public struct ContinueWatchingItem: Sendable, Equatable, Identifiable {
    public var id: EpisodeID {
        episodeID
    }

    public let seriesID: SeriesID
    public let episodeID: EpisodeID
    public let seriesTitle: String
    public let coverURL: URL?
    /// 1 tabanlı bölüm numarası; katalog vermezse nil (etiket yalnız yüzdeye düşer).
    public let episodeNumber: Int?
    /// Kaldığı konum (saniye) — kart dokununca `PlayerFeed`'e bu pozisyonla girilir (§4.12).
    public let positionSec: Double
    /// [0, 1] izleme oranı (`WatchProgressRecord.progressFraction`).
    public let progressFraction: Double
    public let watchedAt: Date
    /// `false` = dizi yayından kalktı (kart soluk + "yayında değil", §4.12 edge case).
    public let isAvailable: Bool

    public init(
        seriesID: SeriesID,
        episodeID: EpisodeID,
        seriesTitle: String,
        coverURL: URL?,
        episodeNumber: Int?,
        positionSec: Double,
        progressFraction: Double,
        watchedAt: Date,
        isAvailable: Bool
    ) {
        self.seriesID = seriesID
        self.episodeID = episodeID
        self.seriesTitle = seriesTitle
        self.coverURL = coverURL
        self.episodeNumber = episodeNumber
        self.positionSec = positionSec
        self.progressFraction = progressFraction
        self.watchedAt = watchedAt
        self.isAvailable = isAvailable
    }

    /// İlerleme yüzdesi (0...100 tam sayı) — "%62" etiketi + analitik `progress_pct`.
    public var progressPercent: Int {
        Int((min(1, max(0, progressFraction)) * 100).rounded())
    }

    /// `WatchProgressRecord` + katalog JOIN → görüntüleme modeli (SAF). Katalog dizi özeti
    /// yoksa (kaldırılmış içerik) başlık boş + `isAvailable=false` döner.
    public static func make(
        record: WatchProgressRecord,
        info: LibrarySeriesInfo?,
        episodeNumber: Int?
    ) -> ContinueWatchingItem {
        ContinueWatchingItem(
            seriesID: record.seriesID,
            episodeID: record.episodeID,
            seriesTitle: info?.title ?? "",
            coverURL: info?.coverURL,
            episodeNumber: episodeNumber,
            positionSec: record.positionSec,
            progressFraction: record.progressFraction,
            watchedAt: record.watchedAt,
            isAvailable: info?.isAvailable ?? false
        )
    }
}

/// Favoriler ızgarası hücresinin görüntüleme modeli — SAF (02 §4.12: 3 sütun poster ızgarası,
/// eklenme tarihine göre yeni→eski). `FavoriteRecord` + katalog JOIN'inden türetilir.
public struct FavoriteItem: Sendable, Equatable, Identifiable {
    public var id: SeriesID {
        seriesID
    }

    public let seriesID: SeriesID
    public let title: String
    public let coverURL: URL?
    public let isAvailable: Bool
    public let addedAt: Date

    public init(seriesID: SeriesID, title: String, coverURL: URL?, isAvailable: Bool, addedAt: Date) {
        self.seriesID = seriesID
        self.title = title
        self.coverURL = coverURL
        self.isAvailable = isAvailable
        self.addedAt = addedAt
    }

    public static func make(record: FavoriteRecord, info: LibrarySeriesInfo?) -> FavoriteItem {
        FavoriteItem(
            seriesID: record.seriesID,
            title: info?.title ?? "",
            coverURL: info?.coverURL,
            isAvailable: info?.isAvailable ?? false,
            addedAt: record.addedAt
        )
    }
}
