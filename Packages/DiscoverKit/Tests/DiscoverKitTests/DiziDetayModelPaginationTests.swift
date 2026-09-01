import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

/// DiziDetayModel bölüm-sayfalama + ilerleme-sayfası dayanıklılık (DiscoverKit bug-hunt): geçici sayfa
/// hatası sessizce yanlış CTA üretmemeli, boş+non-nil cursor sonsuz sayfalama yapmamalı.
@MainActor
@Suite("DiziDetayModel sayfalama dayanıklılık")
struct DiziDetayModelPaginationTests {
    private let seriesID = SeriesID("srs_abc123")
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeModel(catalog: SpyCatalog, history: FakeHistory = FakeHistory()) -> DiziDetayModel {
        DiziDetayModel(
            seriesID: seriesID,
            source: .kesfet,
            catalog: catalog,
            history: history,
            favorites: FakeFavorites(),
            entitlement: FakeEntitlements(),
            analytics: MockAnalytics(),
            delegate: nil,
            now: { now }
        )
    }

    private func freePage(_ range: ClosedRange<Int>) -> [Episode] {
        range.map { Fixtures.episode(seriesID: "srs_abc123", index: $0, access: .free, unlockPrice: nil) }
    }

    @Test func derinIlerlemeSayfasiHatasiEkraniBozmaz() async {
        // self-review: ilerleme bölümü (Bölüm 45, sayfa 2) sayfasının GEÇİCİ hatası tüm ekranı bozMAMALI
        // (canlı dizi .removed/.error dead-end'ine düşmemeli). Best-effort yutulur → dizi .loaded görünür
        // (CTA .start'a düşer — kabul-LOW; PREP: doğru fix episodeId-resume). page1 ızgarası izlenebilir kalır.
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(Fixtures.series(
            id: "srs_abc123", episodeCount: 60, releasedEpisodeCount: 60, freeEpisodeCount: 60
        )))
        spy.setEpisodes(.success(Page(items: freePage(1 ... 20), nextCursor: "p2", ttlSec: nil)))
        spy.setEpisodesPage(.failure(.content(.notFound)), cursor: "p2") // derin-sayfa 404 (bayat cursor)
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 45, completed: false))
        let model = makeModel(catalog: spy, history: history)

        await model.load()

        #expect(model.loadState == .loaded) // canlı dizi .removed dead-end'ine DÜŞMEZ
        #expect(model.episodes.count == 20) // page1 ızgarası izlenebilir
    }

    @Test func loadMoreBosSayfaNonNilCursorDaSonsuzSayfalamaYapmaz() async {
        // #4: sunucu Page(items:[], nextCursor:"p2") dönerse cursor nil'lenmezse her scroll-sonu loadMore
        // SONSUZ yeniden tetikler (AramaModel.loadMore ile simetrik guard eksikti).
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(Fixtures.series(
            id: "srs_abc123", episodeCount: 60, releasedEpisodeCount: 60, freeEpisodeCount: 60
        )))
        spy.setEpisodes(.success(Page(items: freePage(1 ... 20), nextCursor: "p2", ttlSec: nil)))
        spy.setEpisodesPage(.success(Page(items: [], nextCursor: "p2", ttlSec: nil)), cursor: "p2") // boş + self-cursor
        let model = makeModel(catalog: spy) // default FakeHistory (progress yok → load p2 çekmez)
        await model.load()

        await model.loadMoreEpisodes() // boş p2 → cursor nil'lenmeli
        let afterFirst = spy.episodesCursors.count
        await model.loadMoreEpisodes() // cursor nil → NO-OP (fetch yok)
        #expect(spy.episodesCursors.count == afterFirst) // ikinci loadMore fetch yapmadı (sonsuz sayfalama yok)
    }

    @Test func ensureEpisodeLoadedBosSayfaNonNilCursorDaSonsuzSayfalamaYapmaz() async {
        // MEDIUM (DiscoverKit hunt): recompute() CTA hedef bölümünü ileri sayfalarken (ensureEpisodeLoaded)
        // sunucu Page(items:[], nextCursor:"p3") dönerse cursor nil'lenmezse döngü sınırsız fetch atar + load()
        // kalıcı .loading'de kalır. Kardeşleri (load/ensureProgress/loadMore) boş-sayfa guard'ına sahipti, bu değildi.
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(Fixtures.series(
            id: "srs_abc123", episodeCount: 60, releasedEpisodeCount: 60, freeEpisodeCount: 60
        )))
        spy.setEpisodesPage(.success(Page(items: freePage(1 ... 20), nextCursor: "p2", ttlSec: nil)), cursor: nil)
        spy.setEpisodesPage(.success(Page(items: [], nextCursor: "p3", ttlSec: nil)), cursor: "p2") // boş + ilerleyen cursor
        // Son izlenen (20) TAMAMLANMIŞ → CTA hedefi 21 (yüklü değil) → ensureEpisodeLoaded ileri sayfalar.
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 20, completed: true))
        let model = makeModel(catalog: spy, history: history)

        await model.load()

        #expect(model.loadState == .loaded) // kalıcı .loading'e DÜŞMEZ
        #expect(!spy.episodesCursors.contains("p3")) // boş sayfa "liste sonu" → "p3" HİÇ istenmedi (sonsuz sayfalama yok)
    }
}
