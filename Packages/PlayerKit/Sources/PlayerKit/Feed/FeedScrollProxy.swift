import UIKit

/// `UICollectionView`/`UIScrollView` delegate'ini `PlayerFeedViewController`'ın public
/// yüzeyinden ayıran internal proxy (04 §2.4 kapalı liste): `willDisplay`/
/// `didEndDisplaying`/`willEndDragging`/settle metotları dışarıya public SIZMAZ —
/// VC yüzeyi `init + apply + delegate` asgarisinde kalır. VC proxy'yi güçlü tutar,
/// proxy VC'yi weak tutar (retain cycle yok).
final class FeedScrollProxy: NSObject, UICollectionViewDelegate {
    weak var controller: PlayerFeedViewController?

    func collectionView(
        _: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        controller?.willDisplayCell(cell, at: indexPath)
    }

    func collectionView(
        _: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        controller?.didEndDisplayingCell(cell, at: indexPath)
    }

    func scrollViewWillEndDragging(
        _: UIScrollView,
        withVelocity _: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        controller?.recordSwipeIntent(targetOffsetY: targetContentOffset.pointee.y)
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        controller?.scrollDidSettle()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            controller?.scrollDidSettle()
        }
    }

    func scrollViewDidEndScrollingAnimation(_: UIScrollView) {
        controller?.scrollAnimationDidEnd()
    }
}
