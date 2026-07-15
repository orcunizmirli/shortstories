import AppFoundation
import Foundation
@testable import RewardsKit

// MARK: - Check-in servisi portu fake'i (programlanabilir status/claim sonuçları + çağrı sayaçları)

final class FakeCheckInService: CheckInService, @unchecked Sendable {
    private let lock = NSLock()
    private var statusResult: Result<CheckInState, Error>
    private var claimResult: Result<CheckInClaimResult, Error>
    private var statusCalls = 0
    private var claimCalls = 0

    init(
        status: Result<CheckInState, Error> = .success(.mock()),
        claim: Result<CheckInClaimResult, Error> = .success(.mock())
    ) {
        statusResult = status
        claimResult = claim
    }

    var statusCallCount: Int {
        lock.withLock { statusCalls }
    }

    var claimCallCount: Int {
        lock.withLock { claimCalls }
    }

    func setStatus(_ result: Result<CheckInState, Error>) {
        lock.withLock { statusResult = result }
    }

    func setClaim(_ result: Result<CheckInClaimResult, Error>) {
        lock.withLock { claimResult = result }
    }

    func status() async throws -> CheckInState {
        let result = lock.withLock { () -> Result<CheckInState, Error> in
            statusCalls += 1
            return statusResult
        }
        return try result.get()
    }

    func claim() async throws -> CheckInClaimResult {
        let result = lock.withLock { () -> Result<CheckInClaimResult, Error> in
            claimCalls += 1
            return claimResult
        }
        return try result.get()
    }
}

// MARK: - Coin bakiyesi portu fake'i (current-value replay'li akış)

final class FakeRewardsWallet: RewardsWalletReading, @unchecked Sendable {
    private let lock = NSLock()
    private var balance: Int
    private let multicast = TestMulticast<Int>()

    init(_ balance: Int = 0) {
        self.balance = balance
        multicast.send(balance)
    }

    /// Testten bakiye değişimi (başka cihazdan satın alma/VIP bonusu) yayınlar.
    func set(_ newValue: Int) {
        lock.withLock { balance = newValue }
        multicast.send(newValue)
    }

    func currentBalance() async -> Int {
        lock.withLock { balance }
    }

    func balanceUpdates() -> AsyncStream<Int> {
        multicast.subscribe()
    }
}

// MARK: - Görev kataloğu portu fake'i (programlanabilir sonuç + çağrı sayacı)

final class FakeTaskCatalog: TaskCatalogProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<[RewardTask], Error>
    private var calls = 0

    init(_ result: Result<[RewardTask], Error> = .success([])) {
        self.result = result
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func set(_ result: Result<[RewardTask], Error>) {
        lock.withLock { self.result = result }
    }

    func tasks() async throws -> [RewardTask] {
        let result = lock.withLock { () -> Result<[RewardTask], Error> in
            calls += 1
            return self.result
        }
        return try result.get()
    }
}

// MARK: - Görev ilerleme portu fake'i (current-value replay'li akış)

final class FakeTaskProgress: TaskProgressReading, @unchecked Sendable {
    private let lock = NSLock()
    private var progress: [RewardTask.Kind: Int]
    private let multicast = TestMulticast<[RewardTask.Kind: Int]>()

    init(_ progress: [RewardTask.Kind: Int] = [:]) {
        self.progress = progress
        multicast.send(progress)
    }

    /// Testten canlı ilerleme (izleme/favori/paylaşım) yayınlar.
    func set(_ newValue: [RewardTask.Kind: Int]) {
        lock.withLock { progress = newValue }
        multicast.send(newValue)
    }

    func currentProgress() async -> [RewardTask.Kind: Int] {
        lock.withLock { progress }
    }

    func progressUpdates() -> AsyncStream<[RewardTask.Kind: Int]> {
        multicast.subscribe()
    }
}

// MARK: - Görev claim portu fake'i (programlanabilir sonuç + çağrı sayacı)

