import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import PlayerKit

/// PlayerMetricsCollector testleri (04 §13.1, 08 §4): ttff/stall/swipe ölçümleri
/// player-teknolojisi-bağımsız işaretleyicilerle toplanır; taşıyıcı event'ler
/// 08 §3.2 kataloğuyla birebir basılır (ayrı performans event'i YOKTUR).
struct PlayerMetricsCollectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test func ttffVideoStartEventiyleTasinir() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e1", seriesID: "s1", index: 3)

        await collector.recordPlaybackIntent(for: episode, startType: .swipe, at: t0)
        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(0.42))

        let event = analytics.events.first { $0.name == "video_start" }
        #expect(event != nil)
        #expect(event?.parameters["ttff_ms"] == .int(420))
        #expect(event?.parameters["series_id"] == .string("s1"))
        #expect(event?.parameters["episode_id"] == .string("e1"))
        #expect(event?.parameters["episode_number"] == .int(3))
        #expect(event?.parameters["start_type"] == .string("swipe"))
        #expect(event?.parameters["is_locked_content"] == .bool(false))
    }

    @Test func unlockluIcerikIsLockedContentTasir() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e5", kind: .unlocked)

        await collector.recordPlaybackIntent(for: episode, startType: .tap, at: t0)
        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(0.1))

        let event = analytics.events.first { $0.name == "video_start" }
        #expect(event?.parameters["is_locked_content"] == .bool(true))
    }

    @Test func entitlementIleAcilanKilitliBolumIsLockedContentTasir() async {
        // 08 §3.2: kilitli bölüm entitlement'la (VIP / daha önce açılmış) oynatıldığında
        // da is_locked_content = true — kilitli içerik tüketimi ölçümden düşmez.
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e9", kind: .locked, unlockPrice: 60)

        await collector.recordPlaybackIntent(
            for: episode,
            startType: .tap,
            isUnlockedByEntitlement: true,
            at: t0
        )
        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(0.1))

        let event = analytics.events.first { $0.name == "video_start" }
        #expect(event?.parameters["is_locked_content"] == .bool(true))
    }

    @Test func resumeBaslangiciPozisyonParametresiTasir() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e1")

        await collector.recordPlaybackIntent(for: episode, startType: .resume, resumePosition: 33.4, at: t0)
        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(0.2))

        let event = analytics.events.first { $0.name == "video_start" }
        #expect(event?.parameters["start_type"] == .string("resume"))
        #expect(event?.parameters["resume_position_s"] == .int(33))
    }

    @Test func niyetsizIlkKareEventUretmez() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)

        await collector.recordFirstFrame(for: Fixture.episode(id: "e1"), at: t0)

        #expect(analytics.events.isEmpty)
    }

    @Test func ilkKareyeIkinciNiyetCiftEventUretmez() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e1")
        await collector.recordPlaybackIntent(for: episode, startType: .tap, at: t0)
        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(0.1))

        await collector.recordFirstFrame(for: episode, at: t0.addingTimeInterval(0.2))

        #expect(analytics.events.count { $0.name == "video_start" } == 1)
    }

    // MARK: - Stall (08 §3.2: >= 250 ms eşiği; stall bittiğinde gönderilir)

    @Test func esikUstuStallVideoStallEventiUretir() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e1", seriesID: "s1")

        await collector.recordStallBegan(for: episode, positionSeconds: 12.5, networkType: "cellular", at: t0)
        await collector.recordStallEnded(at: t0.addingTimeInterval(0.4))

        let event = analytics.events.first { $0.name == "video_stall" }
        #expect(event != nil)
        #expect(event?.parameters["stall_duration_ms"] == .int(400))
        #expect(event?.parameters["position_s"] == .int(12))
        #expect(event?.parameters["network_type"] == .string("cellular"))
    }

    @Test func esikAltiStallRaporlanmaz() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let episode = Fixture.episode(id: "e1")

        await collector.recordStallBegan(for: episode, positionSeconds: 5, networkType: "wifi", at: t0)
        await collector.recordStallEnded(at: t0.addingTimeInterval(0.1)) // 100 ms < 250 ms

        #expect(analytics.events.isEmpty)
    }

    @Test func baslamamisStallinBitisiYokSayilir() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)

        await collector.recordStallEnded(at: t0)

        #expect(analytics.events.isEmpty)
    }

    // MARK: - Swipe gecikmesi (08 §4: settle → hedef player ilk kare)

    @Test func ileriSwipeSwipeNextIleGecikmeTasir() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let target = Fixture.episode(id: "e2")

        await collector.recordSwipeSettled(
            from: EpisodeID("e1"), to: target.id, direction: .forward, watchPercentageAtSwipe: 0.8, at: t0
        )
        await collector.recordPlaybackIntent(for: target, startType: .swipe, at: t0)
        await collector.recordFirstFrame(for: target, at: t0.addingTimeInterval(0.08))

        let event = analytics.events.first { $0.name == "swipe_next" }
        #expect(event != nil)
        #expect(event?.parameters["swipe_latency_ms"] == .int(80))
        #expect(event?.parameters["from_episode_id"] == .string("e1"))
        #expect(event?.parameters["to_episode_id"] == .string("e2"))
        #expect(event?.parameters["watch_pct_at_swipe"] == .double(0.8))
    }

    @Test func geriSwipeSwipePrevUretir() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let target = Fixture.episode(id: "e1")

        await collector.recordSwipeSettled(
            from: EpisodeID("e2"), to: target.id, direction: .backward, at: t0
        )
        await collector.recordPlaybackIntent(for: target, startType: .swipe, at: t0)
        await collector.recordFirstFrame(for: target, at: t0.addingTimeInterval(0.05))

        let event = analytics.events.first { $0.name == "swipe_prev" }
        #expect(event != nil)
        #expect(event?.parameters["swipe_latency_ms"] == .int(50))
    }

    @Test func farkliBolumeGelenIlkKareSwipeEventiUretmez() async {
        let analytics = MockAnalytics()
        let collector = PlayerMetricsCollector(analytics: analytics)
        let other = Fixture.episode(id: "e7")

        await collector.recordSwipeSettled(from: EpisodeID("e1"), to: EpisodeID("e2"), direction: .forward, at: t0)
        await collector.recordPlaybackIntent(for: other, startType: .tap, at: t0)
        await collector.recordFirstFrame(for: other, at: t0.addingTimeInterval(0.05))

        #expect(!analytics.eventNames.contains("swipe_next"))
    }
}
