import AppFoundation
import Foundation

/// Episode wire DTO'su (05 §2.2; decode sınırı — 05 kural 7).
struct EpisodeWire: Decodable, Sendable {
    let id: String
    let seriesId: String
    let index: Int
    let title: String?
    let durationSec: Int
    let thumbnailURL: URL
    let access: EpisodeAccessWire
    let publishedAt: Date?

    func toDomain() -> Episode {
        Episode(
            id: EpisodeID(id),
            seriesId: SeriesID(seriesId),
            index: index,
            title: title,
            durationSec: durationSec,
            thumbnailURL: thumbnailURL,
            access: access.toDomain(),
            publishedAt: publishedAt
        )
    }
}

/// Bilinmeyen `kind` değeri decode sınırında `.unknown`a düşer (05 §12 kural 4);
/// domain tarafında kilitli varsayılır.
struct EpisodeAccessWire: Decodable, Sendable {
    let kind: EpisodeAccess.Kind
    let unlockPrice: Int?
    let adUnlockEligible: Bool

    func toDomain() -> EpisodeAccess {
        EpisodeAccess(kind: kind, unlockPrice: unlockPrice, adUnlockEligible: adUnlockEligible)
    }
}
