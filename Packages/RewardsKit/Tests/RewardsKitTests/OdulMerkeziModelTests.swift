import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import RewardsKit

/// SS-110/111 `OdulMerkeziModel`: yükleme/durum, coin bakiyesi başlığı, check-in takvimi türetimi,
/// SERVER-OTORİTER + idempotent claim, offline/hata, streak kırılması ve analitik registry adları.
@MainActor
@Suite("SS-110/111 OdulMerkeziModel")
struct OdulMerkeziModelTests {
    private func makeModel(
        service: FakeCheckInService = FakeCheckInService(),
        wallet: FakeRewardsWallet = FakeRewardsWallet(100),
        taskCatalog: FakeTaskCatalog = FakeTaskCatalog(),
        taskProgress: FakeTaskProgress = FakeTaskProgress(),
        rewardClaiming: FakeRewardClaiming = FakeRewardClaiming(),
        analytics: MockAnalytics = MockAnalytics(),
        flags: MockFeatureFlags = MockFeatureFlags(),
        delegate: RewardsDelegateSpy = RewardsDelegateSpy()
    ) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: service,
            wallet: wallet,
            taskCatalog: taskCatalog,
            taskProgress: taskProgress,
            rewardClaiming: rewardClaiming,
            analytics: analytics,
            featureFlags: flags,
            delegate: delegate
        )
    }

    // MARK: - Yükleme + durum

    @Test func onAppearTracksScreenView() async {
        let analytics = MockAnalytics()
        let model = makeModel(analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        #expect(analytics.events.contains {
            $0.name == "screen_view" && $0.parameters["screen_name"] == .string("odul_merkezi")
        })
    }

    @Test func loadsBalanceAndCheckInState() async {
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 3, streakDays: 3)))
        let model = makeModel(service: service, wallet: FakeRewardsWallet(250))
        model.onAppear()
        await model.pendingWork()
        #expect(model.loadState == .loaded)
        #expect(model.coinBalance == 250)
        #expect(model.checkInState?.cycleDay == 3)
        #expect(model.streakDays == 3)
        #expect(model.calendar.count == 7)
    }

    @Test func loadEmitsCheckinViewWithRegistryParams() async {
        let analytics = MockAnalytics()
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)))
        let model = makeModel(service: service, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        let view = analytics.events.first { $0.name == "checkin_view" }
        #expect(view?.parameters["current_streak_day"] == .int(3))
        #expect(view?.parameters["can_claim_today"] == .bool(true))
    }

    @Test func loadOfflineSetsOfflineState() async {
        let service = FakeCheckInService(status: .failure(AppError.network(.offline)))
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork()
        #expect(model.loadState == .offline)
        #expect(model.checkInState == nil)
    }

    @Test func loadGenericFailureSetsFailed() async {
        let service = FakeCheckInService(status: .failure(AppError.unexpected(underlying: "boom")))
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork()
        #expect(model.loadState == .failed)
    }

    @Test func retryReloadsAfterFailure() async {
        let service = FakeCheckInService(status: .failure(AppError.network(.timeout)))
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork()
        #expect(model.loadState == .offline)

        service.setStatus(.success(.mock(cycleDay: 1, streakDays: 1)))
        await model.retry()
        #expect(model.loadState == .loaded)
        #expect(model.checkInState?.cycleDay == 1)
    }

    // MARK: - Rewarded ad kartı feature flag (F1 gizli)

    @Test func rewardedAdCardHiddenByDefaultInF1() {
        let model = makeModel()
        #expect(model.rewardedAdCardVisible == false)
    }

    @Test func rewardedAdCardVisibleWhenFlagEnabled() {
        let flags = MockFeatureFlags()
        flags.set(true, for: RewardsFlags.rewardedAdCard)
        let model = makeModel(flags: flags)
        #expect(model.rewardedAdCardVisible == true)
    }

    // MARK: - Takvim türetimi + bonus

    @Test func calendarMarksTodayAndBonus() async {
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 7, todayClaimed: false, streakDays: 7)))
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork()
        #expect(model.calendar[6].status == .today)
        #expect(model.calendar[6].isBonus)
        #expect(model.isStreakBonusDay)
        #expect(model.canClaimToday)
    }

    // MARK: - Claim: SERVER-OTORİTER (optimistik DEĞİL) + idempotent

    @Test func claimCreditsFromServerNotOptimistically() async {
        let claimed = CheckInState.mock(cycleDay: 3, todayClaimed: true, streakDays: 3)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)),
            claim: .success(.mock(coins: 20, coinBalance: 320, checkin: claimed))
        )
        let model = makeModel(service: service, wallet: FakeRewardsWallet(300))
        model.onAppear()
        await model.pendingWork()
        #expect(model.coinBalance == 300) // claim ÖNCESİ: server yanıtı beklenir, iyimser kredi yok

        await model.claimToday()
        #expect(model.coinBalance == 320) // YALNIZ server yanıtından
        #expect(model.checkInState?.todayClaimed == true)
        #expect(model.claimCelebration == 1) // haptic + animasyon tetiği
        #expect(model.claimFailure == nil)
        #expect(model.canClaimToday == false)
    }

    @Test func claimEmitsCheckinClaimWithRegistryParams() async {
        let claimed = CheckInState.mock(cycleDay: 7, todayClaimed: true, streakDays: 7)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 7, todayClaimed: false, streakDays: 7)),
            claim: .success(.mock(coins: 50, isStreakBonus: true, coinBalance: 400, checkin: claimed))
        )
        let analytics = MockAnalytics()
        let model = makeModel(service: service, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        await model.claimToday()
        let claim = analytics.events.first { $0.name == "checkin_claim" }
        #expect(claim?.parameters["streak_day"] == .int(7))
        #expect(claim?.parameters["coin_reward"] == .int(50))
        #expect(claim?.parameters["is_streak_bonus"] == .bool(true))
    }

    @Test func claimBlockedWhenAlreadyClaimedToday() async {
        let service = FakeCheckInService(status: .success(.mock(todayClaimed: true)))
        let model = makeModel(service: service)
        model.onAppear()
        await model.pendingWork()
        #expect(model.canClaimToday == false)

        await model.claimToday()
        #expect(service.claimCallCount == 0) // UI'dan çift-claim tetiklenemez
    }

    @Test func doubleClaimIsIdempotentNoOp() async {
        let claimed = CheckInState.mock(cycleDay: 3, todayClaimed: true, streakDays: 3)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)),
            claim: .success(.mock(coins: 20, coinBalance: 220, checkin: claimed))
        )
        let model = makeModel(service: service, wallet: FakeRewardsWallet(200))
        model.onAppear()
        await model.pendingWork()

        await model.claimToday()
        await model.claimToday() // ikinci claim: todayClaimed artık true → no-op
        #expect(service.claimCallCount == 1)
        #expect(model.coinBalance == 220) // tekrar kredilenmez
        #expect(model.claimCelebration == 1)
    }

    @Test func alreadyClaimed409SilentlyResyncsNoToastNoCredit() async {
        let fresh = CheckInState.mock(cycleDay: 3, todayClaimed: true, streakDays: 3)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 3, todayClaimed: false, streakDays: 3)),
            claim: .failure(CheckInClaimError.alreadyClaimed(fresh))
        )
        let analytics = MockAnalytics()
        let model = makeModel(service: service, wallet: FakeRewardsWallet(200), analytics: analytics)
        model.onAppear()
        await model.pendingWork()

        await model.claimToday()
        #expect(model.checkInState?.todayClaimed == true) // sessiz senkron
        #expect(model.claimFailure == nil) // hata/toast YOK
        #expect(model.coinBalance == 200) // kredilenmez
        #expect(model.claimCelebration == 0)
        #expect(!analytics.events.contains { $0.name == "checkin_claim" })
    }

    @Test func claimOfflineNoCreditShowsFailure() async {
        let service = FakeCheckInService(
            status: .success(.mock(todayClaimed: false)),
            claim: .failure(AppError.network(.offline))
        )
        let model = makeModel(service: service, wallet: FakeRewardsWallet(200))
        model.onAppear()
        await model.pendingWork()

        await model.claimToday()
        #expect(model.claimFailure == .offline)
        #expect(model.coinBalance == 200) // kredilenmez
        #expect(model.checkInState?.todayClaimed == false)
        #expect(model.claimCelebration == 0)
        #expect(model.isClaiming == false)
    }

    @Test func claimGenericFailureNoCredit() async {
        let service = FakeCheckInService(
            status: .success(.mock(todayClaimed: false)),
            claim: .failure(AppError.unexpected(underlying: "boom"))
        )
        let model = makeModel(service: service, wallet: FakeRewardsWallet(200))
        model.onAppear()
        await model.pendingWork()
        await model.claimToday()
        #expect(model.claimFailure == .generic)
        #expect(model.coinBalance == 200)
    }

    @Test func successfulClaimClearsPreviousFailure() async {
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 2, todayClaimed: false, streakDays: 2)),
            claim: .failure(AppError.network(.offline))
        )
        let model = makeModel(service: service, wallet: FakeRewardsWallet(200))
        model.onAppear()
        await model.pendingWork()
        await model.claimToday()
        #expect(model.claimFailure == .offline)

        let claimed = CheckInState.mock(cycleDay: 2, todayClaimed: true, streakDays: 2)
        service.setClaim(.success(.mock(coins: 15, coinBalance: 215, checkin: claimed)))
        await model.claimToday()
        #expect(model.claimFailure == nil)
        #expect(model.coinBalance == 215)
        #expect(model.claimCelebration == 1)
    }

    // MARK: - Streak kırılması analitiği

    @Test func streakBreakEmittedWhenStreakDropsOnRefresh() async {
        let service = FakeCheckInService(status: .success(.mock(cycleDay: 5, todayClaimed: false, streakDays: 5)))
        let analytics = MockAnalytics()
        let model = makeModel(service: service, analytics: analytics)
        model.onAppear()
        await model.pendingWork()
        #expect(!analytics.events.contains { $0.name == "checkin_streak_break" }) // ilk yüklemede yok

        service.setStatus(.success(.mock(cycleDay: 1, todayClaimed: false, streakDays: 0)))
        await model.retry()
        let brk = analytics.events.first { $0.name == "checkin_streak_break" }
        #expect(brk?.parameters["broken_at_day"] == .int(5))
        #expect(brk?.parameters["previous_streak_length"] == .int(5))
    }

    // MARK: - Canlı bakiye akışı

    @Test func walletLiveUpdateReflectedInBalance() async {
        let wallet = FakeRewardsWallet(10)
        let model = makeModel(wallet: wallet)
        model.onAppear()
        await model.pendingWork()
        #expect(model.coinBalance == 10)

        let observer = Task { await model.observeUpdates() }
        defer { observer.cancel() }
        wallet.set(999)
        let updated = await eventually { model.coinBalance == 999 }
        #expect(updated)
    }

    // MARK: - Navigasyon niyeti

    @Test func openCoinStoreInvokesDelegate() async {
        let spy = RewardsDelegateSpy()
        let model = makeModel(delegate: spy)
        model.onAppear()
        await model.pendingWork()
        model.openCoinStore()
        #expect(spy.coinStore == 1)
    }
}
