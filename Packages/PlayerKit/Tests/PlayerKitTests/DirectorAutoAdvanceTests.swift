import AppFoundation
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// FeedPlaybackDirector auto-advance karar akışı (04 §8.6, SS-062). Harness ve
// yardımcılar (makeDirector/collectDecisions/DecisionBox) FeedPlaybackDirectorTests.swift'te.

// MARK: - Auto-advance akışı (04 §8.6, SS-062)

/// Bekleme OLAY-GÜDÜMLÜ'dür (`awaitDecisions`): karar akışını yapısal `await` ile tüketir,
/// duvar-saati poll'ü YOKTUR — CI paralel-yük altında zamanlayıcı açlığı yaşansa bile değer
/// KESİN geldiği an (engine latch, exactly-once) uyandırılır, flake üretmez. `.timeLimit`
/// yalnız gerçek bir teslim-regresyonunda (olay hiç gelmezse) sonsuz asılmayı engelleyen
/// güvenlik tavanıdır; normal ve starve yollarında ateşlenmez.
@Suite("FeedPlaybackDirector — otomatik sonraki bölüm", .timeLimit(.minutes(1)))
struct DirectorAutoAdvanceTests {
    @Test("playedToEnd: sonraki karta geçiş kararı yayınlanır")
    func playedToEndAdvances() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))

        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)

        let decisions = await awaitDecisions(1, from: harness.director)
        #expect(decisions == [.advance(toIndex: 1)])
    }

    @Test("Son kartta playedToEnd: yeni öğe isteği kararı yayınlanır")
    func lastItemRequestsMore() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 1))

        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)

        let decisions = await awaitDecisions(1, from: harness.director)
        #expect(decisions == [.requestMoreItems])
    }

    @Test("Otomatik oynatma kapalı: stay kararı yayınlanır")
    func disabledYieldsStay() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))

        await harness.director.setAutoAdvanceEnabled(false)
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)

        let decisions = await awaitDecisions(1, from: harness.director)
        #expect(decisions == [.stay])
    }
}
