import AppFoundation
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// FeedPlaybackDirector auto-advance karar akışı (04 §8.6, SS-062). Harness ve
// yardımcılar (makeDirector/collectDecisions/DecisionBox) FeedPlaybackDirectorTests.swift'te.

// MARK: - Auto-advance akışı (04 §8.6, SS-062)

@Suite("FeedPlaybackDirector — otomatik sonraki bölüm")
struct DirectorAutoAdvanceTests {
    /// playedToEnd kararı çok-hop'lu asenkron zincirden (fake backend → engine pump →
    /// engine latch/broadcast → director watch → karar akışı) geçer; kayıp latch ile
    /// giderildi (PlaybackEngine.endedForCurrentLoad), ama CI runner'ında 34 suite
    /// az çekirdekte paralel koşarken zamanlayıcı açlığı 2 sn poll'ü aşabiliyor. Değer
    /// KESİN geldiği için cömert tavan verilir; normal yolda anında döner (yavaşlatmaz).
    private static let decisionTimeout: TimeInterval = 15

    @Test("playedToEnd: sonraki karta geçiş kararı yayınlanır")
    func playedToEndAdvances() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        let (box, task) = collectDecisions(from: harness.director)
        defer { task.cancel() }

        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)

        let arrived = await eventually(timeoutSeconds: Self.decisionTimeout) {
            box.decisions == [.advance(toIndex: 1)]
        }
        #expect(arrived)
    }

    @Test("Son kartta playedToEnd: yeni öğe isteği kararı yayınlanır")
    func lastItemRequestsMore() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 1))
        let (box, task) = collectDecisions(from: harness.director)
        defer { task.cancel() }

        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)

        let arrived = await eventually(timeoutSeconds: Self.decisionTimeout) {
            box.decisions == [.requestMoreItems]
        }
        #expect(arrived)
    }

    @Test("Otomatik oynatma kapalı: stay kararı yayınlanır")
    func disabledYieldsStay() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        let (box, task) = collectDecisions(from: harness.director)
        defer { task.cancel() }

        await harness.director.setAutoAdvanceEnabled(false)
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)

        let arrived = await eventually(timeoutSeconds: Self.decisionTimeout) {
            box.decisions == [.stay]
        }
        #expect(arrived)
    }
}
