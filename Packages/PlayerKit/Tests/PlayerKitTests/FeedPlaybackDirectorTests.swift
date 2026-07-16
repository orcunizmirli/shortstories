import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

// MARK: - Harness

struct DirectorHarness {
    let director: FeedPlaybackDirector
    let pool: RecordingFeedPool
    let prefetcher: RecordingFeedPrefetcher
    let analytics: MockAnalytics
    let clock: ClockBox
}

func makeDirector(items: [FeedItem], poolSize: Int = 3) async -> DirectorHarness {
    let pool = RecordingFeedPool()
    let prefetcher = RecordingFeedPrefetcher()
    let analytics = MockAnalytics()
    let clock = ClockBox()
    let director = FeedPlaybackDirector(
        pool: pool,
        prefetch: prefetcher,
        metrics: PlayerMetricsCollector(analytics: analytics),
        poolSizeProvider: { poolSize }
    )
    await director.updateItems(items)
    return DirectorHarness(director: director, pool: pool, prefetcher: prefetcher, analytics: analytics, clock: clock)
}

/// Auto-advance karar akışını toplayan kutu.
final class DecisionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [AutoAdvancePolicy.Decision] = []

    var decisions: [AutoAdvancePolicy.Decision] {
        lock.withLock { collected }
    }

    func append(_ decision: AutoAdvancePolicy.Decision) {
        lock.withLock { collected.append(decision) }
    }
}

func collectDecisions(from director: FeedPlaybackDirector) -> (DecisionBox, Task<Void, Never>) {
    let box = DecisionBox()
    let task = Task {
        for await decision in director.autoAdvanceDecisions {
            box.append(decision)
        }
    }
    return (box, task)
}

/// İlk auto-advance kararını OLAY-GÜDÜMLÜ yakalar. İterator, `trigger` (playedToEnd
/// emit'i) ateşlenmeden ÖNCE kurulur — ABONE-ÖNCE-YIELD sırası: karar `trigger`'dan
/// hemen sonra üretilse bile ya canlı park etmiş iterator'a ya da unbounded AsyncStream
/// buffer'ına düşer; hiçbir sıralamada kaçmaz.
///
/// Duvar-saati bütçesi YOKTUR (poll/deadline/`eventually` yok). playedToEnd→karar zinciri
/// çok hop'ludur (fake backend → engine olay pompası → engine actor → director watch task →
/// director actor → continuation) ve CI paralel-yük matrisinde bu arka-plan görevleri
/// zamanlayıcı açlığına girip teslimi ONLARCA SANİYE geciktirebilir. Teslim KESİN'dir
/// (engine `endedForCurrentLoad` latch'i + exactly-once + generation eşleşir + unbounded
/// buffer + tek tüketici), bu yüzden `await next()` değer geldiği AN uyandırılır — bütçe
/// aşımı diye bir şey olmadığından starvation yalnız GECİKTİRİR, asla flake üretmez. Gerçek
/// bir teslim-regresyonu (karar hiç üretilmez) CI iş-seviyesi timeout'uyla yakalanır; bu
/// yüzden per-test duvar-saati tavanı (`.timeLimit`) KULLANILMAZ — o, yavaş teslimi hatalı
/// yere fail'e çevirir.
func awaitDecision(
    from director: FeedPlaybackDirector,
    triggering trigger: () -> Void
) async -> AutoAdvancePolicy.Decision? {
    var iterator = director.autoAdvanceDecisions.makeAsyncIterator()
    trigger()
    return await iterator.next()
}

// MARK: - Pencere/lease koreografisi (SS-044 çekirdeği)

