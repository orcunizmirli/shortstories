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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        seriesId = try container.decode(String.self, forKey: .seriesId)
        index = try container.decode(Int.self, forKey: .index)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        durationSec = try container.decode(Int.self, forKey: .durationSec)
        thumbnailURL = try container.decode(URL.self, forKey: .thumbnailURL)
        access = try container.decode(EpisodeAccessWire.self, forKey: .access)
        // `publishedAt` non-core (UI): bozuk/parse-edilemez tarih (çekirdeği geçerli) bölümü düşürmesin (audit).
        publishedAt = container.decodeLossyDate(forKey: .publishedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, seriesId, index, title, durationSec, thumbnailURL, access, publishedAt
    }

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
