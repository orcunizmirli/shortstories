import AppFoundation
import Foundation

/// DiziDetay'ın açılış kaynağı (08 §3.3 `series_detail_view.source`).
public enum DiziDetaySource: String, Sendable, Equatable {
    case kesfet
    case arama
    case playerFeed = "player_feed"
    case listem
    case deeplink
}

/// Kilitli bölüm açma niyeti — WalletKit'i import ETMEDEN taşınan sözleşme (R2/R3). App
/// koordinatörü bunu WalletKit'in `UnlockContext`ine çevirip `UnlockSheet` sunar (02 §4.6).
public struct LockedEpisodeIntent: Equatable, Sendable {
    public let seriesID: SeriesID
    public let episodeID: EpisodeID
    public let seriesTitle: String
    public let episodeNumber: Int
    /// Coin fiyatı; nil = coin yolu kapalı (05 §2.2 — reklam/VIP yolları açık kalabilir).
    public let unlockPrice: Int?

    public init(seriesID: SeriesID, episodeID: EpisodeID, seriesTitle: String, episodeNumber: Int, unlockPrice: Int?) {
        self.seriesID = seriesID
        self.episodeID = episodeID
        self.seriesTitle = seriesTitle
        self.episodeNumber = episodeNumber
        self.unlockPrice = unlockPrice
    }
}

/// DiziDetay intent sözleşmesi — App koordinatörü bağlar (02 §4.4 akışları). Zayıf referans,
/// MainActor. Player/UnlockSheet DiscoverKit'e import EDİLMEZ; bağlam koordinatördedir.
@MainActor
public protocol DiziDetayDelegate: AnyObject {
    /// "İzlemeye Başla / Devam Et" veya açık bölüm → `PlayerFeed` (bağlamsal, pozisyonla, §4.4).
    func diziDetayStartWatching(seriesID: SeriesID, episodeNumber: Int, startPositionSec: Double)
    /// Kilitli bölüm (CTA veya ızgara hücresi) → `UnlockSheet` intent (§4.4/§4.6).
    func diziDetayRequestsUnlock(_ intent: LockedEpisodeIntent)
    /// Paylaş → universal link ile share sheet (§4.4, §8.1.1).
    func diziDetayShare(_ url: URL)
    /// Etiket çipi → `Kesfet`'in o tür filtresi (§4.4).
    func diziDetayRequestsDiscover(genre: String)
    /// Kaldırılmış içerik boş durumu CTA'sı → `Kesfet` köküne dön (§4.4). Varsayılan uygulama
    /// filtresiz `Kesfet`'e yönlendirmeye eşdeğerdir (geriye dönük uyumluluk).
    func diziDetayRequestsDiscoverRoot()
}

public extension DiziDetayDelegate {
    /// Varsayılan: filtresiz tür isteği olarak `Kesfet`'e yönlendir (mevcut koordinatörler
    /// yeni metodu uygulamasa da derlenir).
    func diziDetayRequestsDiscoverRoot() {
        diziDetayRequestsDiscover(genre: "")
    }
}