final class FakeRewardClaiming: RewardClaiming, @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<RewardTaskClaimResult, Error>
    private var claimedIDs: [String] = []

    init(_ result: Result<RewardTaskClaimResult, Error> = .success(.mock())) {
        self.result = result
    }

    var claimCallCount: Int {
        lock.withLock { claimedIDs.count }
    }

    var lastClaimedID: String? {
        lock.withLock { claimedIDs.last }
    }

    func set(_ result: Result<RewardTaskClaimResult, Error>) {
        lock.withLock { self.result = result }
    }

    func claimTask(id: String) async throws -> RewardTaskClaimResult {
        let result = lock.withLock { () -> Result<RewardTaskClaimResult, Error> in
            claimedIDs.append(id)
            return self.result
        }
        return try result.get()
    }
}

// MARK: - Navigasyon delegate spy'ı

@MainActor
final class RewardsDelegateSpy: RewardsDelegate {
    var coinStore = 0

    func rewardsOpensCoinStore() {
        coinStore += 1
    }
}

// MARK: - Minimal current-value multicast (WalletKit/ProfileKit AsyncMulticast sözleşmesi; R2 kopya)

final class TestMulticast<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var latest: Element?

    func subscribe() -> AsyncStream<Element> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.withLock {
                continuations[id] = continuation
                if let latest {
                    continuation.yield(latest)
                }
            }
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { _ = self?.continuations.removeValue(forKey: id) }
            }
        }
    }

    func send(_ element: Element) {
        let active = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
            latest = element
            return Array(continuations.values)
        }
        for continuation in active {
            continuation.yield(element)
        }
    }
}

// MARK: - Deterministik akış bekleme (MainActor executor'da yield ederek gözlem görevini işler)

@MainActor
func eventually(iterations: Int = 500, _ condition: () -> Bool) async -> Bool {
    for _ in 0 ..< iterations {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}

// MARK: - Mock builder'lar

extension CheckInState {
    static func mock(
        cycleDay: Int = 3,
        todayClaimed: Bool = false,
        todayReward: Int = 20,
        streakDays: Int = 3,
        schedule: [DayReward]? = nil,
        streakBonusAt: Int? = nil,
        streakBonusCoins: Int? = nil
    ) -> CheckInState {
        let defaultSchedule = (1 ... CheckInCycle.length).map { day in
            DayReward(day: day, coins: CheckInCycle.defaultRewards[day - 1], claimed: day < cycleDay)
        }
        return CheckInState(
            cycleDay: cycleDay,
            todayClaimed: todayClaimed,
            todayReward: todayReward,
            schedule: schedule ?? defaultSchedule,
            streakDays: streakDays,
            streakBonusAt: streakBonusAt,
            streakBonusCoins: streakBonusCoins
        )
    }
}

extension CheckInClaimResult {
    static func mock(
        coins: Int = 20,
        isStreakBonus: Bool = false,
        coinBalance: Int = 120,
        checkin: CheckInState = .mock(todayClaimed: true)
    ) -> CheckInClaimResult {
        CheckInClaimResult(
            reward: ClaimedReward(coins: coins, isStreakBonus: isStreakBonus, expiresAt: nil),
            checkin: checkin,
            coinBalance: coinBalance
        )
    }
}

extension RewardTask {
    static func mock(
        id: String = "msn_watch10",
        kind: Kind = .watchMinutes,
        title: String = "10 dakika izle",
        rewardCoins: Int = 20,
        target: Int = 10,
        progress: Int = 4,
        state: State = .inProgress,
        resetPolicy: ResetPolicy = .daily,
        expiresAt: Date? = nil
    ) -> RewardTask {
        RewardTask(
            id: id,
            kind: kind,
            title: title,
            rewardCoins: rewardCoins,
            target: target,
            progress: progress,
            state: state,
            resetPolicy: resetPolicy,
            expiresAt: expiresAt
        )
    }
}

extension RewardTaskClaimResult {
    static func mock(
        coins: Int = 20,
        coinBalance: Int = 140,
        expiresAt: Date? = nil,
        task: RewardTask = .mock(progress: 10, state: .claimed)
    ) -> RewardTaskClaimResult {
        RewardTaskClaimResult(
            reward: ClaimedReward(coins: coins, isStreakBonus: false, expiresAt: expiresAt),
            task: task,
            coinBalance: coinBalance
        )
    }
}
