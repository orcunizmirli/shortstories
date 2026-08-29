import Foundation
@testable import RewardsKit

// MARK: - Referral gateway portu fake'i (programlanabilir status/redeem sonuçları + çağrı sayaçları)

final class FakeReferralGateway: ReferralGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var statusResult: Result<ReferralStatus, Error>
    private var redeemResult: Result<ReferralRedeemOutcome, Error>
    private var statusCalls = 0
    private var redeemedCodes: [String] = []

    init(
        status: Result<ReferralStatus, Error> = .success(.mock()),
        redeem: Result<ReferralRedeemOutcome, Error> = .success(
            .credited(
                reward: ClaimedReward(coins: 50, isStreakBonus: false, expiresAt: nil),
                referral: .mock(canRedeem: false)
            )
        )
    ) {
        statusResult = status
        redeemResult = redeem
    }

    var statusCallCount: Int {
        lock.withLock { statusCalls }
    }

    var redeemCallCount: Int {
        lock.withLock { redeemedCodes.count }
    }

    var lastRedeemedCode: String? {
        lock.withLock { redeemedCodes.last }
    }

    func setStatus(_ result: Result<ReferralStatus, Error>) {
        lock.withLock { statusResult = result }
    }

    func setRedeem(_ result: Result<ReferralRedeemOutcome, Error>) {
        lock.withLock { redeemResult = result }
    }

    func status() async throws -> ReferralStatus {
        let result = lock.withLock { () -> Result<ReferralStatus, Error> in
            statusCalls += 1
            return statusResult
        }
        return try result.get()
    }

    func redeem(code: String) async throws -> ReferralRedeemOutcome {
        let result = lock.withLock { () -> Result<ReferralRedeemOutcome, Error> in
            redeemedCodes.append(code)
            return redeemResult
        }
        return try result.get()
    }
}

// MARK: - Referral navigasyon delegate spy'ı

@MainActor
final class ReferralDelegateSpy: ReferralDelegate {
    private(set) var shares: [(code: String, url: URL?)] = []

    var lastShare: (code: String, url: URL?)? {
        shares.last
    }

    func referralSharesInvite(code: String, url: URL?) {
        shares.append((code, url))
    }
}

// MARK: - Mock builder

extension ReferralStatus {
    static func mock(
        inviteCode: String = "DRAMA-7Q2X",
        inviteURL: URL? = URL(string: "https://shortseries.app/r/DRAMA-7Q2X"),
        invitedCount: Int = 5,
        rewardedCount: Int = 3,
        pendingCount: Int = 2,
        rewardPerReferral: Int = 50,
        maxReferrals: Int? = 20,
        canRedeem: Bool = true
    ) -> ReferralStatus {
        ReferralStatus(
            inviteCode: inviteCode,
            inviteURL: inviteURL,
            invitedCount: invitedCount,
            rewardedCount: rewardedCount,
            pendingCount: pendingCount,
            rewardPerReferral: rewardPerReferral,
            maxReferrals: maxReferrals,
            canRedeem: canRedeem
        )
    }
}
