import AppFoundation
import ContentKit

/// SS-050/062 kilitli-bölüm unlock → feed reactivation'ın SAF karar katmanı (yan etkisiz):
/// bir bölüm coin/reklam/VIP ile açıldığında feed öğelerini "oynatılabilir" işaretler.
/// `HomeCoordinator.applyUnlock` bunu `PlayerFeedViewModel.feedState`e akıtır; PlayerKit
/// `PlayerFeedViewController.apply(state:)` diff'li uygular ve `reactivatableUnlockIndex`
/// aracılığıyla kilitli kartı YERİNDE reactivate eder (access `.locked` → oynatılabilir, 04 §9.2).
///
/// Karar burada saf tutulur (test bu katmanı hedefler): access.kind değişimi PlayerKit'in
/// reaktivasyon sinyalidir (`EpisodeAccess.isPlayableWithoutUnlock`), koordinatör yalnız uygular.
enum FeedUnlockReducer {
    /// Verilen `episodeID`'yi taşıyan feed öğe(ler)ini `.unlocked` yapar. Yalnız GERÇEKTEN
    /// değişiklik varsa (bölüm feed'de VAR ve halen kilitli/oynatılamaz) güncellenmiş diziyi
    /// döner; aksi halde `nil` → çağıran `feedState`e DOKUNMAZ (idempotent, gereksiz
    /// `apply(state:)`/reactivation tetiklenmez). Bölüm taşımayan kartlar (seriesPromo) atlanır.
    static func applyingUnlock(of episodeID: EpisodeID, to items: [FeedItem]) -> [FeedItem]? {
        var didChange = false
        let updated = items.map { item -> FeedItem in
            guard let episode = item.episode,
                  episode.id == episodeID,
                  !episode.access.isPlayableWithoutUnlock
            else { return item }
            didChange = true
            return item.replacingEpisode(with: episode.unlocked())
        }
        return didChange ? updated : nil
    }
}

private extension Episode {
    /// Erişimi `.unlocked`'a çevirir (oynatma yetkisi geldi). `unlockPrice`/`adUnlockEligible`
    /// korunur — `.unlocked` iken anlamsızdırlar (05 §2.2) ama veri kaybı yaratmadan taşınır;
    /// bölümün diğer alanları (index/süre/thumbnail/publishedAt) DEĞİŞMEZ.
    func unlocked() -> Episode {
        Episode(
            id: id,
            seriesId: seriesId,
            index: index,
            title: title,
            durationSec: durationSec,
            thumbnailURL: thumbnailURL,
            access: EpisodeAccess(kind: .unlocked, unlockPrice: access.unlockPrice, adUnlockEligible: access.adUnlockEligible),
            publishedAt: publishedAt
        )
    }
}

private extension FeedItem {
    /// Aynı öğe kimliği/bağlamıyla (id/series/progress/reason KORUNUR) bölümü değiştirir:
    /// aynı `id` → diff'li `apply(state:)` kartı reconfigure eder (T7 ihlali/remount YOK).
    func replacingEpisode(with episode: Episode) -> FeedItem {
        FeedItem(id: id, type: type, episode: episode, series: series, progress: progress, reason: reason)
    }
}
