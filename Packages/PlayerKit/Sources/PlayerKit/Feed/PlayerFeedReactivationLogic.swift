import ContentKit

// MARK: - Kilit-açıldı reaktivasyon karar katmanı (SAF+static, test hedefi — 04 §9.2 / SS-050)

extension PlayerFeedViewController {
    /// Kilitli aktif kart yeni state'te oynatılabilir olduysa indeksini döner. Çift-apply (VIP) koruması +
    /// başarısız-reaktivasyon retry'ı çağrı yerindeki `reactivatingIndex` UÇUŞ-guard'ıyla sağlanır — transition
    /// heuristiği DEĞİL (self-review4: transition, başarısız reaktivasyonun MEŞRU retry'ını yanlışça bastırdı).
    static func reactivatableUnlockIndex(newItems: [FeedItem], lockedIndex: Int?) -> Int? {
        guard let lockedIndex, newItems.indices.contains(lockedIndex),
              newItems[lockedIndex].episode?.access.isPlayableWithoutUnlock == true
        else { return nil }
        return lockedIndex
    }

    /// Uçuş-guard'ı (self-review4): aday reaktivasyon zaten UÇUŞTAYSA (aynı index) nil döner → tekrar dispatch
    /// edilmez (VIP çift-apply çift-video_start önlenir; uçuş bitince settle guard'ı temizler → retry serbest).
    static func reactivateDispatchIndex(candidate: Int?, reactivatingIndex: Int?) -> Int? {
        guard let candidate, candidate != reactivatingIndex else { return nil }
        return candidate
    }
}
