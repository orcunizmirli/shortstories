import ContentKit
import Foundation

/// PlayerFeed navigasyon/aksiyon niyetlerinin Coordinator'a aktığı public protokol
/// (04 §2.4). `PlayerFeedViewController` hiçbir ekran açmaz (04 §2.2): UnlockSheet,
/// DiziDetay, BolumListesi, paylaşım ve menüler App katmanındaki Coordinator'da
/// yaşar; buradaki her çağrı yalnız NİYETTİR. İmzalar yalnız ContentKit/Foundation
/// value tipleri taşır — AVFoundation sızmaz (04 §2.4 kural 1).
@MainActor
public protocol PlayerFeedDelegate: AnyObject {
    /// Kilitli bölüme gelindi (04 §9.1 adım 3): oynatma başlamadı, UnlockSheet
    /// açılmalı. Tetik idempotenttir — aynı kartta çift sheet açılmaz.
    func playerFeed(
        _ feed: PlayerFeedViewController,
        didReachLockedEpisode episode: Episode,
        in series: Series
    )

    /// Aktif kart değişti (settle tamamlandı). `episode` bölüm taşımayan kartlarda nil.
    func playerFeed(
        _ feed: PlayerFeedViewController,
        didChangeActiveIndex index: Int,
        episode: Episode?
    )

    /// Feed tükendi (dizi sonu dahil — 04 §8.6): yeni sayfa / yeni dizi önerisi istenir.
    func playerFeedDidRequestMoreItems(_ feed: PlayerFeedViewController)

    /// Üst/alt bilgi bölgesindeki dizi adı dokunuşu → DiziDetay (02 §4.3.2 katman 2).
    func playerFeed(_ feed: PlayerFeedViewController, didRequestSeriesDetail series: Series)

    /// Sağ ray: Favori (SS-063; favori YALNIZ ray butonundan — 02 §4.3.2).
    func playerFeed(
        _ feed: PlayerFeedViewController,
        didRequestFavoriteToggle series: Series,
        episode: Episode?
    )

    /// Sağ ray: Paylaş (SS-063; deep link üretimi App katmanında — SS-142).
    func playerFeed(
        _ feed: PlayerFeedViewController,
        didRequestShare series: Series,
        episode: Episode?
    )

    /// Sağ ray: Bölümler → BolumListesi sheet'i (04 §8.5).
    func playerFeed(_ feed: PlayerFeedViewController, didRequestEpisodeList series: Series)

    /// Sağ ray: Hız menüsü (04 §8.2; F1 iskelet — menü UI'ı sonraki dilim).
    func playerFeed(_ feed: PlayerFeedViewController, didRequestPlaybackSpeedMenu currentRate: Double)

    /// Sağ ray: Altyazı seçim sheet'i (04 §8.3; F1 iskelet — SS-046).
    func playerFeed(_ feed: PlayerFeedViewController, didRequestSubtitleMenu episode: Episode)
}
