import Testing
@testable import WalletKit

/// Backend katalog + StoreKit ürün birleştirme (06 §4.2) ve intro offer okuma (06 §4.8).
struct StorefrontMergeTests {
    @Test func coinShopKatalogVeFiyatiEsler() {
        let catalog = CoinPackageCatalog(
            packages: [
                CoinPackage(
                    productId: "com.shortseries.coins.tier1",
                    baseCoins: 100,
                    bonusPercent: 0,
                    bonusCoins: 0,
                    firstTopUpBonusCoins: 100,
                    badge: nil
                ),
                CoinPackage(
                    productId: "com.shortseries.coins.tier3",
                    baseCoins: 1000,
                    bonusPercent: 20,
                    bonusCoins: 200,
                    firstTopUpBonusCoins: 1000,
                    badge: "EN POPÜLER"
                )
            ],
            firstTopUpEligible: false,
            ttlSec: 600
        )
        let products = [
            StoreProduct.coin(id: "com.shortseries.coins.tier1", price: 0.99, displayPrice: "$0.99"),
            StoreProduct.coin(id: "com.shortseries.coins.tier3", price: 9.99, displayPrice: "$9.99")
        ]

        let items = StorefrontMerge.coinShop(catalog: catalog, products: products)

        #expect(items.count == 2)
        #expect(items[0].displayPrice == "$0.99")
        #expect(items[1].displayPrice == "$9.99")
        #expect(items[1].displayedTotalCoins == 1200) // standart toplam
    }

    @Test func storeKittteOlmayanPaketAtlanir() {
        // ASC'de pasif/reddedilmiş ürün → kart gizlenir (06 §4.2).
        let catalog = CoinPackageCatalog(
            packages: [
                CoinPackage(
                    productId: "com.shortseries.coins.tier1",
                    baseCoins: 100,
                    bonusPercent: 0,
                    bonusCoins: 0,
                    firstTopUpBonusCoins: 100,
                    badge: nil
                ),
                CoinPackage(
                    productId: "com.shortseries.coins.tier6",
                    baseCoins: 10000,
                    bonusPercent: 100,
                    bonusCoins: 10000,
                    firstTopUpBonusCoins: 10000,
                    badge: nil
                )
            ],
            firstTopUpEligible: false,
            ttlSec: 600
        )
        let products = [StoreProduct.coin(id: "com.shortseries.coins.tier1", price: 0.99, displayPrice: "$0.99")]

        let items = StorefrontMerge.coinShop(catalog: catalog, products: products)

        #expect(items.count == 1)
        #expect(items[0].productId == "com.shortseries.coins.tier1")
    }

    @Test func ilkYuklemeUygunkenIkiKatToplamGosterilir() {
        let catalog = CoinPackageCatalog(
            packages: [CoinPackage(
                productId: "com.shortseries.coins.tier3",
                baseCoins: 1000,
                bonusPercent: 20,
                bonusCoins: 200,
                firstTopUpBonusCoins: 1000,
                badge: nil
            )],
            firstTopUpEligible: true,
            ttlSec: 600
        )
        let products = [StoreProduct.coin(id: "com.shortseries.coins.tier3", price: 9.99, displayPrice: "$9.99")]

        let items = StorefrontMerge.coinShop(catalog: catalog, products: products)

        #expect(items[0].displayedTotalCoins == 2000) // baz 1000 + firstTopUp 1000
    }

    @Test func vipPlanlariEslesir() {
        let products = [
            StoreProduct.vip(id: "com.shortseries.vip.weekly", displayPrice: "$5.99", eligibleIntro: false, intro: nil),
            StoreProduct.vip(id: "com.shortseries.vip.yearly", displayPrice: "$49.99", eligibleIntro: false, intro: nil),
            StoreProduct.coin(id: "com.shortseries.coins.tier1", price: 0.99, displayPrice: "$0.99")
        ]

        let plans = StorefrontMerge.vipPlans(products: products)

        #expect(plans.count == 2) // coin ürünü atlanır
        #expect(plans.contains { $0.plan == .weekly })
        #expect(plans.contains { $0.plan == .yearly })
    }

    @Test func introOfferYalnizUygunKullaniciyaGosterilir() {
        let intro = IntroOffer(
            displayPrice: "$3.99",
            paymentMode: .payUpFront,
            periodUnit: .week,
            periodValue: 1,
            periodCount: 1
        )
        let eligibleProduct = StoreProduct.vip(
            id: "com.shortseries.vip.weekly",
            displayPrice: "$5.99",
            eligibleIntro: true,
            intro: intro
        )
        let ineligibleProduct = StoreProduct.vip(
            id: "com.shortseries.vip.weekly",
            displayPrice: "$5.99",
            eligibleIntro: false,
            intro: intro
        )

        let eligible = VIPPlanOption(plan: .weekly, product: eligibleProduct)
        let ineligible = VIPPlanOption(plan: .weekly, product: ineligibleProduct)

        #expect(eligible.showsIntroOffer)
        #expect(eligible.effectiveIntroOffer?.displayPrice == "$3.99")
        #expect(!ineligible.showsIntroOffer)
        #expect(ineligible.effectiveIntroOffer == nil)
    }
}
