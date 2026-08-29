import Foundation

/// Deterministik bellek-içi referral gateway — SwiftUI preview + `AppComposition` flag-KAPALI yol
/// (canlı `/rewards/referral` endpoint'i henüz YOK; PREP-BEKLEYEN). Testler kendi programlanabilir
/// `FakeReferralGateway`'ini kullanır — bu tip yalnız sabit önizleme verisi sağlar.
public struct MockReferralGateway: ReferralGateway {
    private let statusResult: ReferralStatus
    private let redeemResult: ReferralRedeemOutcome

    public init(
        status: ReferralStatus = .previewMock,
        redeem: ReferralRedeemOutcome = .credited(
            reward: ClaimedReward(coins: 50, isStreakBonus: false, expiresAt: nil),
            referral: .previewMockRedeemed
        )
    ) {
        statusResult = status
        redeemResult = redeem
    }

    public func status() async throws -> ReferralStatus {
        statusResult
    }

    public func redeem(code _: String) async throws -> ReferralRedeemOutcome {
        redeemResult
    }
}

public extension ReferralStatus {
    /// Önizleme durumu — kod kullanılabilir (`canRedeem: true`).
    static let previewMock = ReferralStatus(
        inviteCode: "DRAMA-7Q2X",
        inviteURL: URL(string: "https://shortseries.app/r/DRAMA-7Q2X"),
        invitedCount: 5,
        rewardedCount: 3,
        pendingCount: 2,
        rewardPerReferral: 50,
        maxReferrals: 20,
        canRedeem: true
    )

    /// Redeem sonrası önizleme durumu — kod artık kullanılamaz (`canRedeem: false`).
    static let previewMockRedeemed = ReferralStatus(
        inviteCode: "DRAMA-7Q2X",
        inviteURL: URL(string: "https://shortseries.app/r/DRAMA-7Q2X"),
        invitedCount: 5,
        rewardedCount: 3,
        pendingCount: 2,
        rewardPerReferral: 50,
        maxReferrals: 20,
        canRedeem: false
    )
}
