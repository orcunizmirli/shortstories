import Testing
@testable import WalletKit

/// VIP plan intro/fiyat kopyası (06 §8.1/§11.2): çok-dönemli intro'da süre `periodValue × periodCount`
/// toplamıyla gösterilmeli — yalnız `periodUnit` kullanmak yanıltıcı tek-dönem fiyatı basına yol açardı.
struct VIPPlanCopyTests {
    private func intro(
        price: String,
        mode: PaymentMode,
        unit: PeriodUnit,
        value: Int,
        count: Int
    ) -> IntroOffer {
        IntroOffer(displayPrice: price, paymentMode: mode, periodUnit: unit, periodValue: value, periodCount: count)
    }

    @Test func introTekDonemSayisiz() {
        // value=1/count=1 (test edilen weekly vaka) → yalnız birim adı, sayı yok.
        #expect(VIPPlanCopy.introDuration(intro(price: "$3.99", mode: .payUpFront, unit: .week, value: 1, count: 1)) == "hafta")
    }

    @Test func introPayUpFrontUcAyValueUcCountBir() {
        // "İlk 3 ay $9.99" (payUpFront): value=3, count=1 → toplam 3 birim.
        #expect(VIPPlanCopy.introDuration(intro(price: "$9.99", mode: .payUpFront, unit: .month, value: 3, count: 1)) == "3 ay")
    }

    @Test func introPayAsYouGoUcAyValueBirCountUc() {
        // Aynı toplam süre farklı kodlanabilir: value=1, count=3 → yine 3 birim.
        #expect(VIPPlanCopy.introDuration(intro(price: "$4.99", mode: .payAsYouGo, unit: .month, value: 1, count: 3)) == "3 ay")
    }

    @Test func priceSubtitleCokDonemToplamSureyiGosterir() {
        let product = StoreProduct.vip(
            id: SubscriptionPlan.weekly.productID,
            displayPrice: "$5.99",
            eligibleIntro: true,
            intro: intro(price: "$9.99", mode: .payUpFront, unit: .month, value: 3, count: 1)
        )
        let option = VIPPlanOption(plan: .weekly, product: product)
        #expect(VIPPlanCopy.priceSubtitle(for: option) == "İlk 3 ay $9.99, sonra $5.99/hafta")
    }

    @Test func priceSubtitleIntroYoksaSadeceDonemFiyati() {
        let option = VIPPlanOption(plan: .yearly, product: .vipYearly(displayPrice: "$49.99"))
        #expect(VIPPlanCopy.priceSubtitle(for: option) == "$49.99/yıl")
    }

    @Test func introCTASuffixCokDonem() {
        let product = StoreProduct.vip(
            id: SubscriptionPlan.weekly.productID,
            displayPrice: "$5.99",
            eligibleIntro: true,
            intro: intro(price: "$9.99", mode: .payUpFront, unit: .month, value: 3, count: 1)
        )
        #expect(VIPPlanCopy.introCTASuffix(for: VIPPlanOption(plan: .weekly, product: product)) == "ilk 3 ay $9.99")
    }

    @Test func introCTASuffixIntroYoksaNil() {
        let option = VIPPlanOption(plan: .yearly, product: .vipYearly())
        #expect(VIPPlanCopy.introCTASuffix(for: option) == nil)
        #expect(VIPPlanCopy.introCTASuffix(for: nil) == nil)
    }
}
