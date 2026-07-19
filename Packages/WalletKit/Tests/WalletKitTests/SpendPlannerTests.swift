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

    // MARK: - Earned-önce harcama ŞEFFAFLIĞI (06 §2.4; UI okuması)

    @Test func yalnizEarnedDuserseTekSatirEarned() {
        let plan = SpendPlanner.plan(spending: 60, from: CoinBalance(purchasedCoins: 100, earnedCoins: 80))

        #expect(plan.sources == [SpendSource(bucket: .earned, coins: 60)])
        #expect(plan.primaryBucket == .earned)
        #expect(!plan.drawsFromBothBuckets)
    }

    @Test func karisikDususIkiSatirEarnedOnce() {
        // 45 earned + 15 purchased: ledger iki satır, earned ÖNCE (05 §2.6 örneği).
        let plan = SpendPlanner.plan(spending: 60, from: CoinBalance(purchasedCoins: 105, earnedCoins: 45))

        #expect(plan.sources == [
            SpendSource(bucket: .earned, coins: 45),
            SpendSource(bucket: .purchased, coins: 15)
        ])
        #expect(plan.primaryBucket == .earned) // banner: "önce kazanılmış coin"
        #expect(plan.drawsFromBothBuckets)
    }

    @Test func earnedSifirsaYalnizPurchasedSatiri() {
        let plan = SpendPlanner.plan(spending: 50, from: CoinBalance(purchasedCoins: 200, earnedCoins: 0))

        #expect(plan.sources == [SpendSource(bucket: .purchased, coins: 50)])
        #expect(plan.primaryBucket == .purchased)
        #expect(!plan.drawsFromBothBuckets)
    }

    @Test func bakiyeYetersizseSadeceDusenSatirlar() {
        // Yetersiz bakiye: shortfall satır ÜRETMEZ; yalnız fiilen düşen kesler görünür.
        let plan = SpendPlanner.plan(spending: 100, from: CoinBalance(purchasedCoins: 20, earnedCoins: 48))

        #expect(plan.sources == [
            SpendSource(bucket: .earned, coins: 48),
            SpendSource(bucket: .purchased, coins: 20)
        ])
        #expect(!plan.isCovered)
    }

    // MARK: - UnlockSheet earned-önce notu (SS-115 D2; mesaj tek kaynak)

    @Test func notYalnizEarnedIseEarnedOnly() {
        let plan = SpendPlanner.plan(spending: 60, from: CoinBalance(purchasedCoins: 100, earnedCoins: 80))

        #expect(plan.earnedFirstNote == .earnedOnly(coins: 60))
        #expect(plan.earnedFirstNote?.message == "Önce kazanılmış 60 coin'in kullanılır")
    }

    @Test func notKarisikDususIseMixedEarnedOnce() {
        let plan = SpendPlanner.plan(spending: 60, from: CoinBalance(purchasedCoins: 105, earnedCoins: 45))

        #expect(plan.earnedFirstNote == .mixed(earned: 45, purchased: 15))
        #expect(plan.earnedFirstNote?.message == "Önce kazanılmış 45 coin, sonra satın alınan 15 coin kullanılır")
    }

    @Test func notYalnizPurchasedIseNil() {
        // Earned düşmüyorsa "önce earned" anlatılacak bir şey yok → not gösterilmez.
        let plan = SpendPlanner.plan(spending: 50, from: CoinBalance(purchasedCoins: 200, earnedCoins: 0))
        #expect(plan.earnedFirstNote == nil)
    }

    @Test func notBakiyeYetersizseNil() {
        // Shortfall varsa unlock olmayacak → not gösterilmez (yanıltıcı olmasın).
        let plan = SpendPlanner.plan(spending: 100, from: CoinBalance(purchasedCoins: 20, earnedCoins: 48))
        #expect(plan.earnedFirstNote == nil)
    }
}
