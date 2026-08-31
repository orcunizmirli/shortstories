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

    @Test func gecicIlerlemeSayfasiHatasiYanlisStartCTAYerineLoadHatasiVerir() async {
        // #3: ilerleme bölümü (Bölüm 45, sayfa 2) sayfasının GEÇİCİ ağ hatası eskiden `try?` ile yutulup
        // resolve'u sessizce .start (Bölüm 1)'e düşürüyordu (kullanıcı kaldığı yeri kaybeder, loadState .loaded
        // kalıyordu). Fix: hata YÜZER → load .offline gösterir (retry).
        let spy = SpyCatalog()
        spy.setSeriesDetail(.success(Fixtures.series(
            id: "srs_abc123", episodeCount: 60, releasedEpisodeCount: 60, freeEpisodeCount: 60
        )))
        spy.setEpisodes(.success(Page(items: freePage(1 ... 20), nextCursor: "p2", ttlSec: nil)))
        spy.setEpisodesPage(.failure(.network(.offline)), cursor: "p2") // ilerleme sayfası GEÇİCİ hata
        let history = FakeHistory(progress: Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 45, completed: false))
        let model = makeModel(catalog: spy, history: history)

        await model.load()

        #expect(model.loadState == .offline) // yanlış .start CTA yerine retry (eskiden .loaded + Bölüm 1 idi)
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
}