@Suite("FeedPlaybackDirector — pencere koreografisi")
struct DirectorWindowTests {
    @Test("Settle: activate → recycle → prefetch sırasıyla koşar")
    func settleActivatesAndShiftsWindow() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 10))
        let outcome = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)

        guard case let .activated(_, episode) = outcome else {
            Issue.record("activated bekleniyordu")
            return
        }
        #expect(episode.id == EpisodeID("e0"))
        // desiredIndexes(0, forward, 3, 10) = [0, 1] → pencere 0...1
        #expect(harness.pool.calls == [
            .activate(EpisodeID("e0"), feedIndex: 0, resumePosition: nil),
            .recycle(0 ... 1)
        ])
        #expect(harness.prefetcher.calls == [
            .windowChanged(activeIndex: 0, episodeCount: 10, direction: .forward)
        ])
    }

    @Test("İkinci settle pencereyi kaydırır (aktif ± komşular)")
    func secondSettleShiftsWindow() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 10))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        _ = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)

        // desiredIndexes(1, forward, 3, 10) = [1, 2, 0] → pencere 0...2
        #expect(harness.pool.calls.last == .recycle(0 ... 2))
        #expect(harness.prefetcher.calls.last ==
            .windowChanged(activeIndex: 1, episodeCount: 10, direction: .forward))
    }

    @Test("Geri kaydırma yönü prefetch'e backward olarak iletilir")
    func backwardDirectionPropagates() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 10))
        _ = await harness.director.settle(at: 2, startType: .tap, now: harness.clock.now)
        _ = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)

        #expect(harness.prefetcher.calls.last ==
            .windowChanged(activeIndex: 1, episodeCount: 10, direction: .backward))
    }

    @Test("Aynı indekse ikinci settle no-op'tur (tek activate)")
    func duplicateSettleIsNoOp() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 10))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        let second = await harness.director.settle(at: 0, startType: .swipe, now: harness.clock.now)

        guard case .none = second else {
            Issue.record("none bekleniyordu")
            return
        }
        let activateCount = harness.pool.calls.filter { call in
            if case .activate = call {
                return true
            }
            return false
        }.count
        #expect(activateCount == 1)
    }

    @Test("Eşzamanlı settle'lar SERİLEŞİR: activate/recycle blokları iç içe geçmez")
    func concurrentSettlesAreSerialized() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 10))
        harness.pool.setActivateDelay(nanoseconds: 40_000_000)

        async let first = harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        async let second = harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)
        _ = await (first, second)

        let calls = harness.pool.calls
        #expect(calls.count == 4)
        for (index, call) in calls.enumerated() {
            switch call {
            case .activate:
                #expect(index.isMultiple(of: 2), "activate yalnız blok başında olabilir")
            case .recycle:
                #expect(!index.isMultiple(of: 2), "recycle activate'i izlemeli")
            default:
                Issue.record("beklenmeyen çağrı: \(call)")
            }
        }
    }

    @Test("Teardown: prefetch iptal + havuz drain")
    func teardownCancelsAndDrains() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        await harness.director.teardown()

        #expect(harness.prefetcher.calls.last == .cancelAll)
        #expect(harness.pool.calls.last == .drain)
    }

    @Test("Bölüm taşımayan kart: activate yok, aktif oynatma durur")
    func nonPlayableItemPausesActive() async {
        var items = Fixture.feedItems(count: 3)
        items[1] = FeedItem(
            id: "promo-1",
            type: .seriesPromo,
            episode: nil,
            series: Fixture.series(),
            progress: nil,
            reason: nil
        )
        let harness = await makeDirector(items: items)
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        let outcome = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)

        // Aktif indeks bölümsüz karta ilerledi: VC delegate'e nil bölüm bildirir (04 §2.4).
        guard case .settledWithoutEpisode = outcome else {
            Issue.record("settledWithoutEpisode bekleniyordu")
            return
        }
        let backend = harness.pool.backend(for: EpisodeID("e0"))
        #expect(backend?.calls.contains(.pause) == true)
        // Ses sızıntısı yok: bölümsüz karta geçişte mute+pause (02 §4.3.7).
        #expect(backend?.calls.contains(.setMuted(true)) == true)
    }

    @Test("Aynı bölümsüz karta re-settle idempotenttir (.none)")
    func nonPlayableResettleIsIdempotent() async {
        var items = Fixture.feedItems(count: 3)
        items[1] = FeedItem(
            id: "promo-1",
            type: .seriesPromo,
            episode: nil,
            series: Fixture.series(),
            progress: nil,
            reason: nil
        )
        let harness = await makeDirector(items: items)
        _ = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)
        let second = await harness.director.settle(at: 1, startType: .swipe, now: harness.clock.now)
        guard case .none = second else {
            Issue.record("none bekleniyordu")
            return
        }
    }
}

// MARK: - Kilitli bölüm kesişimi (04 §9, SS-050)

@Suite("FeedPlaybackDirector — kilit sınırı")
struct DirectorLockTests {
    @Test("Kilitli bölüme settle: locked outcome + önceki oynatma pause")
    func lockedSettleReportsAndPauses() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 5, lockedIndexes: [3]))
        harness.pool.setLocked([EpisodeID("e3")])
        _ = await harness.director.settle(at: 2, startType: .tap, now: harness.clock.now)
        let outcome = await harness.director.settle(at: 3, startType: .swipe, now: harness.clock.now)

        guard case let .locked(episode) = outcome else {
            Issue.record("locked bekleniyordu")
            return
        }
        #expect(episode.id == EpisodeID("e3"))
        let backend = harness.pool.backend(for: EpisodeID("e2"))
        #expect(backend?.calls.contains(.pause) == true)
        // 02 §4.3.7: önceki player mute+pause garanti — ses sızıntısı penceresi yok.
        #expect(backend?.calls.contains(.setMuted(true)) == true)
    }

    @Test("Aynı kilitli indekse ikinci settle sessizdir (çift sheet yok)")
    func lockedSettleIsIdempotent() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 5, lockedIndexes: [3]))
        harness.pool.setLocked([EpisodeID("e3")])
        _ = await harness.director.settle(at: 3, startType: .swipe, now: harness.clock.now)
        let second = await harness.director.settle(at: 3, startType: .swipe, now: harness.clock.now)

        guard case .none = second else {
            Issue.record("none bekleniyordu")
            return
        }
    }

    @Test("Unlock sonrası aynı hücrede yeniden aktivasyon: locked → activated (04 §9.2)")
    func reactivateAfterUnlockPlaysInPlace() async {
        let harness = await makeDirector(items: Fixture.feedItems(count: 5, lockedIndexes: [3]))
        harness.pool.setLocked([EpisodeID("e3")])
        _ = await harness.director.settle(at: 2, startType: .tap, now: harness.clock.now)
        let locked = await harness.director.settle(at: 3, startType: .swipe, now: harness.clock.now)
        guard case .locked = locked else {
            Issue.record("locked bekleniyordu")
            return
        }

        // Entitlement geldi (coin/reklam/VIP): idempotans + kilit korkuluğu aşılır.
        harness.pool.setLocked([])
        let outcome = await harness.director.reactivateAfterUnlock(at: 3, now: harness.clock.now)
        guard case let .activated(_, episode) = outcome else {
            Issue.record("activated bekleniyordu")
            return
        }
        #expect(episode.id == EpisodeID("e3"))
        // Açılan slot mute değil (02 §4.3.7 tersine): aktivasyonda unmute.
        #expect(harness.pool.backend(for: EpisodeID("e3"))?.calls.contains(.setMuted(false)) == true)
    }
}

