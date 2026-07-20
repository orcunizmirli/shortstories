import Foundation
@testable import RewardsKit

// MARK: - Rewarded ad SDK portu fake'i (SS-113; programlanabilir fill/outcome + çağrı sayaçları)

final class MockRewardedAdProvider: RewardedAdProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var fill: Bool
    private var outcome: AdWatchOutcome
    private var preloads = 0
    private var shows = 0

    init(fill: Bool = true, outcome: AdWatchOutcome = .completed(.mock())) {
        self.fill = fill
        self.outcome = outcome
    }

    var preloadCount: Int {
        lock.withLock { preloads }
    }

    var showCount: Int {
        lock.withLock { shows }
    }

    func setFill(_ value: Bool) {
        lock.withLock { fill = value }
    }

    func setOutcome(_ value: AdWatchOutcome) {
        lock.withLock { outcome = value }
    }

    func preload() async {
        lock.withLock { preloads += 1 }
    }

    func isAdAvailable() async -> Bool {
        lock.withLock { fill }
    }

    func showAd() async -> AdWatchOutcome {
        lock.withLock {
            shows += 1
            return outcome
        }
    }
}

// MARK: - Ad-unlock gateway portu fake'i (SS-113; programlanabilir sonuç + istek kaydı)

final class MockAdUnlockGateway: AdUnlockGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<AdUnlockOutcome, Error>
    private var received: [AdUnlockRequest] = []

    init(_ result: Result<AdUnlockOutcome, Error> = .success(.mock())) {
        self.result = result
    }

    var requestCount: Int {
        lock.withLock { received.count }
    }

    var lastRequest: AdUnlockRequest? {
        lock.withLock { received.last }
    }

    func set(_ result: Result<AdUnlockOutcome, Error>) {
        lock.withLock { self.result = result }
    }

    func requestAdUnlock(_ request: AdUnlockRequest) async throws -> AdUnlockOutcome {
        let result = lock.withLock { () -> Result<AdUnlockOutcome, Error> in
            received.append(request)
            return self.result
        }
        return try result.get()
    }
}

// MARK: - SS-113 rewarded ads mock builder'ları

extension RewardProof {
    static func mock(
        provider: String = "admob",
        nonce: String = "adn_84f2",
        proofPayload: [String: String] = ["signature": "sig_opaque"]
    ) -> RewardProof {
        RewardProof(provider: provider, nonce: nonce, proofPayload: proofPayload)
    }
}

extension AdUnlockOutcome {
    static func mock(
        target: AdRewardTarget = .episode(id: "ep_5410bf"),
        remainingToday: Int? = 4,
        coinBalance: Int? = nil
    ) -> AdUnlockOutcome {
        AdUnlockOutcome(target: target, remainingToday: remainingToday, coinBalance: coinBalance)
    }
}
