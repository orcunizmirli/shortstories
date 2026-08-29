import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import RewardsKit

/// RWD-07 OdulMerkezi davet (referral) giriş kartı: `RewardsFlags.referralCard` görünürlük gate'i
/// (varsayılan KAPALI → yapı ships, kullanıcıya gizli) + `openReferral()` navigasyon niyeti (delegate).
@MainActor
@Suite("RWD-07 OdulMerkezi davet giriş kartı")
struct OdulMerkeziReferralCardTests {
    private func makeModel(
        flags: MockFeatureFlags = MockFeatureFlags(),
        delegate: RewardsDelegateSpy = RewardsDelegateSpy()
    ) -> OdulMerkeziModel {
        OdulMerkeziModel(
            checkInService: FakeCheckInService(),
            wallet: FakeRewardsWallet(100),
            taskCatalog: FakeTaskCatalog(),
            taskProgress: FakeTaskProgress(),
            rewardClaiming: FakeRewardClaiming(),
            analytics: MockAnalytics(),
            featureFlags: flags,
            delegate: delegate
        )
    }

    @Test func referralCardHiddenByDefault() {
        let model = makeModel()
        #expect(model.referralCardVisible == false)
    }

    @Test func referralCardVisibleWhenFlagEnabled() {
        let flags = MockFeatureFlags()
        flags.set(true, for: RewardsFlags.referralCard)
        let model = makeModel(flags: flags)
        #expect(model.referralCardVisible == true)
    }

    @Test func openReferralFiresDelegate() {
        let delegate = RewardsDelegateSpy()
        let model = makeModel(delegate: delegate)
        model.openReferral()
        #expect(delegate.referral == 1)
    }
}
