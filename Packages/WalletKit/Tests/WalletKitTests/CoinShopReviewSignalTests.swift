import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// RTG-01 kriter 3 (00-genel-bakis.md §294): GERÇEK satın alma hatası NEGATİF sinyaldir → App puanlama
/// istemini bir süre bastırır. İPTAL şikayet değildir → sinyal bildirilmez.
@MainActor
@Suite("RTG-01 satın-alma-hatası → puanlama negatif sinyali")
struct CoinShopReviewSignalTests {
    private var products: [StoreProduct] {
        [.coin(id: "com.shortseries.coins.tier1", price: 0.99, displayPrice: "$0.99")]
    }

    private func catalog() -> CoinPackageCatalog {
        CoinPackageCatalog(
            packages: [CoinPackage(
                productId: "com.shortseries.coins.tier1",
                baseCoins: 100, bonusPercent: 0, bonusCoins: 0, firstTopUpBonusCoins: 100, badge: nil
            )],
            firstTopUpEligible: false,
            ttlSec: 600
        )
    }

    private func makeModel(purchaseResults: [PurchaseFlowResult], delegate: SpyCoinShopDelegate) -> CoinShopModel {
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = purchaseResults
        return CoinShopModel(
            source: .unlockSheet,
            loader: FakeStorefrontLoader(packages: .success(catalog()), products: .success(products)),
            wallet: FakeWalletGateway(),
            purchasing: purchasing,
            analytics: MockAnalytics(),
            delegate: delegate
        )
    }

    @Test func gercekHataNegatifSinyalBildirir() async throws {
        let delegate = SpyCoinShopDelegate()
        let model = makeModel(purchaseResults: [.failed(.network(.server(status: 503)))], delegate: delegate)
        await model.begin()

        try await model.purchase(#require(model.items.first))

        #expect(delegate.purchaseFailures == 1)
        model.onDisappear()
    }

    @Test func iptalNegatifSinyalBildirmez() async throws {
        let delegate = SpyCoinShopDelegate()
        let model = makeModel(purchaseResults: [.cancelled], delegate: delegate)
        await model.begin()

        try await model.purchase(#require(model.items.first))

        #expect(delegate.purchaseFailures == 0) // iptal ≠ şikayet
        model.onDisappear()
    }
}
