import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// MARK: - TTFF niyet → ilk kare kablolaması (04 §13, 08 §4)

@Suite("FeedPlaybackDirector — metrik kablolaması")
struct DirectorMetricsTests {
    @Test("Settle niyeti + ilk kare = ttff_ms'li video_start")
    func ttffWiring() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        let t0 = harness.clock.now
        _ = await harness.director.settle(at: 0, startType: .tap, now: t0)
        harness.clock.advance(by: 0.12)
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e0"), at: harness.clock.now)

        let event = harness.analytics.events.first { $0.name == "video_start" }
        #expect(event != nil)
        #expect(event?.parameters["ttff_ms"] == .int(120))
        #expect(event?.parameters["start_type"] == .string("tap"))
    }

    @Test("Devam pozisyonlu kart: activate resume ile, start_type=resume")
    func resumeStartType() async {
        let episode = Fixture.episode(id: "e0", durationSec: 100)
        let item = Fixture.feedItem(episode: episode, progress: Fixture.progress(for: episode, positionSec: 42))
        let harness = await makeDirector(items: [item])
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        await harness.director.firstFrameBecameVisible(episodeID: episode.id, at: harness.clock.now)

        #expect(harness.pool.calls.first ==
            .activate(episode.id, feedIndex: 0, resumePosition: 42))
        let event = harness.analytics.events.first { $0.name == "video_start" }
        #expect(event?.parameters["start_type"] == .string("resume"))
        #expect(event?.parameters["resume_position_s"] == .int(42))
    }

    @Test("Swipe niyeti (willEndDragging t0) + ilk kare = swipe_latency_ms'li swipe_next")
    func swipeLatencyWiring() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e0"), at: harness.clock.now)

        harness.clock.advance(by: 5)
        // t0 = scrollViewWillEndDragging (hedef indeks belli) — 04 §13.1.
        let intentAt = harness.clock.now
        await harness.director.recordSwipeIntent(toIndex: 1, at: intentAt)
        harness.clock.advance(by: 0.03) // deceleration süresi ölçüme DAHİL
        _ = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)
        harness.clock.advance(by: 0.02)
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e1"), at: harness.clock.now)

        let event = harness.analytics.events.first { $0.name == "swipe_next" }
        #expect(event != nil)
        #expect(event?.parameters["swipe_latency_ms"] == .int(50)) // 30 + 20 ms
        #expect(event?.parameters["from_episode_id"] == .string("e0"))
        #expect(event?.parameters["to_episode_id"] == .string("e1"))
    }

    @Test("Swipe niyeti t0'ı settle anından ÖNCEDİR (deceleration ölçüme dahil)")
    func swipeLatencyT0IsIntentMoment() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e0"), at: harness.clock.now)

        harness.clock.advance(by: 2)
        await harness.director.recordSwipeIntent(toIndex: 1, at: harness.clock.now) // t0
        harness.clock.advance(by: 0.20) // yalnız settle'dan ölçseydi bu süre kaybolurdu
        _ = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)
        harness.clock.advance(by: 0.10)
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e1"), at: harness.clock.now) // t1

        let event = harness.analytics.events.first { $0.name == "swipe_next" }
        #expect(event?.parameters["swipe_latency_ms"] == .int(300)) // 200 + 100 ms
    }

    @Test("Swipe niyeti gerçek watch_pct_at_swipe üretir (ileri yön)")
    func swipeWatchPercentageProduced() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3)) // durationSec = 90
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e0"), at: harness.clock.now)
        harness.pool.backend(for: EpisodeID("e0"))?.setPosition(45) // %50

        await harness.director.recordSwipeIntent(toIndex: 1, at: harness.clock.now)
        _ = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e1"), at: harness.clock.now)

        let event = harness.analytics.events.first { $0.name == "swipe_next" }
        #expect(event?.parameters["watch_pct_at_swipe"] == .double(0.5))
    }

    @Test("Ekran dışı bayat ilk-kare metrik ÜRETMEZ (eski episodeID)")
    func staleFirstFrameProducesNoMetric() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        // e0 ilk karesi hiç gelmeden e1'e geçildi (kart ekran dışına çıktı).
        _ = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)

        // Bayat hücre GEÇ ilk-kare sinyali basar (eski episodeID = e0):
        await harness.director.firstFrameBecameVisible(episodeID: EpisodeID("e0"), at: harness.clock.now)

        // e0 için sahte video_start ÜRETİLMEZ (aktif bölüm e1).
        let e0Start = harness.analytics.events.first {
            $0.name == "video_start" && $0.parameters["episode_id"] == .string("e0")
        }
        #expect(e0Start == nil)
    }
}
