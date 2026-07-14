import AppFoundation
import AppFoundationTestSupport
import Foundation
@testable import WalletKit

extension MockAnalytics.Event {
    /// `.double` parametresini çıkarır (float eşitliği yerine tolerans karşılaştırması için).
    /// Decimal→Double dönüşümü (ör. 49.99 → 49.9899…) ham literal'den farklı olabildiğinden
    /// fiyat parametreleri tam eşitlikle değil toleransla doğrulanır.
    func double(_ key: String) -> Double? {
        if case let .double(value)? = parameters[key] {
            return value
        }
        return nil
    }
}

// UI dilimi (UnlockSheet/CoinMagazasi/VIPAbonelik) modelleri için test fake'leri. Portlar
// arkasına alınan cüzdan/satın alma/katalog erişimi burada kontrollü sonuçlarla simüle edilir.

// MARK: - WalletGateway fake

final class FakeWalletGateway: WalletGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var _balance: CoinBalance
    private var _snapshot: WalletSnapshot
    private var _subscription: SubscriptionStatus
    private var _unlocked: Set<EpisodeID> = []

    var unlockResults: [UnlockResult] = []
    private(set) var unlockCalls: [(episodeID: EpisodeID, price: Int)] = []
    private(set) var snapshotReads = 0

    /// Eşzamanlılık kancaları: seed okumasını / unlock çağrısını beklet (askıya al).
    var readGate: (@Sendable () async -> Void)?
    var unlockGate: (@Sendable () async -> Void)?

    private let balanceCast = AsyncMulticast<CoinBalance>()
    private let entitlementCast = AsyncMulticast<EntitlementSnapshot>()

    init(
        balance: CoinBalance = .zero,
        snapshot: WalletSnapshot = .fixture(),
        subscription: SubscriptionStatus = .none
    ) {
        _balance = balance
        _snapshot = snapshot
        _subscription = subscription
        balanceCast.send(balance)
    }

    func currentBalance() async -> CoinBalance {
        lock.withLock { snapshotReads += 1 }
        if let gate = readGate {
            await gate()
        }
        return lock.withLock { _balance }
    }

    func currentSnapshot() async -> WalletSnapshot {
        lock.withLock { snapshotReads += 1 }
        if let gate = readGate {
            await gate()
        }
        return lock.withLock { _snapshot }
    }

    func subscriptionStatus() async -> SubscriptionStatus {
        lock.withLock { snapshotReads += 1 }
        if let gate = readGate {
            await gate()
        }
        return lock.withLock { _subscription }
    }

    func isEpisodeUnlocked(_ episodeID: EpisodeID) async -> Bool {
        lock.withLock { _unlocked.contains(episodeID) }
    }

    func unlock(episodeID: EpisodeID, expectedPrice: Int) async -> UnlockResult {
        lock.withLock { unlockCalls.append((episodeID, expectedPrice)) }
        if let gate = unlockGate {
            await gate()
        }
        return lock.withLock {
            unlockResults.isEmpty
                ? .failed(.unexpected(underlying: "no unlock stub"))
                : unlockResults.removeFirst()
        }
    }

    func balanceUpdates() -> AsyncStream<CoinBalance> {
        balanceCast.subscribe()
    }

    func entitlementUpdates() -> AsyncStream<EntitlementSnapshot> {
        entitlementCast.subscribe()
    }

    /// Test kancaları
    func pushBalance(_ balance: CoinBalance) {
        lock.withLock { _balance = balance }
        balanceCast.send(balance)
    }

    func pushEntitlement(_ snapshot: EntitlementSnapshot) {
        entitlementCast.send(snapshot)
    }

    func setSubscription(_ status: SubscriptionStatus) {
        lock.withLock { _subscription = status }
    }

    var unlockCallCount: Int {
        lock.withLock { unlockCalls.count }
    }
}

// MARK: - WalletPurchasing fake

final class FakeWalletPurchasing: WalletPurchasing, @unchecked Sendable {
    private let lock = NSLock()
    var purchaseResults: [PurchaseFlowResult] = []
    var restoreResult: Result<Void, AppError> = .success(())
    private(set) var purchasedProductIDs: [String] = []
    private(set) var restoreCount = 0
    var purchaseGate: (@Sendable () async -> Void)?

