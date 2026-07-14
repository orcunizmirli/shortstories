import Testing
@testable import WalletKit

/// Harcama önceliği (kanon §5; 06 §2.4): EARNED ÖNCE. Saf fonksiyon testleri.
struct SpendPlannerTests {
    @Test func earnedYeterliyseYalnizEarnedDuser() {
        let plan = SpendPlanner.plan(spending: 60, from: CoinBalance(purchasedCoins: 100, earnedCoins: 80))

        #expect(plan.earnedSpent == 60)
        #expect(plan.purchasedSpent == 0)
        #expect(plan.resulting == CoinBalance(purchasedCoins: 100, earnedCoins: 20))
        #expect(plan.isCovered)
        #expect(plan.shortfall == 0)
    }

    @Test func earnedYetmezseKalaniPurchasedKapatir() {
        // Karışık bakiye: 45 earned + 15 purchased = 60 (05 §4.5 örneği).
        let plan = SpendPlanner.plan(spending: 60, from: CoinBalance(purchasedCoins: 105, earnedCoins: 45))

        #expect(plan.earnedSpent == 45)
        #expect(plan.purchasedSpent == 15)
        #expect(plan.resulting == CoinBalance(purchasedCoins: 90, earnedCoins: 0))
        #expect(plan.isCovered)
    }

    @Test func earnedSifirsaTamamenPurchasedDuser() {
        let plan = SpendPlanner.plan(spending: 50, from: CoinBalance(purchasedCoins: 200, earnedCoins: 0))

        #expect(plan.earnedSpent == 0)
        #expect(plan.purchasedSpent == 50)
        #expect(plan.resulting == CoinBalance(purchasedCoins: 150, earnedCoins: 0))
    }

    @Test func bakiyeYetersizseShortfallHesaplanir() {
        let plan = SpendPlanner.plan(spending: 100, from: CoinBalance(purchasedCoins: 20, earnedCoins: 48))

        #expect(!plan.isCovered)
        #expect(plan.shortfall == 32) // 100 − (48 + 20)
        #expect(plan.totalSpent == 68)
    }

    @Test func tamBakiyeHarcanabilir() {
        let plan = SpendPlanner.plan(spending: 68, from: CoinBalance(purchasedCoins: 20, earnedCoins: 48))

        #expect(plan.isCovered)
        #expect(plan.resulting == .zero)
    }
}
