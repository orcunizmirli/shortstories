import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// CoinMagazasi ekran modeli (SS-094): katalog+StoreKit birleştirme, satın alma durum makinesi,
/// analitik ve boş/hata durumları.
@MainActor
struct CoinShopModelTests {
    private func tier(_ tierNumber: Int, base: Int, bonus: Int, badge: String? = nil) -> CoinPackage {
        CoinPackage(
            productId: "com.shortseries.coins.tier\(tierNumber)",
            baseCoins: base,
            bonusPercent: base > 0 ? Int(Double(bonus) / Double(base) * 100) : 0,
            bonusCoins: bonus,
            firstTopUpBonusCoins: base,
            badge: badge
        )
    }

    private func catalog(firstTopUp: Bool = false) -> CoinPackageCatalog {
        CoinPackageCatalog(
            packages: [
                tier(1, base: 100, bonus: 0),
                tier(3, base: 1000, bonus: 200, badge: "EN POPÜLER")
            ],
            firstTopUpEligible: firstTopUp,
            ttlSec: 600
        )
    }

    private var products: [StoreProduct] {
        [
            .coin(id: "com.shortseries.coins.tier1", price: 0.99, displayPrice: "$0.99"),
            .coin(id: "com.shortseries.coins.tier3", price: 9.99, displayPrice: "$9.99")
        ]
    }

    private func makeModel(
        loader: FakeStorefrontLoader,
        gateway: FakeWalletGateway,
        purchasing: FakeWalletPurchasing,
        analytics: MockAnalytics = MockAnalytics(),
        delegate: SpyCoinShopDelegate,
        source: CoinShopSource = .unlockSheet
    ) -> CoinShopModel {
        CoinShopModel(
            source: source,
            loader: loader,
            wallet: gateway,
            purchasing: purchasing,
            analytics: analytics,
            delegate: delegate
        )
    }

    @Test func beginYuklerVeStoreViewAnalitigi() async {
        let loader = FakeStorefrontLoader(packages: .success(catalog(firstTopUp: true)), products: .success(products))
        let gateway = FakeWalletGateway(
            balance: CoinBalance(purchasedCoins: 200, earnedCoins: 40),
            snapshot: .fixture(purchased: 200, earned: 40)
        )
        let analytics = MockAnalytics()
        let delegate = SpyCoinShopDelegate()
        let model = makeModel(
            loader: loader,
            gateway: gateway,
            purchasing: FakeWalletPurchasing(),
            analytics: analytics,
            delegate: delegate
        )

        await model.begin()

        #expect(model.loadPhase == .loaded)
        #expect(model.items.count == 2)
        #expect(model.firstTopUpEligible)
        #expect(model.balance.totalCoins == 240)
        let view = analytics.events.first { $0.name == "coin_store_view" }
        #expect(view?.parameters["source"] == .string("unlock_sheet"))
        #expect(view?.parameters["coin_balance"] == .int(240))
        model.onDisappear()
    }

    @Test func katalogHatasiFailedDurumu() async {
        let loader = FakeStorefrontLoader(packages: .failure(.network(.offline)), products: .success(products))
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: FakeWalletPurchasing(),
            delegate: SpyCoinShopDelegate()
        )

        await model.begin()

