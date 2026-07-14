import UIKit

/// Scroll/paging köprüsü (internal — `FeedScrollProxy` çağırır): `UICollectionView`/
/// `UIScrollView` delegate olaylarını VC durumuna çevirir. Public yüzeye eklenmez
/// (04 §2.4 asgari yüzey).
extension PlayerFeedViewController {
    /// Hücre görünür oldu: bekleyen lease varsa bağla (settle hücreden önce geldiyse).
    func willDisplayCell(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
        guard let pending = pendingBind, pending.index == indexPath.item,
              let playerCell = cell as? PlayerCell
        else { return }
        pendingBind = nil
        playerCell.bind(handle: pending.handle)
    }

    /// Hücre ekran dışına çıktı (04 §14 T5, denetim (c)): layer.player=nil +
    /// isReadyForDisplay KVO'su SENKRON kesilir — bayat ilk-kare sinyali eski
    /// episodeID ile ateşlenemez (sahte video_start/ttff yok; iki layer'a render yok).
    func didEndDisplayingCell(_ cell: UICollectionViewCell, at _: IndexPath) {
        (cell as? PlayerCell)?.unbind()
    }

    /// Swipe niyeti (t0 = scrollViewWillEndDragging — 04 §13.1): hedef indeks belli
    /// olduğunda swipe gecikmesi işareti director'a kaydedilir (deceleration dahil).
    func recordSwipeIntent(targetOffsetY: CGFloat) {
        guard let index = pageIndex(forOffsetY: targetOffsetY) else { return }
        let now = Date()
        Task { [director] in
            await director.recordSwipeIntent(toIndex: index, at: now)
        }
    }

    /// Kaydırma yerleşti (deceleration bitti / drag decelerate'siz bitti).
    func scrollDidSettle() {
        settleAtCurrentOffset(startType: .swipe)
    }

    /// Programatik kaydırma animasyonu bitti (auto-advance): bekleyen settle uygulanır.
    func scrollAnimationDidEnd() {
        if let pending = pendingProgrammaticSettle {
            pendingProgrammaticSettle = nil
            settle(at: pending.index, startType: pending.startType)
        } else {
            settleAtCurrentOffset(startType: .swipe)
        }
    }

    private func settleAtCurrentOffset(startType: PlaybackStartType) {
        guard let collectionView, let index = pageIndex(forOffsetY: collectionView.contentOffset.y) else { return }
        settle(at: index, startType: startType)
    }

    private func pageIndex(forOffsetY offsetY: CGFloat) -> Int? {
        guard let collectionView, collectionView.bounds.height > 0, !items.isEmpty else { return nil }
        let page = Int((offsetY / collectionView.bounds.height).rounded())
        return min(max(page, 0), items.count - 1)
    }
}
