import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

/// DiziDetayModel'in sayfalı-ilerleme + favori eşzamanlılığı + onAppear re-entrancy + boş durum
/// CTA türetimleri (review/spec bulguları). Ana suite'ten ayrı tutulur (dosya boyutu).
@MainActor
@Suite("DiziDetayModel concurrency")
struct DiziDetayModelConcurrencyTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let seriesID = SeriesID("srs_abc123")

    private func makeSeries() -> Series {
        Fixtures.series(
            id: "srs_abc123",
            title: "Gece Yarısı",
            tags: ["revenge"],
            episodeCount: 60,
            releasedEpisodeCount: 8,
            freeEpisodeCount: 5
        )
    }

    private func makeEpisodes() -> [Episode] {
        (1 ... 8).map { index in
            let free = index <= 5
            return Fixtures.episode(
                seriesID: "srs_abc123",
                index: index,
                access: free ? .free : .locked,
                unlockPrice: free ? nil : 70,
                publishedAt: Date(timeIntervalSince1970: 1_600_000_000)
            )
        }
    }

    private func longSeries(episodeCount: Int, released: Int) -> Series {
        Fixtures.series(
            id: "srs_abc123",
            title: "Uzun Dizi",
            episodeCount: episodeCount,
            releasedEpisodeCount: released,
            freeEpisodeCount: episodeCount
        )
    }

    private func freeEpisodes(_ range: ClosedRange<Int>) -> [Episode] {
        range.map { Fixtures.episode(seriesID: "srs_abc123", index: $0, access: .free) }
    }

    private func makeModel(
        catalog: any CatalogServicing,
        history: FakeHistory = FakeHistory(),
        favorites: any FavoritesGateway = FakeFavorites(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: DiziDetayDelegateSpy? = nil
    ) -> DiziDetayModel {
        DiziDetayModel(
            seriesID: seriesID,
            source: .kesfet,
            catalog: catalog,
            history: history,
            favorites: favorites,
            entitlement: FakeEntitlements(),
            analytics: analytics,
            delegate: delegate,
            now: { now }
        )
    }

    private func loadedCatalog() -> SpyCatalog {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(makeSeries()))
        spy.setEpisodes(.success(Page(items: makeEpisodes(), nextCursor: nil, ttlSec: nil)))
        return spy
    }

    // MARK: - Sayfalı ilerleme / CTA türetimi

    /// İzleme ilerlemesi ilk sayfanın dışındaki bir bölümdeyse (45. bölüm; 1. sayfa 1-20),
    /// model ilerleme bölümünün sayfasını çekip CTA'yı doğru türetmeli (Devam Et · Bölüm 45),
    /// baştan-başlat'a DÜŞMEMELİ.
    @Test func continueTargetResolvesAcrossPaginatedEpisodes() async {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(longSeries(episodeCount: 100, released: 100)))
        spy.setEpisodesPage(.success(Page(items: freeEpisodes(1 ... 20), nextCursor: "p2", ttlSec: nil)), cursor: nil)
        spy.setEpisodesPage(.success(Page(items: freeEpisodes(21 ... 40), nextCursor: "p3", ttlSec: nil)), cursor: "p2")
        spy.setEpisodesPage(.success(Page(items: freeEpisodes(41 ... 60), nextCursor: "p4", ttlSec: nil)), cursor: "p3")
        let history = FakeHistory(progress: Fixtures.progress(
            seriesID: "srs_abc123",
            episodeIndex: 45,
            positionSec: 30,
            completed: false
        ))
        let delegate = DiziDetayDelegateSpy()
        let model = makeModel(catalog: spy, history: history, delegate: delegate)

        await model.load()

        #expect(model.ctaTarget?.kind == .resume)
        #expect(model.ctaTarget?.episodeNumber == 45)
        #expect(model.ctaTarget?.startPositionSec == 30)

        model.primaryCTA()
        #expect(delegate.started.first?.episodeNumber == 45)
        #expect(delegate.started.first?.position == 30)
    }

    // MARK: - Favori eşzamanlılığı

    /// Örtüşen toggle'lar tekilleşmeli (in-flight guard): ilk toggle sunucuda askıdayken
    /// ikinci dokunuş sunucuya ikinci yazım yapmamalı ve durumu geri çevirmemeli.
    @Test func overlappingToggleFavoriteIsCoalesced() async {
        let favorites = GatedFavorites()
        let model = makeModel(catalog: loadedCatalog(), favorites: favorites)
        await model.load()
        #expect(!model.isFavorite)

        async let first: Void = model.toggleFavorite() // target=true, setFavorite askıda
        await favorites.gate.arrivals("0", 1)
        await model.toggleFavorite() // ikinci dokunuş: in-flight guard düşürmeli

        #expect(model.isFavorite) // geri çevrilmedi
        #expect(favorites.setCallCount == 1) // tek sunucu yazımı

        favorites.gate.open("0")
        await first
        #expect(model.isFavorite)
        #expect(favorites.setCallCount == 1)
    }

    /// 08 §3.3: favorite_add/remove event'i sunucu ONAYINDA atılır; setFavorite hata verirse
    /// event ÜRETİLMEMELİ (yanlış dönüşüm metriği önlenir).
    @Test func favoriteEventEmittedOnlyOnServerConfirmation() async {
        let favorites = FakeFavorites(failOnSet: true)
        let analytics = MockAnalytics()
        let model = makeModel(catalog: loadedCatalog(), favorites: favorites, analytics: analytics)
        await model.load()

        await model.toggleFavorite()

        #expect(!model.isFavorite) // geri alındı
        #expect(!analytics.eventNames.contains("favorite_add")) // onay yok → event yok
    }

    // MARK: - onAppear re-entrancy

    /// Tekrar görünümde (sheet/push dönüşü) load() bölümleri/cursor'ı/scroll'u EZMEMELİ:
    /// appeared guard ikinci yüklemeyi engeller.
    @Test func onAppearReentryPreservesPaginatedState() async {
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(makeSeries()))
        spy.setEpisodesPage(.success(Page(items: makeEpisodes(), nextCursor: "c2", ttlSec: nil)), cursor: nil)
        spy.setEpisodesPage(
            .success(Page(
                items: [Fixtures.episode(seriesID: "srs_abc123", index: 9, access: .free)],
                nextCursor: nil,
                ttlSec: nil
            )),
            cursor: "c2"
        )
        let model = makeModel(catalog: spy)

        model.onAppear()
        await model.pendingWork()
        #expect(spy.seriesDetailCallCount == 1)
        #expect(model.episodes.count == 8)

        await model.loadMoreEpisodes() // kullanıcı sayfaladı → 9 bölüm
        #expect(model.episodes.count == 9)

        model.onAppear() // tekrar görünüm
        await model.pendingWork()

        #expect(spy.seriesDetailCallCount == 1) // yeniden yükleme YOK
        #expect(model.episodes.count == 9) // sayfalama korundu
    }

    // MARK: - Boş durum CTA (02 §4.4)

    @Test func openDiscoverRoutesToDiscoverRoot() {
        let delegate = DiziDetayDelegateSpy()
        let model = makeModel(catalog: loadedCatalog(), delegate: delegate)

        model.openDiscover()

        #expect(delegate.discoverRootRequested == 1)
    }
}
