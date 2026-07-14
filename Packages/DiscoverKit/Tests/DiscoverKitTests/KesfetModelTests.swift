import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Observation
import Testing
@testable import DiscoverKit

@MainActor
@Suite("KesfetModel")
struct KesfetModelTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContent(banner: String = "b1") -> DiscoverContent {
        DiscoverContent(
            banners: [Fixtures.banner(id: banner)],
            collections: [
                Fixtures.collection(
                    id: "trend",
                    kind: .trending,
                    title: "Trend",
                    series: [
                        Fixtures.series(id: "srs_rom001", genres: ["romance"]),
                        Fixtures.series(id: "srs_act001", genres: ["action"])
                    ]
                )
            ]
        )
    }

    private func makeModel(
        catalog: SpyCatalog,
        session: DiscoverSessionStore = DiscoverSessionStore(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: KesfetDelegateSpy? = nil
    ) -> KesfetModel {
        KesfetModel(
            catalog: catalog,
            session: session,
            analytics: analytics,
            delegate: delegate,
            now: { now }
        )
    }

    @Test func loadWithoutCacheFetchesAndStores() async {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let session = DiscoverSessionStore()
        let model = makeModel(catalog: catalog, session: session)

        await model.load()

        #expect(model.loadState == .loaded)
        #expect(catalog.discoverCallCount == 1)
        #expect(model.content != nil)
        #expect(session.cached != nil)
        #expect(model.composition.shelves.count == 1)
    }

    @Test func freshCacheSkipsNetwork() async {
        let catalog = SpyCatalog(discover: .success(makeContent(banner: "fromNetwork")))
        let session = DiscoverSessionStore(
            cached: CachedDiscover(content: makeContent(banner: "fromCache"), storedAt: now.addingTimeInterval(-10))
        )
        let model = makeModel(catalog: catalog, session: session)

        await model.load()

        #expect(model.loadState == .loaded)
        #expect(catalog.discoverCallCount == 0) // taze cache → ağ turu yok
        #expect(model.composition.banners.first?.id == "fromCache")
    }

    @Test func staleCacheShownThenRevalidated() async {
        let catalog = SpyCatalog(discover: .success(makeContent(banner: "fromNetwork")))
        let session = DiscoverSessionStore(
            cached: CachedDiscover(content: makeContent(banner: "fromCache"), storedAt: now.addingTimeInterval(-1000))
        )
        let model = makeModel(catalog: catalog, session: session)

        await model.load()

        #expect(catalog.discoverCallCount == 1) // bayat → revalidate
        #expect(model.composition.banners.first?.id == "fromNetwork") // taze içerik geldi
    }

    @Test func refreshAlwaysRevalidatesEvenWhenFresh() async {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let analytics = MockAnalytics()
        let session = DiscoverSessionStore(
            cached: CachedDiscover(content: makeContent(), storedAt: now.addingTimeInterval(-10))
        )
        let model = makeModel(catalog: catalog, session: session, analytics: analytics)

        await model.load()
        #expect(catalog.discoverCallCount == 0)
        await model.refresh()

        #expect(catalog.discoverCallCount == 1)
        #expect(analytics.eventNames.contains("discover_refreshed"))
    }

    @Test func offlineWithoutCacheShowsOfflineState() async {
        let catalog = SpyCatalog(discover: .failure(.network(.offline)))
        let model = makeModel(catalog: catalog)

        await model.load()

        #expect(model.loadState == .offline)
        #expect(!model.showsOfflineBanner)
    }

    @Test func offlineWithCacheKeepsContentAndShowsBanner() async {
        let catalog = SpyCatalog(discover: .failure(.network(.offline)))
        let session = DiscoverSessionStore(
            cached: CachedDiscover(content: makeContent(), storedAt: now.addingTimeInterval(-1000))
        )
        let model = makeModel(catalog: catalog, session: session)

        await model.load()

        #expect(model.loadState == .loaded)
        #expect(model.showsOfflineBanner)
        #expect(model.content != nil)
    }

    @Test func serverErrorWithoutCacheShowsError() async {
        let catalog = SpyCatalog(discover: .failure(.network(.server(status: 500))))
        let model = makeModel(catalog: catalog)

        await model.load()

        #expect(model.loadState == .error)
    }

    @Test func selectGenrePersistsAndFilters() async {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let analytics = MockAnalytics()
        let session = DiscoverSessionStore()
        let model = makeModel(catalog: catalog, session: session, analytics: analytics)
        await model.load()

        model.selectGenre("romance")

        #expect(session.selectedGenreID == "romance")
        #expect(model.selectedGenreID == "romance")
        #expect(model.composition.shelves.allSatisfy { $0.series.allSatisfy { $0.genres.contains { $0.id == "romance" } } })
        #expect(analytics.eventNames.contains("genre_filter_selected"))
        // İstemci-içi filtre: yeni ağ turu YOK.
        #expect(catalog.discoverCallCount == 1)
    }

    @Test func filterPersistsAcrossModelRecreation() async {
        let session = DiscoverSessionStore()
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let first = makeModel(catalog: catalog, session: session)
        await first.load()
        first.selectGenre("action")

        // Aynı oturum store'u ile yeni model — filtre korunur.
        let second = makeModel(catalog: catalog, session: session)
        #expect(second.selectedGenreID == "action")
    }

    @Test func selectSeriesInvokesDelegateAndAnalytics() async {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let analytics = MockAnalytics()
        let delegate = KesfetDelegateSpy()
        let model = makeModel(catalog: catalog, analytics: analytics, delegate: delegate)
        await model.load()
        let series = model.composition.shelves[0].series[0]

        model.selectSeries(series, shelfID: "trend", position: 0)

        #expect(delegate.selectedSeries.first?.id == series.id)
        #expect(analytics.eventNames.contains("discover_card_tapped"))
    }

    @Test func selectBannerResolvesDeepLink() {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let delegate = KesfetDelegateSpy()
        let model = makeModel(catalog: catalog, delegate: delegate)
        let banner = Fixtures.banner(id: "b", deeplink: "shortseries://store/coins?offer=launch")

        model.selectBanner(banner, position: 1)

        #expect(delegate.openedRoutes == [.coinStore(offer: "launch")])
    }

    @Test func selectBannerInvalidDeepLinkFallsBackToHome() {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let analytics = MockAnalytics()
        let delegate = KesfetDelegateSpy()
        let model = makeModel(catalog: catalog, analytics: analytics, delegate: delegate)
        let banner = Fixtures.banner(id: "b", deeplink: "shortseries://unknown/path")

        model.selectBanner(banner, position: 0)

        #expect(delegate.openedRoutes == [.home])
        #expect(analytics.eventNames.contains("deeplink_fallback"))
    }

    @Test func seeAllAndSearchDelegates() async {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let analytics = MockAnalytics()
        let delegate = KesfetDelegateSpy()
        let model = makeModel(catalog: catalog, analytics: analytics, delegate: delegate)
        await model.load()

        model.selectSeeAll(shelf: model.composition.shelves[0])
        model.openSearch()

        #expect(delegate.seeAll.first?.collectionID == "trend")
        #expect(delegate.searchRequested == 1)
        #expect(analytics.eventNames.contains("discover_shelf_see_all"))
    }

    @Test func screenViewTrackedOnce() async {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let analytics = MockAnalytics()
        let model = makeModel(catalog: catalog, analytics: analytics)

        await model.load()
        await model.load()

        #expect(analytics.eventNames.filter { $0 == "screen_view" }.count == 1)
    }

    // MARK: - Tür filtresi Observation grafiği (SS-071/074)

    /// selectGenre, @Observable grafiğinde bir değişiklik yaymalı ki View filtreye canlı
    /// tepki versin (state session store'da değil, model'de yaşamalı).
    @Test func selectGenreNotifiesObservers() async {
        let catalog = SpyCatalog(discover: .success(makeContent()))
        let model = makeModel(catalog: catalog)
        await model.load()

        let notified = TestFlag()
        withObservationTracking {
            _ = model.selectedGenreID
        } onChange: {
            notified.value = true
        }

        model.selectGenre("romance")
        #expect(notified.value)
    }

    // MARK: - revalidate yarışı (token guard)

    /// Eşzamanlı iki revalidate'te geç dönen BAYAT yanıt, önce dönen TAZE yanıtı ezmemeli ve
    /// TTL'i bayat zaman damgasıyla sıfırlamamalı.
    @Test func staleRevalidateDoesNotClobberFreshOrResetCache() async {
        let staleContent = makeContent(banner: "stale")
        let freshContent = makeContent(banner: "fresh")
        let catalog = GatedCatalog(discoverResults: [.success(staleContent), .success(freshContent)])
        let session = DiscoverSessionStore(
            cached: CachedDiscover(content: makeContent(banner: "cache"), storedAt: now.addingTimeInterval(-1000))
        )
        let model = KesfetModel(
            catalog: catalog,
            session: session,
            analytics: MockAnalytics(),
            delegate: nil,
            now: { now }
        )

        async let load: Void = model.load() // R1 (bayat), önce başlar
        await catalog.gate.arrivals("0", 1)
        async let refresh: Void = model.refresh() // R2 (taze), sonra başlar
        await catalog.gate.arrivals("1", 1)

        catalog.gate.open("1") // R2 önce tamamlanır → taze
        await refresh
        #expect(model.composition.banners.first?.id == "fresh")

        catalog.gate.open("0") // R1 (bayat) sonra tamamlanır
        await load

        #expect(model.composition.banners.first?.id == "fresh") // bayat ezmedi
        #expect(session.cached?.content.banners.first?.id == "fresh") // TTL bayatla sıfırlanmadı
    }

    @Test func discoverTTLMatchesSpec() {
        // 05 §7.2: /discover için max-age=600.
        #expect(CacheFreshness.discoverTTL == .seconds(600))
    }
}