    func purchase(productID: String) async -> PurchaseFlowResult {
        lock.withLock { purchasedProductIDs.append(productID) }
        if let gate = purchaseGate {
            await gate()
        }
        return lock.withLock {
            purchaseResults.isEmpty ? .failed(.unexpected(underlying: "no purchase stub")) : purchaseResults.removeFirst()
        }
    }

    func restore() async throws {
        lock.withLock { restoreCount += 1 }
        try lock.withLock { restoreResult }.get()
    }

    var purchaseCallCount: Int {
        lock.withLock { purchasedProductIDs.count }
    }
}

// MARK: - StorefrontLoading fake

final class FakeStorefrontLoader: StorefrontLoading, @unchecked Sendable {
    private let lock = NSLock()
    var packagesResult: Result<CoinPackageCatalog, AppError>
    var productsResult: Result<[StoreProduct], AppError>
    private(set) var requestedProductIDs: [[String]] = []

    init(
        packages: Result<CoinPackageCatalog, AppError> = .success(.fixture()),
        products: Result<[StoreProduct], AppError> = .success([])
    ) {
        packagesResult = packages
        productsResult = products
    }

    func fetchPackages() async throws -> CoinPackageCatalog {
        try lock.withLock { packagesResult }.get()
    }

    func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        lock.withLock { requestedProductIDs.append(ids) }
        return try lock.withLock { productsResult }.get()
    }
}

// MARK: - Kaydeden delegate'ler

@MainActor
final class SpyUnlockSheetDelegate: UnlockSheetDelegate {
    private(set) var unlocked: [EpisodeID] = []
    private(set) var coinStoreRequests = 0
    private(set) var vipRequests = 0
    private(set) var dismissals = 0
    private(set) var autoUnlockWrites: [(enabled: Bool, seriesID: SeriesID)] = []

    func unlockSheetDidUnlock(episodeID: EpisodeID) {
        unlocked.append(episodeID)
    }

    func unlockSheetRequestsCoinStore() {
        coinStoreRequests += 1
    }

    func unlockSheetRequestsVIP() {
        vipRequests += 1
    }

    func unlockSheetDidDismiss() {
        dismissals += 1
    }

    func unlockSheet(setAutoUnlock enabled: Bool, seriesID: SeriesID) {
        autoUnlockWrites.append((enabled, seriesID))
    }
}

@MainActor
final class SpyCoinShopDelegate: CoinShopDelegate {
    private(set) var purchaseCompletions = 0
    private(set) var dismissals = 0

    func coinShopDidCompletePurchase() {
        purchaseCompletions += 1
    }

    func coinShopRequestsDismiss() {
        dismissals += 1
    }
}

@MainActor
final class SpyVIPSubscriptionDelegate: VIPSubscriptionDelegate {
    private(set) var activations = 0
    private(set) var manageRequests = 0
    private(set) var dismissals = 0

    func vipSubscriptionDidActivate() {
        activations += 1
    }

    func vipSubscriptionRequestsManagement() {
        manageRequests += 1
    }

    func vipSubscriptionRequestsDismiss() {
        dismissals += 1
    }
}

// MARK: - Fixture yardımcıları

extension StoreProduct {
    static func vipWeekly(displayPrice: String = "$5.99", eligibleIntro: Bool = false, intro: IntroOffer? = nil) -> StoreProduct {
        .vip(id: SubscriptionPlan.weekly.productID, displayPrice: displayPrice, eligibleIntro: eligibleIntro, intro: intro)
    }

    static func vipMonthly(displayPrice: String = "$14.99") -> StoreProduct {
        StoreProduct(
            id: SubscriptionPlan.monthly.productID,
            displayName: "VIP Monthly",
            displayPrice: displayPrice,
            price: 14.99,
            kind: .subscription,
            subscription: SubscriptionInfo(isEligibleForIntroOffer: false, introOffer: nil, periodUnit: .month, periodValue: 1)
        )
    }

    static func vipYearly(displayPrice: String = "$49.99") -> StoreProduct {
        StoreProduct(
            id: SubscriptionPlan.yearly.productID,
            displayName: "VIP Yearly",
            displayPrice: displayPrice,
            price: 49.99,
            kind: .subscription,
            subscription: SubscriptionInfo(isEligibleForIntroOffer: false, introOffer: nil, periodUnit: .year, periodValue: 1)
        )
    }
}

extension IntroOffer {
    static let weeklyThreeNinetyNine = IntroOffer(
        displayPrice: "$3.99",
        paymentMode: .payUpFront,
        periodUnit: .week,
        periodValue: 1,
        periodCount: 1
    )
}