// MARK: - Jest → oynatma kontrolü

@Suite("FeedPlaybackDirector — oynatma kontrolü")
struct DirectorControlTests {
    private func activatePlaying(_ harness: DirectorHarness, episodeID: String = "e0") async {
        _ = await harness.director.settle(at: 0, startType: .tap, now: harness.clock.now)
        guard let backend = harness.pool.backend(for: EpisodeID(episodeID)),
              let engine = harness.pool.engine(for: EpisodeID(episodeID))
        else {
            Issue.record("backend/engine bulunamadı")
            return
        }
        backend.emit(.firstFrameReady)
        _ = await awaitState(.playing, on: engine)
    }

    @Test("Tek tap toggle: oynarken pause, dururken play")
    func togglePlayPause() async throws {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        await activatePlaying(harness)
        let engine = try #require(harness.pool.engine(for: EpisodeID("e0")))

        await harness.director.togglePlayPause()
        #expect(await engine.currentState() == .paused)

        await harness.director.togglePlayPause()
        #expect(await engine.currentState() == .playing)
    }

    @Test("Çift tap: toggle geri alınır ve kırpılmış hedefe seek edilir")
    func revertToggleAndSeek() async throws {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        await activatePlaying(harness)
        let engine = try #require(harness.pool.engine(for: EpisodeID("e0")))
        let backend = try #require(harness.pool.backend(for: EpisodeID("e0")))
        backend.setPosition(30)

        await harness.director.togglePlayPause() // tek tap etkisi (pause)
        await harness.director.revertToggleAndSeek(offsetSeconds: 10)

        #expect(await engine.currentState() == .playing)
        // Çift tap TOLERANT seek kullanır (04 §8.1 / 01 PLR-02); keskin .zero değil.
        #expect(backend.calls.contains(.seekTolerant(40)))
        #expect(!backend.calls.contains(.seek(40)))
    }

    @Test("Bölüm sonuna kırpılan seek auto-advance'i BASTIRIR")
    func seekToEndSuppressesAutoAdvance() async throws {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        let (box, task) = collectDecisions(from: harness.director)
        defer { task.cancel() }
        await activatePlaying(harness)
        let backend = try #require(harness.pool.backend(for: EpisodeID("e0")))
        backend.setPosition(85) // durationSec = 90

        await harness.director.seekByOffset(10)
        #expect(backend.calls.contains(.seekTolerant(90)))

        backend.emit(.playedToEnd)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(box.decisions.isEmpty)
    }

    @Test("Uzun bas: 2x'e çıkar, bırakınca tercih hızına döner")
    func holdSpeedTogglesRate() async throws {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        await activatePlaying(harness)
        let backend = try #require(harness.pool.backend(for: EpisodeID("e0")))

        await harness.director.setPreferredRate(1.5)
        await harness.director.setHoldSpeed(true)
        #expect(backend.calls.contains(.setRate(2.0)))

        await harness.director.setHoldSpeed(false)
        #expect(backend.calls.last == .setRate(1.5))
    }

    @Test("Uzun bas 2x: ton koruması (.timeDomain) hıza geçmeden ÖNCE uygulanır")
    func holdSpeedPreservesPitch() async throws {
        let harness = await makeDirector(items: Fixture.feedItems(count: 3))
        await activatePlaying(harness)
        let backend = try #require(harness.pool.backend(for: EpisodeID("e0")))

        await harness.director.setHoldSpeed(true)
        // 01 PLR-03: 2x sırasında ton korunur; pitch koruması setRate'ten ÖNCE.
        let pitchIndex = backend.calls.firstIndex(of: .setPitchPreservation(true))
        let rateIndex = backend.calls.firstIndex(of: .setRate(2.0))
        #expect(pitchIndex != nil)
        #expect(rateIndex != nil)
        if let pitchIndex, let rateIndex {
            #expect(pitchIndex < rateIndex)
        }
    }
}