        #expect(model.loadPhase == .failed)
        model.onDisappear()
    }

    @Test func bosBirlesimFailedDurumu() async {
        // StoreKit'te hiç eşleşen ürün yoksa (products boş) → merge boş → hata + retry (06 §7.4).
        let loader = FakeStorefrontLoader(packages: .success(catalog()), products: .success([]))
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: FakeWalletPurchasing(),
            delegate: SpyCoinShopDelegate()
        )

        await model.begin()

        #expect(model.loadPhase == .failed)
        model.onDisappear()
    }

    @Test func basariliSatinAlmaAnalitikVeDelegate() async throws {
        let loader = FakeStorefrontLoader(packages: .success(catalog()), products: .success(products))
        let gateway = FakeWalletGateway(
            balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0),
            snapshot: .fixture(purchased: 100)
        )
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.completed(transactionID: "txn_777")]
        let analytics = MockAnalytics()
        let delegate = SpyCoinShopDelegate()
        let model = makeModel(loader: loader, gateway: gateway, purchasing: purchasing, analytics: analytics, delegate: delegate)
        await model.begin()
        gateway.pushBalance(CoinBalance(purchasedCoins: 1300, earnedCoins: 0)) // kredi

        let item = try #require(model.items.first { $0.productId == "com.shortseries.coins.tier3" })
        await model.purchase(item)

        #expect(model.purchasePhase == .success(productID: "com.shortseries.coins.tier3"))
        #expect(delegate.purchaseCompletions == 1)

        let start = analytics.events.first { $0.name == "coin_purchase_start" }
        #expect(start?.parameters["product_id"] == .string("com.shortseries.coins.tier3"))
        #expect(start?.parameters["coin_amount"] == .int(1000))
        #expect(start?.parameters["bonus_coin_amount"] == .int(200))
        #expect(start?.parameters["is_first_purchase_offer"] == .bool(false))
        #expect(abs((start?.double("price_usd") ?? 0) - 9.99) < 0.001)

        let success = analytics.events.first { $0.name == "coin_purchase_success" }
        #expect(success?.parameters["balance_after"] == .int(1300))
        // 08 §3.4: coin_purchase_success zorunlu transaction_id (App Store işlemine join).
        #expect(success?.parameters["transaction_id"] == .string("txn_777"))
        model.onDisappear()
    }

    @Test func iptalSessizAnalitikCancel() async throws {
        let loader = FakeStorefrontLoader(packages: .success(catalog()), products: .success(products))
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.cancelled]
        let analytics = MockAnalytics()
        let delegate = SpyCoinShopDelegate()
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            analytics: analytics,
            delegate: delegate
        )
        await model.begin()

        let item = try #require(model.items.first)
        await model.purchase(item)

        #expect(model.purchasePhase == .idle)
        #expect(delegate.purchaseCompletions == 0)
        #expect(analytics.eventNames.contains("coin_purchase_cancel"))
        #expect(!analytics.eventNames.contains("coin_purchase_success"))
        model.onDisappear()
    }

    @Test func hataAnalitikFailStage() async throws {
        let loader = FakeStorefrontLoader(packages: .success(catalog()), products: .success(products))
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.failed(.network(.server(status: 503)))]
        let analytics = MockAnalytics()
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            analytics: analytics,
            delegate: SpyCoinShopDelegate()
        )
        await model.begin()

        try await model.purchase(#require(model.items.first))

        #expect(try model.purchasePhase == .failed(productID: #require(model.items.first?.productId)))
        let fail = analytics.events.first { $0.name == "coin_purchase_fail" }
        #expect(fail?.parameters["stage"] == .string("storekit"))
        #expect(fail?.parameters["error_domain"] == .string("network"))
        #expect(fail?.parameters["error_code"] == .string("server_503"))
        model.onDisappear()
    }

    @Test func pendingBilgiDurumu() async throws {
        let loader = FakeStorefrontLoader(packages: .success(catalog()), products: .success(products))
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.pending]
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            delegate: SpyCoinShopDelegate()
        )
        await model.begin()

        try await model.purchase(#require(model.items.first))

        #expect(try model.purchasePhase == .pending(productID: #require(model.items.first?.productId)))
        model.onDisappear()
    }

    @Test func ciftDokunmaCiftSatinAlmaEngellenir() async throws {
        let loader = FakeStorefrontLoader(packages: .success(catalog()), products: .success(products))
        let purchasing = FakeWalletPurchasing()
        let gate = AsyncGate()
        purchasing.purchaseGate = { await gate.wait() }
        purchasing.purchaseResults = [.completed(transactionID: "txn_dbl")]
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            delegate: SpyCoinShopDelegate()
        )
        await model.begin()
        let item = try #require(model.items.first)

        async let first: Void = model.purchase(item)
        while !model.purchasePhase.isPurchasing {
            await Task.yield()
        }
        await model.purchase(item) // ikinci dokunma — uçuşta olduğu için yok sayılır
        await gate.open()
        await first

        #expect(purchasing.purchaseCallCount == 1)
        model.onDisappear()
    }

    @Test func restoreAnalitikVeCagri() async {
        let loader = FakeStorefrontLoader(packages: .success(catalog()), products: .success(products))
        let purchasing = FakeWalletPurchasing()
        let analytics = MockAnalytics()
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            analytics: analytics,
            delegate: SpyCoinShopDelegate()
        )
        await model.begin()

        await model.restore()

        #expect(purchasing.restoreCount == 1)
        #expect(analytics.eventNames.contains("restore_tapped"))
        model.onDisappear()
    }
}
