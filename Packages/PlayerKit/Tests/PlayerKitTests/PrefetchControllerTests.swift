import AppFoundation
import Foundation
import Testing
@testable import PlayerKit

/// PrefetchController akış testleri (04 §5.4, SS-042): pencere değişiminde ısındırma,
/// hedef dışı task iptali ve veri tasarrufunda tam durdurma. Havuz yerine kayıt tutan
/// sahte warmer kullanılır; gerçek indirme yoktur.
struct PrefetchControllerTests {
    private func makeController(
        warmer: RecordingWarmer = RecordingWarmer(),
        network: NetworkCondition = .wifi,
        dataSaver: Bool = false,
        poolSize: Int = 3
    ) -> (PrefetchController, RecordingWarmer) {
        let controller = PrefetchController(
            warmer: warmer,
            network: FakeNetworkProvider(network),
            preferences: FakePreferences(dataSaverEnabled: dataSaver),
            poolSize: poolSize
        )
        return (controller, warmer)
    }

    @Test func pencereDegisinceSonrakiBolumIsindirilir() async {
        let (controller, warmer) = makeController()
        let episodes = Fixture.episodes(count: 10)

        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()

        #expect(warmer.warmedIDs == [EpisodeID("e6")])
        #expect(warmer.warmedFeedIndexes == [6])
    }

    /// PREP §6 (LOW): GEÇİCİ hata alan warm "tamamlandı" SAYILMAMALI → completedWarmups'a eklenmez →
    /// bölüm pencere-içi kaldıkça yeniden ısındırılabilir (ağ dönünce cold-start spinner önlenir).
    @Test func geciciHataAlanWarmPencereIciYenidenDenenir() async {
        let warmer = RecordingWarmer()
        warmer.setFailing([EpisodeID("e6")]) // e6 warm'ı geçici hata (false) döner
        let (controller, _) = makeController(warmer: warmer)
        let episodes = Fixture.episodes(count: 10)

        // 1. pencere: e6 warm edilir ama geçici hata → completedWarmups'a EKLENMEZ.
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()
        #expect(warmer.warmedIDs == [EpisodeID("e6")])

        // 2. pencere (aynı hedef): e6 completedWarmups'ta OLMADIĞINDAN YENİDEN warm edilir.
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()
        #expect(warmer.warmedIDs == [EpisodeID("e6"), EpisodeID("e6")]) // retry (fix'siz: tek [e6])
    }

    /// Regresyon koruması: BAŞARILI warm idempotent kalır (completedWarmups → aynı pencerede tekrar warm YOK).
    @Test func basariliWarmYenidenDenenmez() async {
        let (controller, warmer) = makeController()
        let episodes = Fixture.episodes(count: 10)

        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()

        #expect(warmer.warmedIDs == [EpisodeID("e6")]) // tek deneme (idempotent korundu)
    }

    @Test func geriYondeOncekiBolumIsindirilir() async {
        let (controller, warmer) = makeController(poolSize: 4)
        let episodes = Fixture.episodes(count: 10)

        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .backward)
        await controller.awaitPendingWarmups()

        #expect(warmer.warmedIDs == [EpisodeID("e4"), EpisodeID("e3")])
    }

    @Test func veriTasarrufundaHicbirSeyIsinmaz() async {
        let (controller, warmer) = makeController(dataSaver: true)
        let episodes = Fixture.episodes(count: 10)

        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()

        #expect(warmer.warmedIDs.isEmpty)
    }

    @Test func veriTasarrufunaGecisBekleyenTasklariIptalEder() async {
        let warmer = RecordingWarmer()
        warmer.setDelay(nanoseconds: 5_000_000_000)
        let network = FakeNetworkProvider(.wifi)
        let preferences = FakePreferences()
        let controller = PrefetchController(
            warmer: warmer, network: network, preferences: preferences, poolSize: 3
        )
        let episodes = Fixture.episodes(count: 10)
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)

        preferences.setDataSaver(true)
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)

        #expect(await eventually { warmer.cancelledIDs.contains(EpisodeID("e6")) })
    }

    @Test func kullaniciAtlayincaEskiHedefIptalEdilir() async {
        // 04 §5.1 iptal kuralı: swipe ile geçilen bölümün bekleyen prefetch'i iptal edilir.
        let warmer = RecordingWarmer()
        warmer.setDelay(nanoseconds: 5_000_000_000)
        let (controller, _) = makeController(warmer: warmer)
        let episodes = Fixture.episodes(count: 20)
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)

        await controller.windowChanged(activeIndex: 9, episodes: episodes, direction: .forward)

        #expect(await eventually { warmer.cancelledIDs.contains(EpisodeID("e6")) })
    }

    @Test func kilitliBolumHedefListesineGirmez() async {
        let (controller, warmer) = makeController(poolSize: 4)
        let episodes = Fixture.episodes(count: 10, lockedIndexes: [6])

        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()

        #expect(warmer.warmedIDs == [EpisodeID("e7")])
    }

    @Test func ayniHedefIkinciPencereDegisimindeYenidenIsinmaz() async {
        let (controller, warmer) = makeController()
        let episodes = Fixture.episodes(count: 10)
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()

        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()

        #expect(warmer.warmedIDs.count == 1) // idempotent; tekrar warm çağrısı yok
    }

    @Test func cancelAllTumTasklariDurdurur() async {
        let warmer = RecordingWarmer()
        warmer.setDelay(nanoseconds: 5_000_000_000)
        let (controller, _) = makeController(warmer: warmer)
        let episodes = Fixture.episodes(count: 10)
        await controller.windowChanged(activeIndex: 5, episodes: episodes, direction: .forward)

        await controller.cancelAll()

        #expect(await eventually { warmer.cancelledIDs.contains(EpisodeID("e6")) })
    }
}
