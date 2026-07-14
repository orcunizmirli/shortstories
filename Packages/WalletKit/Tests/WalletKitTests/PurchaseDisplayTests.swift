import AppFoundation
import Testing
@testable import WalletKit

/// CoinMagazasi/VIPAbonelik saf gösterim türevleri (06 §7.2/§7.3 bonus rozetleri + ilk-yükleme;
/// §8.1 plan rozeti/dönem).
struct PurchaseDisplayTests {
    private func item(
        productId: String = "com.shortseries.coins.tier3",
        base: Int = 1000,
        bonusPercent: Int = 20,
        bonus: Int = 200,
        firstTopUpBonus: Int = 1000,
        badge: String? = nil,
        firstTopUpEligible: Bool = false
    ) -> CoinShopItem {
        CoinShopItem(
            productId: productId,
            package: CoinPackage(
                productId: productId,
                baseCoins: base,
                bonusPercent: bonusPercent,
                bonusCoins: bonus,
                firstTopUpBonusCoins: firstTopUpBonus,
                badge: badge
            ),
            displayPrice: "$9.99",
            firstTopUpEligible: firstTopUpEligible
        )
    }

    @Test func bonusRozetiMetni() {
        #expect(item(bonusPercent: 20).bonusBadgeText == "+%20 BONUS")
        #expect(item(bonusPercent: 100).bonusBadgeText == "+%100 BONUS")
    }

    @Test func tier1RozetiYok() {
        // %0 bonus → rozetsiz (06 §7.2).
        #expect(item(bonusPercent: 0, bonus: 0).bonusBadgeText == nil)
    }

    @Test func katalogRozetiSunucudan() {
        #expect(item(badge: "EN POPÜLER").catalogBadge == "EN POPÜLER")
        #expect(item(badge: nil).catalogBadge == nil)
    }

    @Test func ilkYuklemeCiftlemeGosterimi() {
        // Uygun + 2x toplam > standart → üstü çizili standart + büyük 2x (06 §7.3).
        let eligible = item(firstTopUpEligible: true)
        #expect(eligible.showsFirstTopUpDoubling)
        #expect(eligible.standardTotalCoins == 1200) // 1000 + 200
        #expect(eligible.displayedTotalCoins == 2000) // 1000 + firstTopUp 1000

        let ineligible = item(firstTopUpEligible: false)
        #expect(!ineligible.showsFirstTopUpDoubling)
        #expect(ineligible.displayedTotalCoins == 1200)
    }

    @Test func vipPlanEnAvantajliYillik() {
        let weekly = VIPPlanOption(plan: .weekly, product: .vipWeekly())
        let yearly = VIPPlanOption(plan: .yearly, product: .vipYearly())
        #expect(!weekly.isBestValue)
        #expect(yearly.isBestValue)
    }

    @Test func vipPlanDonemBirimi() {
        #expect(VIPPlanOption(plan: .weekly, product: .vipWeekly()).periodUnit == .week)
        #expect(VIPPlanOption(plan: .monthly, product: .vipMonthly()).periodUnit == .month)
        #expect(VIPPlanOption(plan: .yearly, product: .vipYearly()).periodUnit == .year)
    }

    @Test func planGorunumSirasi() {
        #expect(SubscriptionPlan.weekly.displayOrder < SubscriptionPlan.monthly.displayOrder)
        #expect(SubscriptionPlan.monthly.displayOrder < SubscriptionPlan.yearly.displayOrder)
    }
}
