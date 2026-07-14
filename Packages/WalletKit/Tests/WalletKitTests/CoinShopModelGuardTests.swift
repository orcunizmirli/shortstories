import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// CoinMagazasi: Ask-to-Buy pending çift-satın alma koruması (06 §7.5) ve begin()-await sızıntı
/// koruması (gözlem görevi sheet kapandıktan sonra kurulmaz).
@MainActor
struct CoinShopModelGuardTests {
    private func catalog() -> CoinPackageCatalog {
        CoinPackageCatalog(
            packages: [
                CoinPackage(
                    productId: "com.shortseries.coins.tier1",
                    baseCoins: 100, bonusPercent: 0, bonusCoins: 0, firstTopUpBonusCoins: 100, badge: nil
                )
            ],
            firstTopUpEligible: false,
            ttlSec: 600
        )
    }

    private var products: [StoreProduct] {
        [.coin(id: "com.shortseries.coins.tier1", price: 0.99, displayPrice: "$0.99")]
    }

    private func makeModel(gateway: FakeWalletGateway, purchasing: FakeWalletPurchasing) -> CoinShopModel {
        CoinShopModel(
            source: .unlockSheet,
            loader: FakeStorefrontLoader(packages: .success(catalog()), products: .success(products)),
            wallet: gateway,
            purchasing: purchasing,
            analytics: MockAnalytics(),
            delegate: SpyCoinShopDelegate()
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() {
            await Task.yield()
        }
    }

    @Test func pendingSirasindaIkinciSatinAlmaEngellenir() async throws {
        // 06 §7.5: Ask-to-Buy pending penceresinde ikinci satın alma başlatılamaz (çift kredi/ücret).
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.pending, .completed(transactionID: "txn_2")]
        let model = makeModel(gateway: FakeWalletGateway(), purchasing: purchasing)
        await model.begin()
        let item = try #require(model.items.first)

        await model.purchase(item) // → .pending
        #expect(model.purchasePhase == .pending(productID: item.productId))

        await model.purchase(item) // pending iken → engellenir (no-op)

        #expect(purchasing.purchaseCallCount == 1)
        #expect(model.purchasePhase == .pending(productID: item.productId))
        model.onDisappear()
    }

    @Test func beginSirasindaKapanirsaGozlemKurulmazSizintiYok() async {
        // Sızıntı: begin() ilk await'te (currentSnapshot) askıdayken onDisappear gelirse gözlem
        // görevi KURULMAZ; sonraki bakiye yayını modeli güncellemez (kalıcı hayalet abone yok).
        let gateway = FakeWalletGateway(
            balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0),
            snapshot: .fixture(purchased: 100)
        )
        let gate = AsyncGate()
        gateway.readGate = { await gate.wait() }
        let model = makeModel(gateway: gateway, purchasing: FakeWalletPurchasing())

        async let begun: Void = model.begin()
        await waitUntil { gateway.snapshotReads >= 1 } // currentSnapshot çağrıldı, gate'te askıda
        model.onDisappear() // begin await'teyken sheet kapandı
        await gate.open()
        await begun

        gateway.pushBalance(CoinBalance(purchasedCoins: 9999, earnedCoins: 0))
        await Task.yield()
        await Task.yield()

        // Gözlem kurulmadı → seed atlandı, canlı yayın uygulanmadı: balance ilk (zero) değerde kaldı.
        #expect(model.balance == .zero)
        #expect(model.loadPhase == .loading)
    }
}
