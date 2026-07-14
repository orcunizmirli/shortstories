import Foundation
import Testing
@testable import PlayerKit

/// Prefetch politikası saf fonksiyon testleri (04 §5): yön farkındalığı, bütçe,
/// hücresel/veri tasarrufu davranışı ve hızlı flick kuralı.
struct PrefetchPolicyTests {
    private func context(
        activeIndex: Int = 5,
        direction: ScrollDirection = .forward,
        poolSize: Int = 3,
        episodeCount: Int = 100,
        lockedIndexes: Set<Int> = [],
        network: NetworkCondition = .wifi,
        isDataSaverEnabled: Bool = false,
        secondsSinceLastSwipe: TimeInterval? = nil
    ) -> PrefetchPolicy.Context {
        PrefetchPolicy.Context(
            activeIndex: activeIndex,
            direction: direction,
            poolSize: poolSize,
            episodeCount: episodeCount,
            lockedIndexes: lockedIndexes,
            network: network,
            isDataSaverEnabled: isDataSaverEnabled,
            secondsSinceLastSwipe: secondsSinceLastSwipe
        )
    }

    @Test func ileriYondeOncelikSonrakiBolumdur() {
        let plan = PrefetchPolicy.plan(context(poolSize: 3))
        #expect(plan.targetIndexes == [6]) // 3 slotluk havuzda yalnız index+1
    }

    @Test func genisHavuzdaIkiAdimIleriIsinir() {
        let plan = PrefetchPolicy.plan(context(poolSize: 4))
        #expect(plan.targetIndexes == [6, 7]) // önce index+1, sonra index+2 (04 §5.2)
    }

    @Test func geriYondeOncelikTersineDoner() {
        let plan = PrefetchPolicy.plan(context(direction: .backward, poolSize: 4))
        #expect(plan.targetIndexes == [4, 3])
    }

    @Test func feedSonundaHedeflerKirpilir() {
        let plan = PrefetchPolicy.plan(context(activeIndex: 99, poolSize: 5))
        #expect(plan.targetIndexes.isEmpty)
    }

    @Test func kilitliBolumIsinmaz() {
        // 04 §9.1 kural 4: prefetch kilidi — entitlement olmayan kilitli bölüm ısındırılmaz.
        let plan = PrefetchPolicy.plan(context(poolSize: 4, lockedIndexes: [6]))
        #expect(plan.targetIndexes == [7])
    }

    @Test func veriTasarrufuPrefetchiTamamenDurdurur() {
        let plan = PrefetchPolicy.plan(context(network: .cellular, isDataSaverEnabled: true))
        #expect(plan.targetIndexes.isEmpty) // kanon: 480p tavan + prefetch durdur
    }

    @Test func lowDataModeVeriTasarrufunaDusurur() {
        // iOS Low Data Mode (allowsExpensiveNetworkAccess) aynı davranışa düşer (04 §5.3).
        let constrained = NetworkCondition(interface: .wifi, isConstrained: true)
        let plan = PrefetchPolicy.plan(context(network: constrained))
        #expect(plan.targetIndexes.isEmpty)
    }

    @Test func normalHucreselPrefetchAcikKalir() {
        let plan = PrefetchPolicy.plan(context(network: .cellular))
        #expect(plan.targetIndexes == [6])
    }

    @Test func hizliFlickAraIndeksleriAtlar() {
        // İki swipe arası < 300 ms: yalnız hedef + yönündeki komşu ısındırılır (04 §5.2).
        let plan = PrefetchPolicy.plan(context(poolSize: 5, secondsSinceLastSwipe: 0.1))
        #expect(plan.targetIndexes == [6])
    }

    @Test func yavasSwipeNormalPencereKullanir() {
        let plan = PrefetchPolicy.plan(context(poolSize: 4, secondsSinceLastSwipe: 1.5))
        #expect(plan.targetIndexes == [6, 7])
    }

    @Test func butceKanonikDegerlerdir() {
        // ~500 KB veya ilk 2 sn — hangisi önce (04 §5.1).
        let plan = PrefetchPolicy.plan(context())
        #expect(plan.budget == .standard)
        #expect(PrefetchBudget.standard.maxBytes == 500 * 1024)
        #expect(PrefetchBudget.standard.maxSeconds == 2)
    }
}

/// Bitrate tavanı politikası (04 §6.3).
struct BitrateCapPolicyTests {
    @Test func veriTasarrufu480pTavaniUygular() {
        let cap = BitrateCapPolicy.maxBitrate(network: .cellular, isDataSaverEnabled: true)
        #expect(cap == 800_000)
    }

    @Test func lowDataMode480pTavaniUygular() {
        let constrained = NetworkCondition(interface: .cellular, isConstrained: true)
        let cap = BitrateCapPolicy.maxBitrate(network: constrained, isDataSaverEnabled: false)
        #expect(cap == 800_000)
    }

    @Test func normalHucresel720pTavaniUygular() {
        let cap = BitrateCapPolicy.maxBitrate(network: .cellular, isDataSaverEnabled: false)
        #expect(cap == 1_400_000)
    }

    @Test func wifidaSinirYokturABRKararVerir() {
        let cap = BitrateCapPolicy.maxBitrate(network: .wifi, isDataSaverEnabled: false)
        #expect(cap == 0)
    }
}
