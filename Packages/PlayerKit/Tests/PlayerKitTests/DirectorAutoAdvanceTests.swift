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

    @Test("Uçuştaki manuel swipe auto-advance'i bastırır (yanlış bölüme fırlatma yok)")
    func swipeIntentSuppressesAutoAdvance() async throws {
        // hunt MEDIUM: kullanıcı bölüm sonuna yakınken BAŞKA karta (bitişik-olmayan/geri) flick atarken aktif
        // bölüm sonuna ulaşırsa, auto-advance kullanıcının deceleration'ını ezip `active+1`'e fırlatıyordu.
        let harness = await makeDirector(items: Fixture.feedItems(count: 4))
        let (box, task) = collectDecisions(from: harness.director)
        defer { task.cancel() }
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now) // active=0
        let backend = try #require(harness.pool.backend(for: EpisodeID("e0")))

        await harness.director.recordSwipeIntent(toIndex: 2, at: harness.clock.now) // 0→2 flick (bitişik-olmayan)

        backend.emit(.playedToEnd) // deceleration sırasında e0 biter
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(box.decisions.isEmpty) // auto-advance BASTIRILDI (0→1'e YANLIŞ fırlatma YOK)
    }

    @Test("Aynı-yere bounce swipe auto-advance'i bastırmaz (bölüm bitince normal ilerler)")
    func sameIndexSwipeDoesNotSuppressAutoAdvance() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 4))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now) // active=0
        await harness.director.recordSwipeIntent(toIndex: 0, at: harness.clock.now) // aynı-yere (bounce) → niyet guard'a takılır

        // e0 sonuna ulaşır → normal auto-advance 0→1 (gerçek navigasyon yoktu → bastırma yok).
        let decision = await awaitDecision(from: harness.director) {
            harness.pool.backend(for: EpisodeID("e0"))?.emit(.playedToEnd)
        }
        #expect(decision == .advance(toIndex: 1))
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
