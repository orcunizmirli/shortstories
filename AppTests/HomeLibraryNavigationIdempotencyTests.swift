import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import PlayerKit
import XCTest
@testable import ShortSeriesApp

/// FINDING 3 (App-integration hunt): Home & Library detay push'u çift-dokunuşta IDEMPOTENT olmalı — aynı
/// DiziDetay İKİ KEZ push edilmemeli (çift ekran + çift Geri). Discover/Profile zaten `appendIfNotTop` guard'lı;
/// bu test Home/Library'yi de aynı desene (`path: [AppRoute]` + `appendIfNotTop`) getirir. Coordinator-seviyesi
/// (pure seam değil): metodların gerçekten idempotent push ettiğini doğrular. App target CI dışı → yerel.
@MainActor
final class HomeLibraryNavigationIdempotencyTests: XCTestCase {
    func testLibraryOpenDetailIsIdempotentOnDoubleTap() throws {
        let tab = try makeTab()
        tab.library.listemOpenDetail(seriesID: SeriesID("s1"))
        tab.library.listemOpenDetail(seriesID: SeriesID("s1")) // çift-dokunuş
        XCTAssertEqual(tab.library.path.count, 1, "aynı dizi çift-dokunuşta tek push (idempotent)")
    }

    func testLibraryOpenDetailStacksDistinctSeries() throws {
        let tab = try makeTab()
        tab.library.listemOpenDetail(seriesID: SeriesID("s1"))
        tab.library.listemOpenDetail(seriesID: SeriesID("s2"))
        XCTAssertEqual(tab.library.path.count, 2, "farklı dizi her zaman push edilir (guard genel push'u kırmaz)")
    }

    func testHomeSeriesDetailIsIdempotentOnDoubleTap() throws {
        let tab = try makeTab()
        let vc = makeFeedVC(tab.home)
        let series = makeSeries("s1")
        tab.home.playerFeed(vc, didRequestSeriesDetail: series)
        tab.home.playerFeed(vc, didRequestSeriesDetail: series) // çift-dokunuş
        XCTAssertEqual(tab.home.path.count, 1, "aynı dizi çift-dokunuşta tek push (idempotent)")
    }

    func testHomeSeriesDetailStacksDistinctSeries() throws {
        let tab = try makeTab()
        let vc = makeFeedVC(tab.home)
        tab.home.playerFeed(vc, didRequestSeriesDetail: makeSeries("s1"))
        tab.home.playerFeed(vc, didRequestSeriesDetail: makeSeries("s2"))
        XCTAssertEqual(tab.home.path.count, 2, "farklı dizi her zaman push edilir (guard genel push'u kırmaz)")
    }

    // MARK: - Fixtures

    private func makeTab() throws -> TabCoordinator {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        return try TabCoordinator(composition: AppComposition(dependencies: PreviewDependencies(session: session)))
    }

    private func makeFeedVC(_ home: HomeCoordinator) -> PlayerFeedViewController {
        PlayerFeedViewController(
            viewModel: home.feedViewModel,
            playerPool: home.playerPool,
            prefetch: home.prefetch,
            analytics: MockAnalytics()
        )
    }

    private func makeSeries(_ id: String) -> Series {
        Series(
            id: SeriesID(id),
            title: "Dizi \(id)",
            synopsis: "…",
            coverURL: URL(string: "https://cdn.example.com/\(id).jpg")!,
            bannerURL: nil,
            genres: [],
            tags: [],
            episodeCount: 10,
            releasedEpisodeCount: 10,
            freeEpisodeCount: 3,
            releaseState: .completed,
            nextEpisodeAt: nil,
            stats: SeriesStats(viewCount: 0, favoriteCount: 0, trendingRank: nil),
            localeInfo: LocaleInfo(audioLanguage: "en", subtitleLanguages: ["en"]),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
