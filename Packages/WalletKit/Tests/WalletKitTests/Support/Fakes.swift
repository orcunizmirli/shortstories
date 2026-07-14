import AppFoundation
import Foundation
@testable import WalletKit

// Test fake'leri (StoreKit config dosyası OLMADAN çalışır): portlar arkasına alınan StoreKit
// ve backend erişimi burada kontrollü sonuçlarla simüle edilir.

// MARK: - Backend portu

final class FakeWalletRemote: WalletRemoting, @unchecked Sendable {
    private let lock = NSLock()

    // Programlanabilir sonuçlar
    var walletResult: Result<WalletSnapshot, AppError>
    var subscriptionResult: Result<SubscriptionStatus, AppError>
    var packagesResult: Result<CoinPackageCatalog, AppError>
    var unlockResults: [Result<UnlockOutcome, AppError>] = []
    var verifyResults: [Result<VerifyOutcome, AppError>] = []

    // Yavaşlatma kancaları (eşzamanlılık testleri için): çağrıda beklet.
    var verifyGate: (@Sendable () async -> Void)?
    var unlockGate: (@Sendable () async -> Void)?

    /// Spy
    struct UnlockCall: Sendable {
        let episodeID: EpisodeID
        let expectedPrice: Int
        let key: String
    }

    struct VerifyCall: Sendable {
        let productID: String
        let jws: String
        let key: String
    }

    private(set) var unlockCalls: [UnlockCall] = []
    private(set) var verifyCalls: [VerifyCall] = []
    private(set) var fetchWalletCount = 0
    private(set) var fetchSubscriptionCount = 0

    init(
        wallet: WalletSnapshot = .fixture(),
        subscription: SubscriptionStatus = .none,
        packages: CoinPackageCatalog = .fixture()
    ) {
        walletResult = .success(wallet)
        subscriptionResult = .success(subscription)
        packagesResult = .success(packages)
    }

    func fetchWallet() async throws -> WalletSnapshot {
        lock.withLock { fetchWalletCount += 1 }
        return try lock.withLock { walletResult }.get()
    }

    func fetchSubscription() async throws -> SubscriptionStatus {
        lock.withLock { fetchSubscriptionCount += 1 }
        return try lock.withLock { subscriptionResult }.get()
    }

    func fetchPackages() async throws -> CoinPackageCatalog {
        try lock.withLock { packagesResult }.get()
    }

    func unlock(episodeID: EpisodeID, expectedPrice: Int, idempotencyKey: String) async throws -> UnlockOutcome {
        lock.withLock {
            unlockCalls.append(UnlockCall(episodeID: episodeID, expectedPrice: expectedPrice, key: idempotencyKey))
        }
        if let gate = unlockGate {
            await gate()
        }
        let next: Result<UnlockOutcome, AppError> = lock.withLock {
            unlockResults.isEmpty ? .failure(.unexpected(underlying: "no unlock stub")) : unlockResults.removeFirst()
        }
        return try next.get()
    }

    func verifyPurchase(
        productID: String,
        jws: String,
        kind: PurchaseKind,
        idempotencyKey: String
    ) async throws -> VerifyOutcome {
        lock.withLock {
            verifyCalls.append(VerifyCall(productID: productID, jws: jws, key: idempotencyKey))
        }
        if let gate = verifyGate {
            await gate()
        }
        let next: Result<VerifyOutcome, AppError> = lock.withLock {
            verifyResults.isEmpty ? .failure(.unexpected(underlying: "no verify stub")) : verifyResults.removeFirst()
        }
        return try next.get()
    }

    var verifyCallCount: Int {
        lock.withLock { verifyCalls.count }
    }

    var unlockCallCount: Int {
        lock.withLock { unlockCalls.count }
    }
}

/// Deterministik eşzamanlılık kapısı: `wait()` çağrıları `open()` gelene dek asılı kalır.
actor AsyncGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }
}

// MARK: - StoreKit portları

final class FakeProductProvider: ProductProviding, @unchecked Sendable {
    var result: Result<[StoreProduct], AppError>
    private(set) var requestedIDs: [[String]] = []
    private let lock = NSLock()

    init(products: [StoreProduct] = []) {
        result = .success(products)
    }

    func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        lock.withLock { requestedIDs.append(ids) }
        return try lock.withLock { result }.get()
    }
}

final class FakePurchaseService: PurchaseServicing, @unchecked Sendable {
    private let lock = NSLock()

    var purchaseResult: Result<PurchaseResult, AppError> = .success(.userCancelled)
    private var unfinished: [VerifiedTransaction] = []
    private var entitlements: [VerifiedTransaction] = []
    private(set) var finishedIDs: [UInt64] = []
    private(set) var syncCount = 0
    var syncResult: Result<Void, AppError> = .success(())

    private let updatesStream: AsyncStream<VerifiedTransaction>
    private let updatesContinuation: AsyncStream<VerifiedTransaction>.Continuation

    init() {
        (updatesStream, updatesContinuation) = AsyncStream<VerifiedTransaction>.makeStream()
    }

