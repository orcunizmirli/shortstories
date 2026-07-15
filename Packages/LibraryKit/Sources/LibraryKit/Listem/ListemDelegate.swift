import AppFoundation

/// `Listem` navigasyon niyetleri — App koordinatörü bağlar (02 §4.12 akışları). Player/DiziDetay
/// LibraryKit'e import EDİLMEZ; bağlam koordinatördedir (R2). Zayıf referans, MainActor.
@MainActor
public protocol ListemDelegate: AnyObject {
    /// Favori kartı dokunuş → diziyi kaldığı yerden oynat (izlenmemişse 1. bölüm). Kaldığı yer
    /// çözümü App'te `ContinueWatchingService` ile yapılır (§4.12).
    func listemPlaySeries(seriesID: SeriesID)

    /// "Devam Et" kartı → `PlayerFeed` bağlamsal player, kaldığı konumdan (§4.12).
    func listemResumeEpisode(seriesID: SeriesID, episodeID: EpisodeID, startPositionSec: Double)

    /// Favori uzun basma → "Detaya Git" / kaldırılmış içerik kartı → `DiziDetay` (§4.12).
    func listemOpenDetail(seriesID: SeriesID)

    /// Favori uzun basma → "Paylaş" (universal link'i App üretir, §8.1.1).
    func listemShare(seriesID: SeriesID)

    /// Favoriler boş durumu CTA'sı → `Kesfet` (02 §3: CTA içeriğe geri götürür).
    func listemRequestsDiscover()

    /// Devam Et boş durumu CTA'sı → Ana Sayfa (`PlayerFeed`) (§4.12 boş durum).
    func listemRequestsHome()
}
