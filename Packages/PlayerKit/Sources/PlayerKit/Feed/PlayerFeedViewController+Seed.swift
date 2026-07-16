import Foundation
import UIKit

/// Feed-entry/seed ilk aktivasyonu (SS-062/065): bekleyen seed'i director'a verir ve
/// seed edilen içeriği İLK gösterir. Public yüzeye eklenmez (04 §2.4 asgari yüzey) —
/// `PlayerFeedViewController` actor-dışı UIKit parçasıdır, VC ile aynı MainActor'da koşar.
extension PlayerFeedViewController {
    /// İlk aktivasyon: bekleyen seed'i director'a verir (bir kez tüketilir) ve seed edilen
    /// indeks/konumdan (yoksa index 0'dan) settle eder. Çözülen kart görünür değilse ilk
    /// gösterim için programatik konumlama kuyruklanır (`willDisplay` handle'ı bağlar).
    func performInitialActivation() async {
        if let pendingSeed {
            self.pendingSeed = nil
            await director.seed(pendingSeed)
        }
        let result = await director.settleInitial(startType: .tap, now: Date())
        handleSettleOutcome(result.outcome, at: result.index)
        if result.index != 0 {
            pendingInitialScrollIndex = result.index
            applyPendingInitialScrollIfPossible()
        }
    }

    /// Seed'lenen ilk indekse programatik/animasyonsuz konumlanır — layout hazır (bounds > 0)
    /// ve indeks geçerliyse bir kez uygulanır (04 §14 T7: reloadData yok, yalnız scroll).
    func applyPendingInitialScrollIfPossible() {
        guard let index = pendingInitialScrollIndex,
              let collectionView,
              collectionView.bounds.height > 0,
              items.indices.contains(index)
        else { return }
        pendingInitialScrollIndex = nil
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: 0),
            at: .centeredVertically,
            animated: false
        )
    }
}
