import AppFoundation
import ContentKit
import Foundation
@testable import DiscoverKit

/// Programlanabilir `CatalogServicing` fake'i + çağrı sayacı (§5.3 kalıbı).
final class SpyCatalog: CatalogServicing, @unchecked Sendable {
    private let lock = NSLock()

    private var discoverResult: Result<DiscoverContent, AppError>
    private var seriesDetailResult: Result<Series, AppError>?
    private var episodesResult: Result<Page<Episode>, AppError>?
    private var episodesPages: [String?: Result<Page<Episode>, AppError>] = [:]
    private var collectionResult: Result<Page<Series>, AppError>?

    private(set) var discoverCallCount = 0
    private(set) var seriesDetailCallCount = 0
    private(set) var episodesCallCount = 0
    private(set) var lastEpisodesCursor: String??
    private(set) var episodesCursors: [String?] = []

    init(discover: Result<DiscoverContent, AppError> = .success(DiscoverContent(banners: [], collections: []))) {
        discoverResult = discover
    }

    func setDiscover(_ result: Result<DiscoverContent, AppError>) {
        lock.withLock { discoverResult = result }
    }

    func setSeriesDetail(_ result: Result<Series, AppError>) {
        lock.withLock { seriesDetailResult = result }
    }

    func setEpisodes(_ result: Result<Page<Episode>, AppError>) {
        lock.withLock { episodesResult = result }
    }

    /// Cursor'a özgü bölüm sayfası programlar (çok-sayfalı senaryolar). Belirli cursor için
    /// eşleşme varsa `episodesResult` yerine bu döner.
    func setEpisodesPage(_ result: Result<Page<Episode>, AppError>, cursor: String?) {
        lock.withLock { episodesPages[cursor] = result }
    }

    func setCollectionPage(_ result: Result<Page<Series>, AppError>) {
        lock.withLock { collectionResult = result }
    }

    func discover() async throws -> DiscoverContent {
        try lock.withLock {
            discoverCallCount += 1
            return try discoverResult.get()
        }
    }

    func seriesDetail(id: SeriesID) async throws -> Series {
        try lock.withLock {
            seriesDetailCallCount += 1
            guard let seriesDetailResult else {
                throw AppError.unexpected(underlying: "seriesDetail stub yok")
            }
            return try seriesDetailResult.get()
        }
    }

    func episodes(seriesId: SeriesID, cursor: String?) async throws -> Page<Episode> {
        try lock.withLock {
            episodesCallCount += 1
            lastEpisodesCursor = cursor
            episodesCursors.append(cursor)
            if let paged = episodesPages[cursor] {
                return try paged.get()
            }
            guard let episodesResult else {
                throw AppError.unexpected(underlying: "episodes stub yok")
            }
            return try episodesResult.get()
        }
    }

    func collectionPage(id: String, cursor: String?) async throws -> Page<Series> {
        try lock.withLock {
            guard let collectionResult else {
                throw AppError.unexpected(underlying: "collectionPage stub yok")
            }
            return try collectionResult.get()
        }
    }
}

/// Kesfet delegate spy'ı.
@MainActor
final class KesfetDelegateSpy: KesfetDelegate {
    var selectedSeries: [(id: SeriesID, shelfID: String?)] = []
    var openedRoutes: [DeepLinkRoute] = []
    var searchRequested = 0
    var seeAll: [(collectionID: String, title: String)] = []

    func kesfetDidSelectSeries(_ seriesID: SeriesID, shelfID: String?) {
        selectedSeries.append((seriesID, shelfID))
    }

    func kesfetDidOpenRoute(_ route: DeepLinkRoute) {
        openedRoutes.append(route)
    }

    func kesfetRequestsSearch() {
        searchRequested += 1
    }

    func kesfetDidSelectSeeAll(collectionID: String, title: String) {
        seeAll.append((collectionID, title))
    }
}
