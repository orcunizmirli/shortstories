import Testing
@testable import PlayerKit

/// Index-penceresi saf mantık testleri (04 §3.2, §3.3 kural 3): pencere kompozisyonu
/// öncelik sıralıdır; geri alınacak slot aktif indekse EN UZAK olandır, aktif asla.
struct PoolWindowPlannerTests {
    // MARK: - desiredIndexes

    @Test func ileriYondeUcluPencere() {
        let window = PoolWindowPlanner.desiredIndexes(
            activeIndex: 5, direction: .forward, poolSize: 3, episodeCount: 100
        )
        #expect(window == [5, 6, 4]) // aktif, yön komşusu, ters komşu
    }

    @Test func geriYondeUcluPencere() {
        let window = PoolWindowPlanner.desiredIndexes(
            activeIndex: 5, direction: .backward, poolSize: 3, episodeCount: 100
        )
        #expect(window == [5, 4, 6])
    }

    @Test func dortSlotluHavuzYonundeBirAdimOndeGider() {
        let window = PoolWindowPlanner.desiredIndexes(
            activeIndex: 5, direction: .forward, poolSize: 4, episodeCount: 100
        )
        #expect(window == [5, 6, 4, 7]) // 4. slot kaydırma yönünde index+2 (04 §3.2)
    }

    @Test func besSlotluHavuzPencereyiIkiYoneGenisletir() {
        let window = PoolWindowPlanner.desiredIndexes(
            activeIndex: 5, direction: .forward, poolSize: 5, episodeCount: 100
        )
        #expect(window == [5, 6, 4, 7, 3])
    }

    @Test func feedBasindaPencereKirpilir() {
        let window = PoolWindowPlanner.desiredIndexes(
            activeIndex: 0, direction: .forward, poolSize: 3, episodeCount: 100
        )
        #expect(window == [0, 1]) // index -1 yok
    }

    @Test func feedSonundaPencereKirpilir() {
        let window = PoolWindowPlanner.desiredIndexes(
            activeIndex: 9, direction: .forward, poolSize: 3, episodeCount: 10
        )
        #expect(window == [9, 8]) // index 10 yok
    }

    @Test func tekBolumlukFeeddeYalnizAktif() {
        let window = PoolWindowPlanner.desiredIndexes(
            activeIndex: 0, direction: .forward, poolSize: 5, episodeCount: 1
        )
        #expect(window == [0])
    }

    // MARK: - reclaimableSlot

    @Test func bosSlotOncelikliGeriAlinir() {
        let slot = PoolWindowPlanner.reclaimableSlot(
            feedIndexes: [5, nil, 6], activeSlot: 0, activeFeedIndex: 5
        )
        #expect(slot == 1)
    }

    @Test func aktifIndekseEnUzakSlotGeriAlinir() {
        let slot = PoolWindowPlanner.reclaimableSlot(
            feedIndexes: [5, 2, 6], activeSlot: 0, activeFeedIndex: 5
        )
        #expect(slot == 1) // |2-5| = 3 en uzak
    }

    @Test func aktifSlotAslaGeriAlinmaz() {
        let slot = PoolWindowPlanner.reclaimableSlot(
            feedIndexes: [5, 4, 6], activeSlot: 0, activeFeedIndex: 5
        )
        #expect(slot != 0)
    }

    @Test func aktifYokkenIlkBosVeyaIlkSlotSecilir() {
        let slot = PoolWindowPlanner.reclaimableSlot(
            feedIndexes: [nil, nil, nil], activeSlot: nil, activeFeedIndex: nil
        )
        #expect(slot == 0)
    }

    @Test func esitUzaklikltaDusukSlotSecilir() {
        let slot = PoolWindowPlanner.reclaimableSlot(
            feedIndexes: [5, 4, 6], activeSlot: 0, activeFeedIndex: 5
        )
        #expect(slot == 1) // |4-5| == |6-5|; deterministik: ilk aday
    }
}
