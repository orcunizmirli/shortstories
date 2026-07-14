import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

@MainActor
@Suite("AramaModel")
struct AramaModelTests {
    private func makeModel(
        search: SpySearch = SpySearch(),
        recent: FakeRecentStore = FakeRecentStore(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: AramaDelegateSpy? = nil,
        source: AramaSource = .kesfet,
        initialQuery: String? = nil
    ) -> AramaModel {
        AramaModel(
            search: search,
            recentStore: recent,
            analytics: analytics,
            delegate: delegate,
            source: source,
            initialQuery: initialQuery,
            debounceInterval: .zero
        )
    }

    private func series(_ id: String, _ title: String = "Dizi") -> Series {
        Fixtures.series(id: id, title: title)
    }

    // MARK: - Boş durum

    @Test func onAppearTracksOpenAndLoadsRecent() {
        let analytics = MockAnalytics()
        let recent = FakeRecentStore(["ceo", "revenge"])
        let model = makeModel(recent: recent, analytics: analytics)

        model.onAppear()

        #expect(analytics.eventNames.contains("search_open"))
        #expect(model.recentSearches == ["ceo", "revenge"])
        #expect(model.phase == .browsing)
    }

    @Test func loadPopularPopulatesEmptyState() async {
        let search = SpySearch()
        search.setPopular(.success(["ceo romance", "revenge"]))
        let model = makeModel(search: search)

        await model.loadPopular()

        #expect(model.popularSearches == ["ceo romance", "revenge"])
    }

    // MARK: - Yazma / öneri debounce

    @Test func shortQueryStaysBrowsingWithoutSuggest() async {
        let search = SpySearch()
        let model = makeModel(search: search)

        model.queryChanged("m")
        await model.pendingWork()

        #expect(model.phase == .browsing)
        #expect(model.suggestions.isEmpty)
        #expect(search.suggestQueries.isEmpty)
    }

    @Test func debouncedSuggestPopulatesSuggestions() async {
        let search = SpySearch()
        let analytics = MockAnalytics()
        search.setSuggest(
            [SearchSuggestion(text: "midnight heir", kind: .series, seriesID: SeriesID("srs_mid001"))],
            for: "mid"
        )
        let model = makeModel(search: search, analytics: analytics)

        model.queryChanged("mid")
        await model.pendingWork()

        #expect(model.phase == .suggesting)
        #expect(model.suggestions.count == 1)
        let searchQuery = analytics.events.first { $0.name == "search_query" }
        #expect(searchQuery?.parameters["is_autocomplete"] == .bool(true))
    }

    @Test func onlyLatestQuerySuggestionApplied() async {
        let search = SpySearch()
        search.setSuggest([SearchSuggestion(text: "mid", kind: .query, seriesID: nil)], for: "mid")
        search.setSuggest([SearchSuggestion(text: "midn", kind: .query, seriesID: nil)], for: "midn")
        let model = makeModel(search: search)

        model.queryChanged("mid")
        model.queryChanged("midn") // önceki debounce iptal edilir
        await model.pendingWork()

        // Sıra-dışı yanıt savunması: yalnız en güncel sorgu istendi ve uygulandı.
        #expect(search.suggestQueries == ["midn"])
        #expect(model.suggestions.map(\.text) == ["midn"])
    }

    // MARK: - Sonuç ızgarası

    @Test func submitRunsSearchAndRecordsRecent() async {
        let search = SpySearch()
        let recent = FakeRecentStore()
        let analytics = MockAnalytics()
        search.setSearch(.success(Page(items: [series("srs_a11111"), series("srs_b22222")], nextCursor: "c2", ttlSec: nil)))
        let model = makeModel(search: search, recent: recent, analytics: analytics)

        model.queryChanged("midnight")
        model.submit()
        await model.pendingWork()

        #expect(model.phase == .results)
        #expect(model.results.count == 2)
        #expect(model.canLoadMore)
        #expect(recent.load() == ["midnight"])
        let searchQuery = analytics.events.first { $0.name == "search_query" && $0.parameters["is_autocomplete"] == .bool(false) }
        #expect(searchQuery?.parameters["result_count"] == .int(2))
    }

    @Test func submitEmptyIsIgnored() async {
        let search = SpySearch()
        let model = makeModel(search: search)
        model.queryChanged("   ")
        model.submit()
        await model.pendingWork()
        #expect(search.searchCalls.isEmpty)
    }

    @Test func noResultShowsEmptyStateAndTracks() async {
        let search = SpySearch()
        let analytics = MockAnalytics()
        search.setSearch(.success(Page(items: [], nextCursor: nil, ttlSec: nil)))
        let model = makeModel(search: search, analytics: analytics)

        await model.performSearch(query: "zzzz")

        #expect(model.phase == .noResult(query: "zzzz"))
        #expect(analytics.eventNames.contains("search_no_result"))
    }

    @Test func searchErrorSetsInlineError() async {
        let search = SpySearch()
        search.setSearch(.failure(.network(.timeout)))
        let model = makeModel(search: search)

        await model.performSearch(query: "midnight")

        #expect(model.hasResultsError)
        #expect(model.phase == .results)
    }

    @Test func loadMoreAppendsNextPage() async {
        let search = SpySearch()
        search.setSearch(.success(Page(items: [series("srs_a11111")], nextCursor: "c2", ttlSec: nil)), cursor: nil)
        search.setSearch(.success(Page(items: [series("srs_b22222")], nextCursor: nil, ttlSec: nil)), cursor: "c2")
        let model = makeModel(search: search)

        await model.performSearch(query: "midnight")
        #expect(model.canLoadMore)
        await model.loadMore()

        #expect(model.results.map(\.id.rawValue) == ["srs_a11111", "srs_b22222"])
        #expect(!model.canLoadMore)
    }

    // MARK: - Seçimler

    @Test func selectSeriesSuggestionNavigatesAndRecordsRecent() {
        let recent = FakeRecentStore()
        let delegate = AramaDelegateSpy()
        let model = makeModel(recent: recent, delegate: delegate)

        model.selectSuggestion(SearchSuggestion(text: "midnight heir", kind: .series, seriesID: SeriesID("srs_mid001")))

        #expect(delegate.selectedSeries == [SeriesID("srs_mid001")])
        #expect(recent.load() == ["midnight heir"])
    }

    @Test func selectQuerySuggestionRunsSearch() async {
        let search = SpySearch()
        search.setSearch(.success(Page(items: [series("srs_a11111")], nextCursor: nil, ttlSec: nil)))
        let model = makeModel(search: search)

        model.selectSuggestion(SearchSuggestion(text: "ceo", kind: .query, seriesID: nil))
        await model.pendingWork()

        #expect(model.phase == .results)
        #expect(search.searchCalls.first?.query == "ceo")
    }

    @Test func selectResultTracksAndNavigates() {
        let analytics = MockAnalytics()
        let delegate = AramaDelegateSpy()
        let model = makeModel(analytics: analytics, delegate: delegate)

        model.selectResult(series("srs_x99999"), position: 3)

        #expect(delegate.selectedSeries == [SeriesID("srs_x99999")])
        let tap = analytics.events.first { $0.name == "search_result_tap" }
        #expect(tap?.parameters["result_position"] == .int(3))
    }

    @Test func recentRemoveAndClear() {
        let recent = FakeRecentStore(["ceo", "revenge"])
        let model = makeModel(recent: recent)
        model.onAppear()

        model.removeRecent("ceo")
        #expect(model.recentSearches == ["revenge"])

        model.clearRecents()
        #expect(model.recentSearches.isEmpty)
    }

    @Test func cancelDismisses() {
        let delegate = AramaDelegateSpy()
        let model = makeModel(delegate: delegate)
        model.cancel()
        #expect(delegate.dismissed == 1)
    }

    @Test func initialQueryTriggersSearchOnAppear() async {
        let search = SpySearch()
        search.setSearch(.success(Page(items: [series("srs_a11111")], nextCursor: nil, ttlSec: nil)))
        let model = makeModel(search: search, source: .deeplink, initialQuery: "midnight")

        model.onAppear()
        await model.pendingWork()

        #expect(model.phase == .results)
        #expect(search.searchCalls.first?.query == "midnight")
    }

    // MARK: - Sıra-dışı yanıt yarışları (token/generation guard)

    private func makeRaceModel(search: any SearchServicing) -> AramaModel {
        AramaModel(
            search: search,
            recentStore: FakeRecentStore(),
            analytics: MockAnalytics(),
            delegate: nil,
            debounceInterval: .zero
        )
    }

    /// "ab" ağ turu askıdayken "cd" tamamlanır; üstü örtülen "ab" geç dönünce yeni sonucu
    /// EZMEMELİ ve iptal/supersede hatası banner boyamamalı.
    @Test func supersededSearchDoesNotOverwriteNewerResults() async {
        let search = GatedSearch(gatedKeys: [GatedSearch.key("ab", nil)])
        search.setResult(.success(Page(items: [series("srs_ab00001")], nextCursor: "ab_c2", ttlSec: nil)), query: "ab")
        search.setResult(.success(Page(items: [series("srs_cd00002")], nextCursor: "cd_c2", ttlSec: nil)), query: "cd")
        let model = makeRaceModel(search: search)

        async let ab: Void = model.performSearch(query: "ab")
        await search.gate.arrivals(GatedSearch.key("ab", nil), 1) // "ab" askıda
        await model.performSearch(query: "cd") // "cd" hemen tamamlanır, taze durum
        #expect(model.results.map(\.id.rawValue) == ["srs_cd00002"])

        search.gate.open(GatedSearch.key("ab", nil)) // eski "ab" geç döner
        await ab

        #expect(model.results.map(\.id.rawValue) == ["srs_cd00002"]) // "ab" ezmedi
        #expect(!model.hasResultsError) // supersede hatası banner boyamadı
        #expect(model.phase == .results)
    }

    /// "ab" sayfa-2 askıdayken kullanıcı "cd" gönderir; geç dönen "ab" sayfası "cd" listesine
    /// KARIŞMAMALI ve cursor'ı bozmamalı (çapraz-sorgu kirlenmesi).
    @Test func loadMoreDropsPageWhenQueryChangedMidFlight() async {
        let search = GatedSearch(gatedKeys: [GatedSearch.key("ab", "ab_c2")])
        search.setResult(.success(Page(items: [series("srs_ab00001")], nextCursor: "ab_c2", ttlSec: nil)), query: "ab")
        search.setResult(
            .success(Page(items: [series("srs_abpage2")], nextCursor: "ab_c3", ttlSec: nil)),
            query: "ab",
            cursor: "ab_c2"
        )
        search.setResult(.success(Page(items: [series("srs_cd00002")], nextCursor: nil, ttlSec: nil)), query: "cd")
        let model = makeRaceModel(search: search)

        await model.performSearch(query: "ab") // results=[ab], canLoadMore
        async let more: Void = model.loadMore() // "ab" sayfa-2 askıya alınır
        await search.gate.arrivals(GatedSearch.key("ab", "ab_c2"), 1)
        await model.performSearch(query: "cd") // yeni sorgu; results=[cd]

        search.gate.open(GatedSearch.key("ab", "ab_c2")) // "ab" sayfa-2 geç döner
        await more

        #expect(model.results.map(\.id.rawValue) == ["srs_cd00002"]) // karışma yok
        #expect(!model.canLoadMore) // cursor "cd"nin (nil); "ab" cursor'u sızmadı
    }
}
