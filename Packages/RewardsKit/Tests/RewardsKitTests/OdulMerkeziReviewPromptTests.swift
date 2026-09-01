import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import RewardsKit

/// RTG-01 (00-genel-bakis.md §294): başarılı check-in claim'i POZİTİF an'dır → `RewardsDelegate`'e
/// bildirilir; App koordinatörü bunu `ReviewPromptController`'a iletip App Store puanlama istemini
/// terbiyeli sıklıkla değerlendirir. Yalnız GERÇEK claim bildirir (idempotent/guard yolları değil).
@MainActor
@Suite("RTG-01 check-in → puanlama pozitif anı")
struct OdulMerkeziReviewPromptTests {
    private func makeModel(
        service: FakeCheckInService,
        delegate: RewardsDelegateSpy,
        wallet: FakeRewardsWallet = FakeRewardsWallet(100)
    ) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: service,
            wallet: wallet,
            taskCatalog: FakeTaskCatalog(),
            taskProgress: FakeTaskProgress(),
            rewardClaiming: FakeRewardClaiming(),
            analytics: MockAnalytics(),
            featureFlags: MockFeatureFlags(),
            delegate: delegate
        )
    }

    @Test func successfulClaimNotifiesDelegatePositiveMoment() async {
        let claimed = CheckInState.mock(cycleDay: 4, todayClaimed: true, streakDays: 4)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 4, todayClaimed: false, streakDays: 4)),
            claim: .success(.mock(coins: 15, coinBalance: 315, checkin: claimed))
        )
        let delegate = RewardsDelegateSpy()
        let model = makeModel(service: service, delegate: delegate, wallet: FakeRewardsWallet(300))
        model.onAppear()
        await model.pendingWork()

        await model.claimToday()

        #expect(delegate.checkInClaims == [4]) // pozitif an bildirildi (cycleDay taşınır)
    }

    @Test func successfulCheckInClaimCreditsBalanceForWalletRefresh() async {
        // #2 (coin-ekonomisi hunt): claim SERVER-otoriter bakiyeyi kredilendirir ama otoritatif WalletStore'a
        // YANSIMAZ → App'in `WalletStore.refresh()` tetiklemesi için delegate bildirimi gerekir; aksi halde
        // Profil/CoinShop (cüzdan-tabanlı) OdulMerkezi başlığından oturum-içi IRAKSAR.
        let claimed = CheckInState.mock(cycleDay: 4, todayClaimed: true, streakDays: 4)
        let service = FakeCheckInService(
            status: .success(.mock(cycleDay: 4, todayClaimed: false, streakDays: 4)),
            claim: .success(.mock(coins: 15, coinBalance: 315, checkin: claimed))
        )
        let delegate = RewardsDelegateSpy()
        let model = makeModel(service: service, delegate: delegate, wallet: FakeRewardsWallet(300))
        model.onAppear()
        await model.pendingWork()

        await model.claimToday()

        #expect(delegate.creditBalanceCalls == 1) // App bunu alıp WalletStore.refresh tetikler
    }

    @Test func blockedClaimDoesNotNotifyPositiveMoment() async {
        // Zaten claim edilmişse (UI guard) gerçek claim OLMAZ → pozitif an bildirilmez.
        let service = FakeCheckInService(status: .success(.mock(todayClaimed: true)))
        let delegate = RewardsDelegateSpy()
        let model = makeModel(service: service, delegate: delegate)
        model.onAppear()
        await model.pendingWork()

        await model.claimToday()

        #expect(delegate.checkInClaims.isEmpty)
    }
}
