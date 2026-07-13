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
