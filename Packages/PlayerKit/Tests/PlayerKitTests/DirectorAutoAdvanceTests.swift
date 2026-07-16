import AppFoundation
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// FeedPlaybackDirector auto-advance karar akışı (04 §8.6, SS-062). Harness ve
// yardımcılar (makeDirector/collectDecisions/DecisionBox) FeedPlaybackDirectorTests.swift'te.

// MARK: - Auto-advance akışı (04 §8.6, SS-062)

/// Bekleme OLAY-GÜDÜMLÜ'dür (`awaitDecision`): iterator playedToEnd emit'inden ÖNCE kurulur
/// (abone-önce-yield), karar yapısal `await` ile alınır. Duvar-saati poll'ü/tavanı YOKTUR —
/// CI paralel-yük altında zamanlayıcı açlığı teslimi geciktirse bile değer KESİN geldiği an
/// (engine latch, exactly-once) uyandırılır; bir `.timeLimit` tavanı EKLENMEZ çünkü yavaş
/// teslimi hatalı yere fail'e çevirirdi (gerçek teslim-regresyonu CI iş-timeout'uyla yakalanır).
@Suite("FeedPlaybackDirector — otomatik sonraki bölüm")
struct DirectorAutoAdvanceTests {
    @Test("playedToEnd: sonraki karta geçiş kararı yayınlanır")
    func playedToEndAdvances() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)

        let decision = await awaitDecision(from: harness.director) {
            harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)
        }
        #expect(decision == .advance(toIndex: 1))
    }

    @Test("Son kartta playedToEnd: yeni öğe isteği kararı yayınlanır")
    func lastItemRequestsMore() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 1))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)

        let decision = await awaitDecision(from: harness.director) {
            harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)
        }
        #expect(decision == .requestMoreItems)
    }

    @Test("Otomatik oynatma kapalı: stay kararı yayınlanır")
    func disabledYieldsStay() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        await harness.director.setAutoAdvanceEnabled(false)
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)

        let decision = await awaitDecision(from: harness.director) {
            harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)
        }
        #expect(decision == .stay)
    }
}
