import AppFoundation
import ContentKit

// MARK: - Kilit-açıldı reaktivasyon karar katmanı (SAF+static, test hedefi — 04 §9.2 / SS-050)

extension PlayerFeedViewController {
    /// Kilitli aktif kart yeni state'te oynatılabilir olduysa indeksini döner. Çift-apply (VIP) koruması +
    /// başarısız-reaktivasyon retry'ı çağrı yerindeki `reactivatingIndex` UÇUŞ-guard'ıyla sağlanır — transition
    /// heuristiği DEĞİL (self-review4: transition, başarısız reaktivasyonun MEŞRU retry'ını yanlışça bastırdı).
    /// KİMLİK-tabanlı (pozisyonel DEĞİL): kilitli bölümün id'sini yeni listede yeniden bulur → feed
    /// yeniden sıralanırsa (For-You refresh/promo insert/dedup) YANLIŞ komşu kartı reaktive edilmez
    /// (activeIndex'in id'den re-derive edilmesiyle simetrik). Bölüm hâlâ listede + oynatılabilirse indeksi döner.
    static func reactivatableUnlockIndex(newItems: [FeedItem], lockedEpisodeID: EpisodeID?) -> Int? {
        guard let targetID = lockedEpisodeID else { return nil }
        for index in newItems.indices where newItems[index].episode?.id == targetID {
            return newItems[index].episode?.access.isPlayableWithoutUnlock == true ? index : nil
        }
        return nil
    }

    /// Uçuş-guard'ı (self-review4): aday reaktivasyon zaten UÇUŞTAYSA (aynı index) nil döner → tekrar dispatch
    /// edilmez (VIP çift-apply çift-video_start önlenir; uçuş bitince settle guard'ı temizler → retry serbest).
    static func reactivateDispatchIndex(candidate: Int?, reactivatingIndex: Int?) -> Int? {
        guard let candidate, candidate != reactivatingIndex else { return nil }
        return candidate
    }
}
