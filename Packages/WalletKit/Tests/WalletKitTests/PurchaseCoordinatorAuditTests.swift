import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// WalletKit bug-hunt (adversarial workflow) satın-alma bulguları: §575 uçuştaki-kredi hesap-değişimi
/// fence'i (HIGH), dual-delivery yanlış-fail eşlemesi (MEDIUM), family-shared VIP seed reddi (MEDIUM),
/// restore stuck-consumable kurtarma (LOW). `PurchaseCoordinatorTests`'ten ayrı: type_body bütçesi.
struct PurchaseCoordinatorAuditTests {
    private struct Harness {
        let coordinator: PurchaseCoordinator
        let store: WalletStore
        let purchases: FakePurchaseService
        let remote: FakeWalletRemote
    }

    private func make(
        purchases: FakePurchaseService = FakePurchaseService(),
        remote: FakeWalletRemote = FakeWalletRemote()
    ) -> Harness {
        let store = WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
        let coordinator = PurchaseCoordinator(
            purchases: purchases,
            remote: remote,
            wallet: store,
            analytics: MockAnalytics(),
            log: MockLogger(),
            appAccountToken: { UUID() }
        )
        return Harness(coordinator: coordinator, store: store, purchases: purchases, remote: remote)
    }

    private func coinsCredited(purchased: Int, version: Int) -> VerifyOutcome {
        .coinsCredited(
            granted: GrantedCoins(coins: purchased, bonusCoins: 0, firstPurchaseBonusApplied: false),
            wallet: .fixture(purchased: purchased, version: version),
            transaction: nil
        )
    }

    private func waitUntil(_ condition: @Sendable () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - §575 HIGH: uçuştaki kredi hesap-değişiminde sızmamalı

    @Test func inFlightPurchaseCreditDroppedAfterAccountSwitch() async {
        let sut = make()
        let gate = AsyncGate()
        sut.remote.verifyGate = { await gate.wait() }
        sut.purchases.purchaseResult = .success(.success(.fixture(id: 2002)))
        sut.remote.verifyResults = [.success(coinsCredited(purchased: 999, version: 87))] // X hesabı

        let purchaseTask = Task { await sut.coordinator.purchase(productID: "com.shortseries.coins.tier3") }
        await waitUntil { sut.remote.verifyCallCount == 1 } // verify uçuşta (epoch yakalandı)

        await sut.store.reset() // hesap değişimi (epoch bump)
        await sut.store.apply(walletSnapshot: .fixture(purchased: 20, version: 1)) // Y hesabı

        await gate.open()
        _ = await purchaseTask.value

        #expect(await sut.store.currentBalance() == CoinBalance(purchasedCoins: 20, earnedCoins: 0))
    }

    // MARK: - MEDIUM: dual-delivery kaybedeni YANLIŞ fail raporlamamalı

    @Test func inFlightPendingRaporlarFailDegil() {
        // Aynı transaction hem purchase() hem observer'dan gelince kaybeden `.inFlight` alır; kazanan
        // krediyi yazar → kullanıcıya "başarısız" (+ negatif puanlama) GÖSTERİLMEMELİ.
        #expect(ProcessOutcome.inFlight.flowResult(transactionID: "9001") == .verificationPending)
    }

    // MARK: - MEDIUM: family-shared abonelik SEED'i VIP vermemeli

    @Test func aileSharedAbonelikTohumuVipVERMEZ() async {
        // Aile Paylaşımı KAPALI (06 §4.7): process() family-shared'i reddeder; SEED de aynı politikayı uygular.
        let sut = make()
        sut.purchases.setEntitlements([
            .fixture(id: 1, productID: "com.shortseries.vip.weekly", kind: .subscription, ownership: .familyShared)
        ])

        await sut.coordinator.seedEntitlementsFromStoreKit()

        #expect(await sut.store.hasAccess(to: EpisodeID("any")) == false)
        #expect(await sut.store.subscriptionStatus().grantsFullAccess == false)
    }

    // MARK: - LOW: restore askıdaki consumable'ı kurtarmalı

    @Test func restoreAskidakiConsumableKrediEder() async {
        let sut = make()
        let transaction = VerifiedTransaction.fixture(id: 7007)
        sut.purchases.setUnfinished([transaction])
        sut.remote.verifyResults = [.success(coinsCredited(purchased: 1200, version: 5))]

        try? await sut.coordinator.restore()

        #expect(sut.purchases.finished.contains(7007))
        #expect(await sut.store.currentBalance().purchasedCoins == 1200)
    }
}
