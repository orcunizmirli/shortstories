import AppFoundation
import Foundation

/// Aktif lease'in bir hücreye bağlanıp bağlanmayacağının SAF kararı (04 §2 ince UIKit
/// kuralı — kararlar saf katmanda). `willDisplay`, ham koleksiyon indeksiyle DEĞİL
/// bölüm-id ile karar verir (bulgu 4/6):
///
/// - Snapshot kayması (dedup/insert) settle ile hücre gösterimi arasına girse bile,
///   handle YALNIZ gerçekten aktif bölümü taşıyan karta iliştirilir — yanlış karta
///   önceki bölümün AVPlayer yüzeyi (ve TTFF atfı) sızmaz.
/// - Ekran dışına çıkıp (didEndDisplaying → unbind) geri dönen AKTİF hücre, aktif
///   indeks değişmese ve settle .none dönse bile yeniden bağlanır — siyah kare + ses
///   sızıntısı önlenir.
enum FeedCellBindPolicy {
    /// Hücreye aktif handle bağlanmalı mı? Bölüm-id eşleşmesi ZORUNLU; zaten aynı
    /// bölüme bağlıysa gereksiz yeniden bağlama yapılmaz (idempotans).
    static func shouldBindActiveHandle(
        cellEpisodeID: EpisodeID?,
        cellBoundEpisodeID: EpisodeID?,
        activeEpisodeID: EpisodeID?
    ) -> Bool {
        guard let activeEpisodeID, cellEpisodeID == activeEpisodeID else { return false }
        return cellBoundEpisodeID != activeEpisodeID
    }
}
