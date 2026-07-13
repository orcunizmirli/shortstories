import AppFoundation
import Foundation

/// For You feed kartı (05 §2.12). Heterojen liste `type` ile ayrıştırılır; Faz 1'de
/// `.episode` baskındır. Sunucu sıralaması otoritatiftir — istemci müdahale etmez.
public struct FeedItem: Codable, Identifiable, Hashable, Sendable {
    /// Feed item ID (episode ID DEĞİL; dedup için ayrı).
    public let id: String
    public let type: ItemType
    /// `.episode` için zorunlu; diğer tiplerde nil olabilir.
    public let episode: Episode?
    /// Her item'da bağlam için mevcut — PlayerFeed overlay'i buradan beslenir.
    public let series: Series
    /// Kullanıcı bu bölümü yarım bırakmışsa oynatma bu konumdan başlar.
    public let progress: WatchProgress?
    /// Lokalize öneri gerekçesi ("Romantik izlediğin için").
    public let reason: String?

    public enum ItemType: String, Codable, Sendable, UnknownDecodable {
        case episode, seriesPromo, unknown
    }

    public init(
        id: String,
        type: ItemType,
        episode: Episode?,
        series: Series,
        progress: WatchProgress?,
        reason: String?
    ) {
        self.id = id
        self.type = type
        self.episode = episode
        self.series = series
        self.progress = progress
        self.reason = reason
    }
}

public extension [FeedItem] {
    /// 05 §2.12 dedup'u İKİ düzeydedir: (1) feed item `id`si — aynı item id ikinci kez
    /// düşerse tekillenir (bölüm taşımayanlar dahil, ör. `seriesPromo`); (2) `episode.id` —
    /// aynı bölüm farklı item id'leriyle iki kez düşerse de tekillenir. Bölüm taşımayan
    /// item'lar yalnız item id düzeyinde elenir.
    func deduplicatingEpisodes() -> [FeedItem] {
        var seenItemIds = Set<String>()
        var seenEpisodeIds = Set<EpisodeID>()
        return filter { item in
            guard seenItemIds.insert(item.id).inserted else { return false }
            guard let episodeId = item.episode?.id else { return true }
            return seenEpisodeIds.insert(episodeId).inserted
        }
    }
}
