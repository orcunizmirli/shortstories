import AppFoundation
import PlayerKit

// MARK: - Feed reaktivasyonu (SS-050/062: kilit açıldığında feed'de bölümü oynatılabilir işaretle)

extension HomeCoordinator {
    /// Bölüm kilidi açıldı (coin/reklam/başka-cihaz VIP) → feed'de o bölümü oynatılabilir işaretle. Yeni
    /// `feedState` PlayerKit'e diff'li akar; `apply(state:)` kilitli kartı YERİNDE reactivate eder (04 §9.2).
    /// `feedMountToken` BİLİNÇLİ artırılmaz (remount değil diff'li apply → korunan kare kaybolmaz). Karar
    /// SAF (`FeedUnlockReducer`): bölüm feed'de yoksa / zaten oynatılabilirse feed'e dokunulmaz.
    func applyUnlock(_ episodeID: EpisodeID) {
        guard let updatedItems = FeedUnlockReducer.applyingUnlock(
            of: episodeID,
            to: feedViewModel.feedState.items
        ) else { return }
        feedViewModel.feedState = FeedState(items: updatedItems)
    }

    /// VIP aktivasyonu → feed'deki TÜM kilitli bölümleri oynatılabilir işaretle (diff'li apply, remount YOK;
    /// değişiklik yoksa dokunma). Standalone VIP feed'i reaktive etmiyordu (audit LOW; per-episode
    /// `applyUnlock` yalnız tek bölüm açardı, VIP tüm erişim verir).
    func applyVIPUnlock() {
        guard let updatedItems = FeedUnlockReducer.applyingVIPUnlock(to: feedViewModel.feedState.items) else { return }
        feedViewModel.feedState = FeedState(items: updatedItems)
    }
}
