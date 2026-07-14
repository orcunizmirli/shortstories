import ContentKit
import Foundation

/// Bölüm sonu kararının SAF politikası (04 §8.6, SS-062): aktif bölüm playedToEnd
/// olduğunda feed ne yapar? Dizi sonu ayrı bir dal DEĞİLDİR — feed API'ı dizi
/// bitince sıradaki öğe olarak yeni dizi önerisini döndürür (04 §8.6); istemci
/// yalnız feed sırasını oynatır. Feed tükenmişse yeni sayfa istenir.
enum AutoAdvancePolicy {
    enum Decision: Sendable, Equatable {
        /// Sonraki karta programatik kaydırma (kilitliyse aktivasyon kilit akışına düşer).
        case advance(toIndex: Int)
        /// Feed tükendi: Coordinator/VM'den yeni sayfa (yeni dizi önerisi) istenir.
        case requestMoreItems
        /// Otomatik oynatma kapalı ya da karar verilemiyor: yerinde kalınır
        /// (bölüm sonu kartı sonraki dilimde — SS-062 devamı).
        case stay
    }

    static func decision(activeIndex: Int?, itemCount: Int, isAutoAdvanceEnabled: Bool) -> Decision {
        guard isAutoAdvanceEnabled, let activeIndex, itemCount > 0 else {
            return .stay
        }
        let next = activeIndex + 1
        return next < itemCount ? .advance(toIndex: next) : .requestMoreItems
    }
}

/// Devam Et pozisyonu kuralı (04 §12.2, SS-065 çekirdeği): `resumePosition > 3 sn`
/// ve tamamlanma eşiğinin (%90) altındaysa oynatma o konumdan başlar; aksi halde
/// sıfırdan. SAF — feed VC/direktör yalnız uygular.
enum FeedResumePolicy {
    static let minimumResumeSeconds: Double = 3
    /// Kanonik tamamlanma eşiği (04 §12.1 `completedThreshold`).
    static let completedThreshold: Double = 0.9

    static func resumePosition(for item: FeedItem) -> Double? {
        guard let progress = item.progress, let episode = item.episode, !progress.completed else {
            return nil
        }
        let duration = Double(episode.durationSec)
        guard duration > 0,
              progress.positionSec > minimumResumeSeconds,
              progress.positionSec < duration * completedThreshold
        else {
            return nil
        }
        return progress.positionSec
    }
}
