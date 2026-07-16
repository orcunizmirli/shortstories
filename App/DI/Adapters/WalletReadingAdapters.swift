import Foundation
import ProfileKit
import RewardsKit
import WalletKit

// Cüzdan OKUMA portlarının canlı adaptörleri (03 §5.1, R8). RewardsKit `RewardsWalletReading` ve
// ProfileKit `WalletSummaryReading` tüketici-tarafında tanımlıdır; App onları WalletKit
// `WalletGateway` (canlı: `WalletStore`) ÜRETİCİSİNE köprüler. Feature'lar WalletKit tiplerini
// (`CoinBalance`/`SubscriptionStatus`) GÖRMEZ — dönüşüm burada, saf ve izole test edilebilir.

/// RewardsKit `RewardsWalletReading` → WalletKit `WalletGateway`. Coin bakiyesi başlığı için toplam
/// coin (`purchased + earned`) verir; akışta `CoinBalance` → `Int` map edilir (replay `WalletStore`
/// tarafından, current-value semantiği korunur).
struct WalletGatewayRewardsReading: RewardsWalletReading {
    private let gateway: any WalletGateway

    init(gateway: any WalletGateway) {
        self.gateway = gateway
    }

    func currentBalance() async -> Int {
        await gateway.currentBalance().totalCoins
    }

    func balanceUpdates() -> AsyncStream<Int> {
        AsyncStream<Int>.mapping(gateway.balanceUpdates()) { $0.totalCoins }
    }
}

/// ProfileKit `WalletSummaryReading` → WalletKit `WalletGateway`. Profil hesap satırı için bakiye +
/// VIP + yenileme tarihi özetini verir. `summaryUpdates()` bakiye VE entitlement akışlarını tek
/// `WalletSummary` akışında BİRLEŞTİRİR: ilk snapshot `currentSummary()` ile tohumlanır (replay
/// sözleşmesi), sonra iki akıştan hangisi değişirse birleşik özet yeniden yayınlanır.
struct WalletGatewaySummaryReading: WalletSummaryReading {
    private let gateway: any WalletGateway

    init(gateway: any WalletGateway) {
        self.gateway = gateway
    }

    func currentSummary() async -> WalletSummary {
        await Self.summary(balance: gateway.currentBalance(), subscription: gateway.subscriptionStatus())
    }

    func summaryUpdates() -> AsyncStream<WalletSummary> {
        let gateway = gateway
        return AsyncStream { continuation in
            let coordinator = Task {
                // Tohum: ilk birleşik snapshot (replay). Sonra iki akış birleşik özeti günceller.
                let seed = await Self.summary(
                    balance: gateway.currentBalance(),
                    subscription: gateway.subscriptionStatus()
                )
                let merger = WalletSummaryMerger(seed: seed, continuation: continuation)
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await balance in gateway.balanceUpdates() {
                            await merger.updateCoinBalance(balance.totalCoins)
                        }
                    }
                    group.addTask {
                        for await entitlement in gateway.entitlementUpdates() {
                            await merger.updateEntitlement(
                                isVIP: entitlement.isVIP,
                                renewal: entitlement.vipExpiresAt
                            )
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in coordinator.cancel() }
        }
    }

    /// Saf dönüşüm (izole test edilir): WalletKit bakiye + abonelik → ProfileKit özeti.
    static func summary(balance: CoinBalance, subscription: SubscriptionStatus) -> WalletSummary {
        WalletSummary(
            coinBalance: balance.totalCoins,
            isVIP: subscription.isVIP,
            vipRenewalDate: subscription.isVIP ? subscription.expiresAt : nil
        )
    }
}

/// Bakiye + entitlement akışlarını tek `WalletSummary` akışında birleştiren dahili birleştirici.
/// `actor`: iki eşzamanlı akış tüketicisi son bilinen alanları yarışsız günceller ve her değişimde
/// birleşik özeti yayınlar (son-değer tutulur; eksik akış tohumdan gelen değeri korur).
private actor WalletSummaryMerger {
    private var coinBalance: Int
    private var isVIP: Bool
    private var renewal: Date?
    private let continuation: AsyncStream<WalletSummary>.Continuation

    init(seed: WalletSummary, continuation: AsyncStream<WalletSummary>.Continuation) {
        coinBalance = seed.coinBalance
        isVIP = seed.isVIP
        renewal = seed.vipRenewalDate
        self.continuation = continuation
        continuation.yield(seed)
    }

    func updateCoinBalance(_ value: Int) {
        coinBalance = value
        emit()
    }

    func updateEntitlement(isVIP: Bool, renewal: Date?) {
        self.isVIP = isVIP
        self.renewal = renewal
        emit()
    }

    private func emit() {
        continuation.yield(
            WalletSummary(
                coinBalance: coinBalance,
                isVIP: isVIP,
                vipRenewalDate: isVIP ? renewal : nil
            )
        )
    }
}
