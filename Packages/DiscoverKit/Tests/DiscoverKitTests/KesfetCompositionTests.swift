import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

@Suite("KesfetComposition")
struct KesfetCompositionTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func content() -> DiscoverContent {
        let romance = Fixtures.series(id: "srs_rom001", title: "Aşk", genres: ["romance"])
        let action = Fixtures.series(id: "srs_act001", title: "Aksiyon", genres: ["action"])
        let both = Fixtures.series(id: "srs_mix001", title: "Karışık", genres: ["romance", "action"])
        return DiscoverContent(
            banners: [Fixtures.banner(id: "b1")],
            collections: [
                Fixtures.collection(id: "trend", kind: .trending, title: "Trend", series: [romance, action, both]),
                Fixtures.collection(id: "new", kind: .new, title: "Yeni", series: [action])
            ]
        )
    }

    @Test func noFilterKeepsAllShelvesAndBanners() {
        let composition = KesfetComposition.compose(content: content(), selectedGenreID: nil, now: now)
        #expect(composition.shelves.count == 2)
        #expect(composition.shelves[0].series.count == 3)
        #expect(composition.banners.count == 1)
        #expect(!composition.hasActiveFilter)
        #expect(!composition.isFilteredEmpty)
    }

    @Test func genreFilterKeepsMatchingSeriesAndDropsEmptyShelves() {
        let composition = KesfetComposition.compose(content: content(), selectedGenreID: "romance", now: now)
        // Trend rafı: romance + mix (2); Yeni rafı yalnız action → düşer.
        #expect(composition.shelves.count == 1)
        #expect(composition.shelves[0].id == "trend")
        #expect(composition.shelves[0].series.map(\.id.rawValue) == ["srs_rom001", "srs_mix001"])
    }

    @Test func filterHidesBanners() {
        let composition = KesfetComposition.compose(content: content(), selectedGenreID: "romance", now: now)
        #expect(composition.banners.isEmpty)
    }

    @Test func expiredBannerFilteredOut() {
        let expired = Fixtures.banner(
            id: "old",
            startsAt: Date(timeIntervalSince1970: 1_000_000_000),
            endsAt: Date(timeIntervalSince1970: 1_100_000_000)
        )
        let live = Fixtures.banner(id: "live")
        let content = DiscoverContent(
            banners: [expired, live],
            collections: [Fixtures.collection(id: "c", series: [Fixtures.series(id: "srs_abc123")])]
        )
        let composition = KesfetComposition.compose(content: content, selectedGenreID: nil, now: now)
        #expect(composition.banners.map(\.id) == ["live"])
    }

    @Test func availableGenresAreUnionInFirstSeenOrder() {
        let composition = KesfetComposition.compose(content: content(), selectedGenreID: nil, now: now)
        #expect(composition.availableGenres.map(\.id) == ["romance", "action"])
    }

    @Test func filteredEmptyWhenNoSeriesMatch() {
        let composition = KesfetComposition.compose(content: content(), selectedGenreID: "horror", now: now)
        #expect(composition.isEmpty)
        #expect(composition.isFilteredEmpty)
        // Çip listesi boş sonuçta bile korunur (kullanıcı geri dönebilir).
        #expect(composition.availableGenres.map(\.id) == ["romance", "action"])
    }

    @Test func top10ShelfShowsRankBadges() {
        let content = DiscoverContent(
            banners: [],
            collections: [Fixtures.collection(
                id: "top",
                kind: .top10,
                title: "Top 10",
                series: [Fixtures.series(id: "srs_abc123")]
            )]
        )
        let composition = KesfetComposition.compose(content: content, selectedGenreID: nil, now: now)
        #expect(composition.shelves[0].showsRankBadges)
    }

    @Test func emptyCompositionKeepsSelectedFilter() {
        let composition = KesfetComposition.empty(selectedGenreID: "romance")
        #expect(composition.isEmpty)
        #expect(composition.selectedGenreID == "romance")
        // Filtre yokken boşluk "filtre boşluğu" değildir.
        #expect(KesfetComposition.empty(selectedGenreID: nil).isFilteredEmpty == false)
    }
}

@Suite("CacheFreshness")
struct CacheFreshnessTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func freshWithinTTL() {
        let stored = now.addingTimeInterval(-10)
        #expect(CacheFreshness.isFresh(storedAt: stored, ttl: .seconds(300), now: now))
    }

    @Test func staleAfterTTL() {
        let stored = now.addingTimeInterval(-301)
        #expect(!CacheFreshness.isFresh(storedAt: stored, ttl: .seconds(300), now: now))
    }

    @Test func futureStoredAtTreatedFresh() {
        let stored = now.addingTimeInterval(60)
        #expect(CacheFreshness.isFresh(storedAt: stored, ttl: .seconds(300), now: now))
    }
}
