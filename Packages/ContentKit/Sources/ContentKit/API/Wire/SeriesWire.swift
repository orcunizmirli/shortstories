import AppFoundation
import Foundation

/// Series wire DTO'su (05 §2.1; decode sınırı — 05 kural 7). Bugün wire alan adları
/// domain adlarıyla örtüşür; ayrıştıklarında YALNIZ bu dosya + fixture'lar değişir,
/// domain modeli ve ViewModel testleri DEĞİŞMEZ.
struct SeriesWire: Decodable, Sendable {
    let id: String
    let title: String
    let synopsis: String
    let coverURL: URL
    let bannerURL: URL?
    let genres: [GenreWire]
    let tags: [TagWire]
    let episodeCount: Int
    let releasedEpisodeCount: Int
    let freeEpisodeCount: Int
    let releaseState: Series.ReleaseState
    let nextEpisodeAt: Date?
    let stats: SeriesStatsWire
    let localeInfo: LocaleInfoWire
    let updatedAt: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        synopsis = try container.decode(String.self, forKey: .synopsis)
        coverURL = try container.decode(URL.self, forKey: .coverURL)
        bannerURL = try container.decodeIfPresent(URL.self, forKey: .bannerURL)
        // Çevresel koleksiyonlar (genres/tags) LOSSY: tek bozuk/eksik alt-eleman TÜM seriyi düşürmesin
        // (05 §12/4 decode-robustness; PageWire.items/DiscoverWire.collections ile simetrik). Liste
        // yolunda geçerli seri komple kaybolmaz, detay yolunda (/series/{id}, lossy DEĞİL) tam-ekran
        // hataya dönüşmez. Çekirdek alanlar (title/cover/erişim/sayımlar) STRICT — onlarsız seri kullanılamaz.
        genres = try container.decodeLossyArray(GenreWire.self, forKey: .genres)
        tags = try container.decodeLossyArray(TagWire.self, forKey: .tags)
        episodeCount = try container.decode(Int.self, forKey: .episodeCount)
        releasedEpisodeCount = try container.decode(Int.self, forKey: .releasedEpisodeCount)
        freeEpisodeCount = try container.decode(Int.self, forKey: .freeEpisodeCount)
        releaseState = try container.decode(Series.ReleaseState.self, forKey: .releaseState)
        // Non-core tarihler LOSSY (audit): `nextEpisodeAt` UI etiketi, `updatedAt` cache metadata — bozuk/parse-
        // edilemez bir tarih TÜM (çekirdeği geçerli) seriyi düşürmesin (detay yolunda tam-ekran hata, liste
        // yolunda sessiz kayıp). Bozuk `updatedAt` → `.distantPast` (çok bayat say → tazeleme zorlanır).
        nextEpisodeAt = container.decodeLossyDate(forKey: .nextEpisodeAt)
        stats = try container.decode(SeriesStatsWire.self, forKey: .stats)
        localeInfo = try container.decode(LocaleInfoWire.self, forKey: .localeInfo)
        updatedAt = container.decodeLossyDate(forKey: .updatedAt) ?? .distantPast
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, synopsis, coverURL, bannerURL, genres, tags
        case episodeCount, releasedEpisodeCount, freeEpisodeCount
        case releaseState, nextEpisodeAt, stats, localeInfo, updatedAt
    }

    func toDomain() -> Series {
        Series(
            id: SeriesID(id),
            title: title,
            synopsis: synopsis,
            coverURL: coverURL,
            bannerURL: bannerURL,
            genres: genres.map { $0.toDomain() },
            tags: tags.map { $0.toDomain() },
            episodeCount: episodeCount,
            releasedEpisodeCount: releasedEpisodeCount,
            freeEpisodeCount: freeEpisodeCount,
            releaseState: releaseState,
            nextEpisodeAt: nextEpisodeAt,
            stats: stats.toDomain(),
            localeInfo: localeInfo.toDomain(),
            updatedAt: updatedAt
        )
    }
}

struct SeriesStatsWire: Decodable, Sendable {
    let viewCount: Int
    let favoriteCount: Int
    let trendingRank: Int?

    func toDomain() -> SeriesStats {
        SeriesStats(viewCount: viewCount, favoriteCount: favoriteCount, trendingRank: trendingRank)
    }
}

struct LocaleInfoWire: Decodable, Sendable {
    let audioLanguage: String
    let subtitleLanguages: [String]

    func toDomain() -> LocaleInfo {
        LocaleInfo(audioLanguage: audioLanguage, subtitleLanguages: subtitleLanguages)
    }
}

struct GenreWire: Decodable, Sendable {
    let id: String
    let name: String
    let iconURL: URL?

    func toDomain() -> Genre {
        Genre(id: id, name: name, iconURL: iconURL)
    }
}

struct TagWire: Decodable, Sendable {
    let id: String
    let name: String

    func toDomain() -> Tag {
        Tag(id: id, name: name)
    }
}
