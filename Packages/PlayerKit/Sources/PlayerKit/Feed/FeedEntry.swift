import AppFoundation
import ContentKit
import Foundation

/// Feed'e giriş noktası / seed (SS-062/065): App'in `HomeCoordinator`'ı feed'i belirli
/// bir içerikten başlatmak için taşır — "kaldığın yerden devam" (Ana Sayfa rafı, SS-065),
/// Listem/DiziDetay "Oynat" ve deep link hep bunu üretir. Seed YOKSA feed varsayılan
/// For You akışını baştan (index 0) açar; bu tip yalnız BAŞLANGIÇ noktasını belirtir,
/// sonrası mevcut auto-advance akışına devam eder (04 §8.6 değişmez).
///
/// İmza yalnız AppFoundation value tipleri taşır — AVFoundation/ContentKit modeli
/// sızmaz (04 §2.4 kural 1): `SeriesID`/`EpisodeID` paylaşılan ID tipleridir.
public struct FeedEntry: Sendable, Equatable {
    /// Başlatılacak dizi.
    public let seriesID: SeriesID
    /// Opsiyonel hedef bölüm; nil ise dizinin feed'deki bölüm taşıyan ilk kartı seçilir.
    public let episodeID: EpisodeID?
    /// Oynatmanın başlayacağı konum (saniye, SS-065 "kaldığın yer"). Negatifler 0'a
    /// kırpılır. 0 ise seçilen öğenin kendi devam kaydı (varsa) uygulanır; > 0 ise bu
    /// konum bölüm süresine kırpılır ve öğenin devam kaydının önüne geçer.
    public let startPositionSeconds: Double

    public init(
        seriesID: SeriesID,
        episodeID: EpisodeID? = nil,
        startPositionSeconds: Double = 0
    ) {
        self.seriesID = seriesID
        self.episodeID = episodeID
        self.startPositionSeconds = max(0, startPositionSeconds)
    }
}

/// Seed çözümü (SS-062/065 SAF çekirdeği): `FeedEntry` + mevcut feed öğeleri → feed'in
/// ilk yerleşeceği indeks + uygulanacak başlangıç konumu. Direktör yalnız UYGULAR
/// (`FeedResumePolicy` ile aynı desen, 04 §12.2). Eşleşme yoksa nil döner ve feed
/// varsayılan index 0 davranışına düşer — mevcut For You akışı bozulmaz.
enum FeedSeedPolicy {
    struct Resolution: Equatable, Sendable {
        /// Feed'in ilk yerleşeceği (ilk gösterilecek) indeks.
        let index: Int
        /// Oynatma konumu override'ı; nil ise `FeedResumePolicy` (öğenin kendi devam
        /// kaydı) uygulanır — böylece seed konumu 0 iken devam kaydı korunur.
        let startPositionSeconds: Double?
    }

    /// Seed → çözüm. Hedef indeks: önce tam bölüm eşleşmesi (episodeID), yoksa dizinin
    /// bölüm taşıyan ilk kartı, o da yoksa dizinin ilk kartı. Hiçbiri yoksa nil.
    static func resolve(entry: FeedEntry, in items: [FeedItem]) -> Resolution? {
        guard let index = matchIndex(entry: entry, in: items) else { return nil }
        return Resolution(
            index: index,
            startPositionSeconds: clampedPosition(entry.startPositionSeconds, item: items[index])
        )
    }

    private static func matchIndex(entry: FeedEntry, in items: [FeedItem]) -> Int? {
        if let episodeID = entry.episodeID {
            if let exact = items.firstIndex(where: { $0.episode?.id == episodeID }) {
                return exact
            }
        }
        if let playable = items.firstIndex(where: { $0.series.id == entry.seriesID && $0.episode != nil }) {
            return playable
        }
        return items.firstIndex(where: { $0.series.id == entry.seriesID })
    }

    /// Verilen konum bölüm süresine kırpılır; ≤ 0 ise nil (öğenin kendi devam kuralı).
    private static func clampedPosition(_ seconds: Double, item: FeedItem) -> Double? {
        guard seconds > 0 else { return nil }
        guard let episode = item.episode, episode.durationSec > 0 else { return seconds }
        return min(seconds, Double(episode.durationSec))
    }
}
