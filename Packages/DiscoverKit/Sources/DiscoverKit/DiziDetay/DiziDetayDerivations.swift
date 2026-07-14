import ContentKit
import Foundation

/// "İzlemeye Başla / Devam Et" CTA'sının hedefi — SAF, izleme geçmişinden türetilir (02 §4.4).
/// Metin (`kind`) + hedef bölüm + başlangıç pozisyonu. Kilit durumu ayrı çözülür (entitlement
/// asenkron); bu tip yalnız geçmiş → hedef eşlemesini yapar.
public struct ContinueWatchingTarget: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// İzleme geçmişi yok → "İzlemeye Başla".
        case start
        /// Geçmiş var → "Devam Et · Bölüm N".
        case resume
    }

    public let kind: Kind
    /// 1 tabanlı hedef bölüm numarası.
    public let episodeNumber: Int
    /// Devam pozisyonu (saniye); başlangıçta / tamamlanmış bölümde sonrakine geçişte 0.
    public let startPositionSec: Double

    public init(kind: Kind, episodeNumber: Int, startPositionSec: Double) {
        self.kind = kind
        self.episodeNumber = episodeNumber
        self.startPositionSec = startPositionSec
    }

    /// Kurallar (02 §4.4 + 05 §2.11: "Devam Et konumu yalnız ileri gider"):
    /// - geçmiş yok → ilk bölümden başla.
    /// - geçmiş var, yarım → o bölümden kaldığı yerden devam.
    /// - geçmiş var, tamamlanmış → bir SONRAKİ bölüm (yayınlanmış son bölümü aşarsa son bölümde kalır).
    public static func resolve(series: Series, episodes: [Episode], progress: WatchProgress?) -> ContinueWatchingTarget {
        guard let progress, let watched = episodes.first(where: { $0.id == progress.episodeId }) else {
            let first = episodes.map(\.index).min() ?? 1
            return ContinueWatchingTarget(kind: .start, episodeNumber: first, startPositionSec: 0)
        }
        guard progress.completed else {
            return ContinueWatchingTarget(kind: .resume, episodeNumber: watched.index, startPositionSec: progress.positionSec)
        }
        let next = watched.index + 1
        if next <= series.releasedEpisodeCount {
            return ContinueWatchingTarget(kind: .resume, episodeNumber: next, startPositionSec: 0)
        }
        // Yayınlanmış son bölüm de tamamlandı → o bölümde kalınır (yeni bölüm bekleniyor).
        return ContinueWatchingTarget(kind: .resume, episodeNumber: watched.index, startPositionSec: 0)
    }
}

/// Bölüm ızgarası hücre durumu — SAF (02 §4.4). Öncelik: yayınlanmadı > kilitli > kaldığı bölüm >
/// izlendi > açık. Kilitli, "kaldığı bölüm"den önce gelir çünkü kilit açma zorunlu aksiyondur.
public enum EpisodeCellState: Equatable, Sendable {
    /// İzlendi — soluk + tik (02 §4.4).
    case watched
    /// Kaldığı bölüm — accent çerçeve (02 §4.4).
    case current
    /// Açık, normal.
    case available
    /// Kilitli — kilit ikonu + coin fiyatı (`unlockPrice`; nil = coin yolu kapalı, 05 §2.2).
    case locked(price: Int?)
    /// Henüz yayınlanmadı — takvim hücresi (release schedule, 02 §4.4).
    case scheduled

    public static func resolve(
        episode: Episode,
        isWatched: Bool,
        isCurrent: Bool,
        isAccessible: Bool,
        now: Date
    ) -> EpisodeCellState {
        guard episode.isPublished(at: now) else { return .scheduled }
        if !isAccessible {
            return .locked(price: episode.access.unlockPrice)
        }
        if isCurrent {
            return .current
        }
        if isWatched {
            return .watched
        }
        return .available
    }
}

/// Yayın takvimi bilgisi — SAF (02 §4.4: "Tamamlandı / Devam ediyor — Çarşamba yeni bölüm").
public enum ReleaseScheduleInfo: Equatable, Sendable {
    case completed
    /// Devam ediyor, sonraki bölüm tarihi biliniyor → "Yeni bölüm: <gün>".
    case ongoingScheduled(nextEpisodeAt: Date)
    /// Devam ediyor, tarih bilinmiyor.
    case ongoingUnknown

    public static func resolve(series: Series) -> ReleaseScheduleInfo {
        switch series.releaseState {
        case .completed:
            .completed
        case .ongoing, .unknown:
            series.nextEpisodeAt.map(ReleaseScheduleInfo.ongoingScheduled) ?? .ongoingUnknown
        }
    }

    /// Sonraki bölüm günü lokalize adı (ör. "Cuma"). `ongoingScheduled` dışında nil.
    public func newEpisodeWeekday(calendar: Calendar) -> String? {
        guard case let .ongoingScheduled(date) = self else { return nil }
        let weekday = calendar.component(.weekday, from: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        let symbols = formatter.weekdaySymbols ?? []
        guard weekday >= 1, weekday <= symbols.count else { return nil }
        return symbols[weekday - 1]
    }
}

/// 30'luk bölüm ızgarası aralık sekmesi (02 §4.4: "30+ bölümlü dizilerde 30'luk aralık sekmeleri").
public struct EpisodeBlock: Equatable, Sendable, Identifiable {
    public let id: Int
    /// Sekme başlığı, ör. "1-30".
    public let title: String
    public let range: ClosedRange<Int>

    public init(id: Int, title: String, range: ClosedRange<Int>) {
        self.id = id
        self.title = title
        self.range = range
    }
}

/// Bölüm ızgarası aralık sekmelerinin saf üretimi.
public enum EpisodeBlocks {
    public static let defaultBlockSize = 30

    /// `episodeCount <= blockSize` → sekme yok (boş dizi; View tüm ızgarayı tek parça çizer).
    public static func make(episodeCount: Int, blockSize: Int = defaultBlockSize) -> [EpisodeBlock] {
        guard episodeCount > blockSize, blockSize > 0 else { return [] }
        var blocks: [EpisodeBlock] = []
        var start = 1
        var id = 0
        while start <= episodeCount {
            let end = min(start + blockSize - 1, episodeCount)
            blocks.append(EpisodeBlock(id: id, title: "\(start)-\(end)", range: start ... end))
            start = end + 1
            id += 1
        }
        return blocks
    }
}
