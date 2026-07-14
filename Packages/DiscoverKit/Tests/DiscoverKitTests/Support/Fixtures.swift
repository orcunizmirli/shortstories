import AppFoundation
import ContentKit
import Foundation
@testable import DiscoverKit

/// Test veri kurucuları — domain modelleri (05 sözleşmesi) için makul varsayılanlarla.
enum Fixtures {
    static func genre(_ id: String, _ name: String? = nil) -> Genre {
        Genre(id: id, name: name ?? id.capitalized, iconURL: nil)
    }

    static func series(
        id: String,
        title: String = "Dizi",
        genres: [String] = ["romance"],
        tags: [String] = [],
        episodeCount: Int = 60,
        releasedEpisodeCount: Int = 60,
        freeEpisodeCount: Int = 5,
        releaseState: Series.ReleaseState = .completed,
        nextEpisodeAt: Date? = nil,
        trendingRank: Int? = nil
    ) -> Series {
        Series(
            id: SeriesID(id),
            title: title,
            synopsis: "Özet metni burada.",
            coverURL: URL(string: "https://cdn.example.com/\(id)/cover.jpg")!,
            bannerURL: URL(string: "https://cdn.example.com/\(id)/banner.jpg"),
            genres: genres.map { genre($0) },
            tags: tags.map { Tag(id: $0, name: $0.capitalized) },
            episodeCount: episodeCount,
            releasedEpisodeCount: releasedEpisodeCount,
            freeEpisodeCount: freeEpisodeCount,
            releaseState: releaseState,
            nextEpisodeAt: nextEpisodeAt,
            stats: SeriesStats(viewCount: 1000, favoriteCount: 100, trendingRank: trendingRank),
            localeInfo: LocaleInfo(audioLanguage: "en", subtitleLanguages: ["en"]),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func episode(
        seriesID: String,
        index: Int,
        access: EpisodeAccess.Kind = .free,
        unlockPrice: Int? = nil,
        publishedAt: Date? = Date(timeIntervalSince1970: 1_600_000_000),
        durationSec: Int = 120
    ) -> Episode {
        Episode(
            id: EpisodeID("\(seriesID)_e\(index)"),
            seriesId: SeriesID(seriesID),
            index: index,
            title: nil,
            durationSec: durationSec,
            thumbnailURL: URL(string: "https://cdn.example.com/\(seriesID)/\(index).jpg")!,
            access: EpisodeAccess(kind: access, unlockPrice: unlockPrice, adUnlockEligible: false),
            publishedAt: publishedAt
        )
    }

    static func collection(
        id: String,
        kind: Collection.Kind = .editorial,
        title: String = "Raf",
        series: [Series],
        nextCursor: String? = nil
    ) -> Collection {
        Collection(id: id, kind: kind, title: title, seriesList: series, nextCursor: nextCursor)
    }

    static func banner(
        id: String,
        deeplink: String = "shortseries://series/srs_abc123",
        startsAt: Date = Date(timeIntervalSince1970: 1_600_000_000),
        endsAt: Date = Date(timeIntervalSince1970: 2_000_000_000)
    ) -> Banner {
        Banner(
            id: id,
            imageURL: URL(string: "https://cdn.example.com/banner/\(id).jpg")!,
            deeplink: URL(string: deeplink)!,
            title: "Banner \(id)",
            startsAt: startsAt,
            endsAt: endsAt
        )
    }

    static func progress(
        seriesID: String,
        episodeIndex: Int,
        positionSec: Double = 45,
        durationSec: Double = 120,
        completed: Bool = false
    ) -> WatchProgress {
        WatchProgress(
            episodeId: EpisodeID("\(seriesID)_e\(episodeIndex)"),
            seriesId: SeriesID(seriesID),
            positionSec: positionSec,
            durationSec: durationSec,
            completed: completed,
            watchedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func page<T: Sendable>(_ items: [T], nextCursor: String? = nil, ttlSec: Int? = nil) -> Page<T> {
        Page(items: items, nextCursor: nextCursor, ttlSec: ttlSec)
    }
}
