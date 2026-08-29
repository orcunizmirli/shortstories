import AppFoundation
import ContentKit
import Testing
@testable import DiscoverKit

/// SS-033 / 04 §8.5 BolumListesi (player feed hızlı bölüm-değiştirici): bölüm listesi + kilit durumu
/// türetimi (free/unlocked/entitled → oynatılabilir), aktif-bölüm vurgusu, seçim/kapama niyetleri.
@MainActor
@Suite("BolumListesiModel — bölüm listesi + kilit türetimi")
struct BolumListesiModelTests {
    @MainActor
    final class DelegateSpy: BolumListesiDelegate {
        private(set) var selected: [(number: Int, series: SeriesID)] = []
        private(set) var dismissCount = 0
        func bolumListesiDidSelectEpisode(number: Int, in seriesID: SeriesID) {
            selected.append((number, seriesID))
        }

        func bolumListesiRequestsDismiss() {
            dismissCount += 1
        }
    }

    private func make(
        catalog: SpyCatalog,
        entitlement: FakeEntitlements = FakeEntitlements(),
        currentEpisodeID: EpisodeID? = nil,
        delegate: DelegateSpy = DelegateSpy()
    ) -> BolumListesiModel {
        BolumListesiModel(
            series: Fixtures.series(id: "s1", title: "Aşk"),
            currentEpisodeID: currentEpisodeID,
            catalog: catalog,
            entitlement: entitlement,
            delegate: delegate
        )
    }

    @Test func loadTuretirFreeOynatilabilirLockedDegil() async {
        let catalog = SpyCatalog()
        catalog.setEpisodes(.success(Page(items: [
            Fixtures.episode(seriesID: "s1", index: 1, access: .free),
            Fixtures.episode(seriesID: "s1", index: 2, access: .locked, unlockPrice: 50)
        ], nextCursor: nil, ttlSec: nil)))
        let model = make(catalog: catalog)

        await model.load()

        #expect(model.loadState == .loaded)
        #expect(model.rows.count == 2)
        #expect(model.rows[0].number == 1)
        #expect(model.rows[0].isPlayable) // free
        #expect(!model.rows[1].isPlayable) // locked + entitlement yok
    }

    @Test func vipEntitlementKilitliyiOynatilabilirYapar() async {
        let catalog = SpyCatalog()
        catalog.setEpisodes(.success(Page(items: [
            Fixtures.episode(seriesID: "s1", index: 2, access: .locked, unlockPrice: 50)
        ], nextCursor: nil, ttlSec: nil)))
        let model = make(catalog: catalog, entitlement: FakeEntitlements(isVIP: true))

        await model.load()

        #expect(model.rows[0].isPlayable) // VIP → entitled
    }

    @Test func acilmisBolumEntitlementIleOynatilabilir() async {
        let catalog = SpyCatalog()
        catalog.setEpisodes(.success(Page(items: [
            Fixtures.episode(seriesID: "s1", index: 3, access: .locked, unlockPrice: 50)
        ], nextCursor: nil, ttlSec: nil)))
        let entitlement = FakeEntitlements(unlocked: [EpisodeID("s1_e3")])
        let model = make(catalog: catalog, entitlement: entitlement)

        await model.load()

        #expect(model.rows[0].isPlayable) // daha önce açılmış
    }

    @Test func aktifBolumIsCurrentIleIsaretlenir() async {
        let catalog = SpyCatalog()
        catalog.setEpisodes(.success(Page(items: [
            Fixtures.episode(seriesID: "s1", index: 1, access: .free),
            Fixtures.episode(seriesID: "s1", index: 2, access: .free)
        ], nextCursor: nil, ttlSec: nil)))
        let model = make(catalog: catalog, currentEpisodeID: EpisodeID("s1_e2"))

        await model.load()

        #expect(!model.rows[0].isCurrent)
        #expect(model.rows[1].isCurrent)
    }

    @Test func fetchHatasiErrorDurumu() async {
        let catalog = SpyCatalog()
        catalog.setEpisodes(.failure(.network(.offline)))
        let model = make(catalog: catalog)

        await model.load()

        #expect(model.loadState == .error)
        #expect(model.rows.isEmpty)
    }

    @Test func selectEpisodeDelegateyeIletir() async {
        let catalog = SpyCatalog()
        catalog.setEpisodes(.success(Page(items: [
            Fixtures.episode(seriesID: "s1", index: 7, access: .free)
        ], nextCursor: nil, ttlSec: nil)))
        let delegate = DelegateSpy()
        let model = make(catalog: catalog, delegate: delegate)
        await model.load()

        model.selectEpisode(model.rows[0])

        #expect(delegate.selected.count == 1)
        #expect(delegate.selected[0].number == 7)
        #expect(delegate.selected[0].series == SeriesID("s1"))
    }

    @Test func dismissDelegateyeIletir() {
        let delegate = DelegateSpy()
        let model = make(catalog: SpyCatalog(), delegate: delegate)

        model.dismiss()

        #expect(delegate.dismissCount == 1)
    }
}