    func setUnfinished(_ transactions: [VerifiedTransaction]) {
        lock.withLock { unfinished = transactions }
    }

    func setEntitlements(_ transactions: [VerifiedTransaction]) {
        lock.withLock { entitlements = transactions }
    }

    func emit(_ transaction: VerifiedTransaction) {
        updatesContinuation.yield(transaction)
    }

    func finishUpdates() {
        updatesContinuation.finish()
    }

    func purchase(productID: String, appAccountToken: UUID) async throws -> PurchaseResult {
        try lock.withLock { purchaseResult }.get()
    }

    func finish(transactionID: UInt64) async {
        lock.withLock {
            finishedIDs.append(transactionID)
            unfinished.removeAll { $0.id == transactionID }
        }
    }

    func unfinishedTransactions() async -> [VerifiedTransaction] {
        lock.withLock { unfinished }
    }

    func transactionUpdates() -> AsyncStream<VerifiedTransaction> {
        updatesStream
    }

    func currentEntitlements() async -> [VerifiedTransaction] {
        lock.withLock { entitlements }
    }

    func sync() async throws {
        lock.withLock { syncCount += 1 }
        try lock.withLock { syncResult }.get()
    }

    var finished: [UInt64] {
        lock.withLock { finishedIDs }
    }

    var isFinished: (UInt64) -> Bool {
        { id in self.lock.withLock { self.finishedIDs.contains(id) } }
    }
}

// MARK: - Fixture kurucular

extension WalletSnapshot {
    static func fixture(
        purchased: Int = 0,
        earned: Int = 0,
        firstTopUpEligible: Bool = false,
        version: Int = 1
    ) -> WalletSnapshot {
        WalletSnapshot(
            balance: CoinBalance(purchasedCoins: purchased, earnedCoins: earned),
            earnedExpiringSoon: nil,
            firstTopUpEligible: firstTopUpEligible,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            version: version
        )
    }
}

extension SubscriptionStatus {
    static func vip(
        plan: Plan = .weekly,
        expiresAt: Date? = Date(timeIntervalSince1970: 1_800_000_000),
        grace: Bool = false,
        willAutoRenew: Bool = true,
        updatedAt: Date? = nil
    ) -> SubscriptionStatus {
        SubscriptionStatus(
            isVIP: true,
            plan: plan,
            expiresAt: expiresAt,
            willAutoRenew: willAutoRenew,
            isInGracePeriod: grace,
            isInIntroOffer: false,
            dailyBonusCoins: 50,
            dailyBonusClaimedToday: false,
            updatedAt: updatedAt
        )
    }
}

extension UnlockRecord {
    static func fixture(
        episode: String = "ep_1",
        series: String = "srs_1",
        method: Method = .coins,
        coinsSpent: Int = 60
    ) -> UnlockRecord {
        UnlockRecord(
            id: "ulk_\(episode)",
            episodeID: EpisodeID(episode),
            seriesID: SeriesID(series),
            method: method,
            coinsSpent: coinsSpent,
            unlockedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }
}

extension CoinPackageCatalog {
    static func fixture() -> CoinPackageCatalog {
        CoinPackageCatalog(
            packages: [
                CoinPackage(
                    productId: "com.shortseries.coins.tier1",
                    baseCoins: 100,
                    bonusPercent: 0,
                    bonusCoins: 0,
                    firstTopUpBonusCoins: 100,
                    badge: nil
                )
            ],
            firstTopUpEligible: true,
            ttlSec: 600
        )
    }
}

extension VerifiedTransaction {
    static func fixture(
        id: UInt64 = 1001,
        original: UInt64 = 1001,
        productID: String = "com.shortseries.coins.tier3",
        kind: PurchaseKind = .consumable,
        revoked: Date? = nil,
        ownership: OwnershipType = .purchased
    ) -> VerifiedTransaction {
        VerifiedTransaction(
            id: id,
            originalID: original,
            productID: productID,
            jws: "jws-\(id)",
            kind: kind,
            purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
            expirationDate: nil,
            revocationDate: revoked,
            isUpgraded: false,
            appAccountToken: nil,
            ownershipType: ownership
        )
    }
}

extension StoreProduct {
    static func coin(id: String, price: Decimal, displayPrice: String) -> StoreProduct {
        StoreProduct(
            id: id,
            displayName: "Coins",
            displayPrice: displayPrice,
            price: price,
            kind: .coinPack,
            subscription: nil
        )
    }

    static func vip(
        id: String,
        displayPrice: String,
        eligibleIntro: Bool,
        intro: IntroOffer?
    ) -> StoreProduct {
        StoreProduct(
            id: id,
            displayName: "VIP",
            displayPrice: displayPrice,
            price: 5.99,
            kind: .subscription,
            subscription: SubscriptionInfo(
                isEligibleForIntroOffer: eligibleIntro,
                introOffer: intro,
                periodUnit: .week,
                periodValue: 1
            )
        )
    }
}
