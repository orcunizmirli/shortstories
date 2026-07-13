import AppFoundation
import Foundation

/// FeedItem wire DTO'su (05 §2.12; decode sınırı).
///
/// SÖZLEŞME SAPMASI (bilinçli, 05 §2.12'ye göre): sözleşme `series`i her item'da zorunlu
/// tanımlar; wire'da OPSİYONEL tutulur ki gelecekteki bir item tipi (series bağlamı
/// taşımayan) tüm sayfa zarfını decode hatasıyla düşürmesin (ileri uyumluluk,
/// 05 §12 kural 4 ruhu). Sapma SESSİZ DEĞİLDİR: mapping'de düşen her item
/// `Page.droppedItemCount`ta yüzeye çıkar — telemetri/log bu sayacı tüketir.
struct FeedItemWire: Decodable, Sendable {
    let id: String
    let type: FeedItem.ItemType
    let episode: EpisodeWire?
    let series: SeriesWire?
    let progress: WatchProgressWire?
    let reason: String?

    /// `.unknown` tip RENDER EDİLMEZ, ATLANIR (05 §2.12) — nil döner. `.episode` tipi
    /// episode yükü olmadan veya `series` bağlamı olmadan gelirse sözleşme ihlalidir;
    /// güvenli tarafta item düşürülür, sayfanın kalanı akar.
    func toDomain() -> FeedItem? {
        guard type != .unknown, let series else { return nil }
        if type == .episode, episode == nil {
            return nil
        }
        return FeedItem(
            id: id,
            type: type,
            episode: episode?.toDomain(),
            series: series.toDomain(),
            progress: progress?.toDomain(),
            reason: reason
        )
    }
}

struct WatchProgressWire: Decodable, Sendable {
    let episodeId: String
    let seriesId: String
    let positionSec: Double
    let durationSec: Double
    let completed: Bool
    let watchedAt: Date

    func toDomain() -> WatchProgress {
        WatchProgress(
            episodeId: EpisodeID(episodeId),
            seriesId: SeriesID(seriesId),
            positionSec: positionSec,
            durationSec: durationSec,
            completed: completed,
            watchedAt: watchedAt
        )
    }
}

extension PageWire<FeedItemWire> {
    /// Sayfa mapping'i: bilinmeyen/eksik item'lar `compactMap` ile düşer, cursor ve
    /// ttl aynen taşınır (05 §7.1). Düşenler sessizce kaybolmaz — sayısı
    /// `droppedItemCount`ta taşınır.
    func toDomain() -> Page<FeedItem> {
        let mapped = items.compactMap { $0.toDomain() }
        return Page(
            items: mapped,
            nextCursor: nextCursor,
            ttlSec: ttlSec,
            droppedItemCount: items.count - mapped.count
        )
    }
}

extension PageWire<EpisodeWire> {
    func toDomain() -> Page<Episode> {
        Page(items: items.map { $0.toDomain() }, nextCursor: nextCursor, ttlSec: ttlSec)
    }
}

extension PageWire<SeriesWire> {
    func toDomain() -> Page<Series> {
        Page(items: items.map { $0.toDomain() }, nextCursor: nextCursor, ttlSec: ttlSec)
    }
}
