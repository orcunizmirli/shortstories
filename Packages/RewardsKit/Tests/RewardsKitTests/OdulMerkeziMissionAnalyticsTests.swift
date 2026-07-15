import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import RewardsKit

/// SS-112 `OdulMerkeziModel` görev analitiği — 08 §3.5 registry hizalaması: `mission_view`,
/// `mission_progress` (%50 ilk geçiş), `mission_complete` (claimable geçişi + mission_type
/// taksonomisi), `mission_claim` (+expires_at). Ayrıca F2 watchAd flag gate (SS-113): rewarded ad
/// KAPALI iken watchAd görevi listede render edilmez. Registry-DIŞI eski adlar (`task_claimed`/
/// `task_progress`) gönderilmez (§2.3).
@MainActor
@Suite("SS-112 OdulMerkezi görev analitiği (08 §3.5)")
struct OdulMerkeziMissionAnalyticsTests {
    private func makeModel(
        taskCatalog: FakeTaskCatalog = FakeTaskCatalog(),
        rewardClaiming: FakeRewardClaiming = FakeRewardClaiming(),
        analytics: MockAnalytics = MockAnalytics(),
        flags: MockFeatureFlags = MockFeatureFlags()
    ) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: FakeCheckInService(),
            wallet: FakeRewardsWallet(100),
            taskCatalog: taskCatalog,
            taskProgress: FakeTaskProgress(),
            rewardClaiming: rewardClaiming,
            analytics: analytics,
            featureFlags: flags,
            delegate: RewardsDelegateSpy()
        )
    }

    // MARK: - mission_claim (2°): registry adı + parametreler + expires_at (SS-115)

    @Test func claimEmitsMissionClaimWithRegistryParams() async {
        // Registry event adı `mission_claim`; parametreler mission_id + coin_reward (+expires_at?).
        // Eski registry-DIŞI `task_claimed`/`task_id`/`task_kind` artık gönderilmez.
        let claimed = RewardTask.mock(id: "fav1", kind: .favoriteSeries, progress: 1, state: .claimed)
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "fav1", kind: .favoriteSeries, rewardCoins: 10, target: 1, progress: 1, state: .claimable)
        ]))
        let claiming = FakeRewardClaiming(.success(.mock(coins: 10, coinBalance: 110, task: claimed)))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, rewardClaiming: claiming, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        await model.claimTask("fav1")
        #expect(!analytics.events.contains { $0.name == "task_claimed" }) // registry-dışı ad kalkmıştır
        let event = analytics.events.first { $0.name == "mission_claim" }
        #expect(event?.parameters["mission_id"] == .string("fav1"))
        #expect(event?.parameters["coin_reward"] == .int(10))
        #expect(event?.parameters["task_id"] == nil)
        #expect(event?.parameters["task_kind"] == nil)
        #expect(event?.parameters["expires_at"] == nil) // vade yoksa parametre atlanır (opsiyonel)
    }

    @Test func claimEmitsMissionClaimWithExpiresAt() async {
        // reward.expiresAt varsa `expires_at` (Unix epoch ms; §2.2 event_ts konvansiyonu) eklenir —
        // 2° gelir/fraud reconciliation bunu besler (SS-115 vade).
        let expiry = Date(timeIntervalSince1970: 1_800_000) // → 1_800_000_000 ms
        let claimed = RewardTask.mock(id: "a", progress: 10, state: .claimed)
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "a", rewardCoins: 20, target: 10, progress: 10, state: .claimable)
        ]))
        let claiming = FakeRewardClaiming(.success(.mock(coins: 20, coinBalance: 320, expiresAt: expiry, task: claimed)))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, rewardClaiming: claiming, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        await model.claimTask("a")
        let event = analytics.events.first { $0.name == "mission_claim" }
        #expect(event?.parameters["expires_at"] == .int(1_800_000_000))
    }

    // MARK: - mission_complete (2°, ZORUNLU): claimable geçişinde (refresh), ilk yüklemede DEĞİL

    @Test func missionCompleteEmittedWhenTaskBecomesClaimableOnRefresh() async {
        // Registry `mission_complete` = tamamlanma/claimable geçişi; params mission_id + mission_type.
        // Eski registry-DIŞI `task_progress` artık gönderilmez.
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "a", kind: .watchMinutes, target: 10, progress: 6, state: .inProgress)
        ]))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        #expect(!analytics.events.contains { $0.name == "mission_complete" }) // ilk yüklemede milestone yok

        catalog.set(.success([.mock(id: "a", kind: .watchMinutes, target: 10, progress: 10, state: .claimable)]))
        await model.retry()
        #expect(!analytics.events.contains { $0.name == "task_progress" }) // registry-dışı ad kalkmıştır
        let event = analytics.events.first { $0.name == "mission_complete" }
        #expect(event?.parameters["mission_id"] == .string("a"))
        #expect(event?.parameters["mission_type"] == .string("watch_time")) // watchMinutes → watch_time
    }

    // MARK: - mission_progress: ilerleme %50'yi İLK geçtiğinde (refresh), ilk yüklemede DEĞİL

    @Test func missionProgressEmittedWhenTaskCrossesHalfwayOnRefresh() async {
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "a", kind: .watchMinutes, target: 10, progress: 3, state: .inProgress)
        ]))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        #expect(!analytics.events.contains { $0.name == "mission_progress" }) // ilk yüklemede baseline yok

        catalog.set(.success([.mock(id: "a", kind: .watchMinutes, target: 10, progress: 6, state: .inProgress)]))
        await model.retry()
        let event = analytics.events.first { $0.name == "mission_progress" }
        #expect(event?.parameters["mission_id"] == .string("a"))
        #expect(event?.parameters["progress_pct"] == .int(50)) // yalnız 50 checkpoint'i (hacim kontrolü)
        #expect(!analytics.events.contains { $0.name == "mission_complete" }) // henüz claimable değil
    }

    @Test func missionLifecycleSkippedForKindWithoutRegistryMissionType() async {
        // linkAccount registry mission_type taksonomisinde YOK → mission_progress/mission_complete atılmaz.
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "link", kind: .linkAccount, target: 1, progress: 0, state: .inProgress)
        ]))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        catalog.set(.success([.mock(id: "link", kind: .linkAccount, target: 1, progress: 1, state: .claimable)]))
        await model.retry()
        #expect(!analytics.events.contains { $0.name == "mission_progress" })
        #expect(!analytics.events.contains { $0.name == "mission_complete" })
    }

    // MARK: - mission_view: görev listesi görünür olduğunda

    @Test func missionViewEmittedOnLoadWithVisibleMissions() async {
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "a", kind: .watchMinutes),
            .mock(id: "b", kind: .favoriteSeries),
            .mock(id: "u", kind: .unknown("completeEpisodes")) // bilinmeyen düşer
        ]))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        let event = analytics.events.first { $0.name == "mission_view" }
        #expect(event?.parameters["mission_ids"] == .string("a,b"))
        #expect(event?.parameters["mission_count"] == .int(2))
    }

    // MARK: - F2 watchAd flag gate (SS-113): rewarded ad KAPALI iken watchAd render edilmez

    @Test func watchAdMissionHiddenWhenRewardedAdFlagDisabled() async {
        // F1 varsayılan: flag KAPALI → watchAd görevi mission listesinde RENDER EDİLMEZ.
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "watch", kind: .watchMinutes, state: .inProgress),
            .mock(id: "ad", kind: .watchAd, rewardCoins: 30, state: .claimable)
        ]))
        let model = makeModel(taskCatalog: catalog)
        model.onAppear()
        await model.pendingWork()
        #expect(model.taskItems.map(\.id) == ["watch"]) // watchAd düştü
        #expect(model.claimableTaskCount == 0) // gizli watchAd claimable sayılmaz
    }

    @Test func watchAdMissionVisibleWhenRewardedAdFlagEnabled() async {
        let flags = MockFeatureFlags()
        flags.set(true, for: RewardsFlags.rewardedAdCard)
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "watch", kind: .watchMinutes, state: .inProgress),
            .mock(id: "ad", kind: .watchAd, rewardCoins: 30, state: .claimable)
        ]))
        let model = makeModel(taskCatalog: catalog, flags: flags)
        model.onAppear()
        await model.pendingWork()
        #expect(model.taskItems.map(\.id) == ["watch", "ad"]) // flag açık → watchAd görünür
        #expect(model.claimableTaskCount == 1)
    }

    @Test func missionViewExcludesWatchAdWhenFlagDisabled() async {
        // mission_view id listesi de flag KAPALIYKEN watchAd'ı içermez (visibleTasks tek kaynak).
        let catalog = FakeTaskCatalog(.success([
            .mock(id: "watch", kind: .watchMinutes),
            .mock(id: "ad", kind: .watchAd, state: .claimable)
        ]))
        let analytics = MockAnalytics()
        let model = makeModel(taskCatalog: catalog, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        let event = analytics.events.first { $0.name == "mission_view" }
        #expect(event?.parameters["mission_ids"] == .string("watch"))
        #expect(event?.parameters["mission_count"] == .int(1))
    }
}
