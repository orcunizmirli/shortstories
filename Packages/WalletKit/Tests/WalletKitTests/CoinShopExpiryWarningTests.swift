import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// CoinMagazasi yaklaşan-vade uyarısı MODEL kablolaması (SS-115 D1): snapshot lotları seed edilir,
/// `now` enjekte → `earnedExpiryWarning` deterministik türetilir. Görünürlük/mesaj mantığı
/// `EarnedExpiryWarningTests`'te izole; burada modelin lotları doğru beslediği doğrulanır.
@MainActor
struct CoinShopExpiryWarningTests {
    private func makeModel(gateway: FakeWalletGateway, now: @escaping @Sendable () -> Date) -> CoinShopModel {
        CoinShopModel(
            source: .profil,
            loader: FakeStorefrontLoader(packages: .success(.fixture()), products: .success([])),
            wallet: gateway,
            purchasing: FakeWalletPurchasing(),
            analytics: MockAnalytics(),
            delegate: SpyCoinShopDelegate(),
            now: now
        )
    }

    @Test func lotlardanYaklasanVadeTuretilir() async {
        let now = Date(timeIntervalSince1970: 1_752_278_400) // 2026-07-12 00:00 UTC
        let buckets = [
            EarnedCoinBucket(amount: 30, expiresAt: now.addingTimeInterval(2 * 86400)),
            EarnedCoinBucket(amount: 20, expiresAt: now.addingTimeInterval(40 * 86400)) // pencere dışı
        ]
        let gateway = FakeWalletGateway(
            balance: CoinBalance(purchasedCoins: 0, earnedCoins: 50),
            snapshot: .fixture(purchased: 0, earned: 50, earnedBuckets: buckets)
        )
        let model = makeModel(gateway: gateway, now: { now })

        await model.begin()

        #expect(model.earnedBuckets.count == 2)
        #expect(model.earnedExpiryWarning?.coins == 30) // yalnız eşik-içi lot
        #expect(model.earnedExpiryWarning?.daysRemaining == 2)
        model.onDisappear()
    }

    @Test func lotYoksaTekilBandaDuser() async {
        let now = Date(timeIntervalSince1970: 1_752_278_400)
        let notice = ExpiryNotice(amount: 15, expiresAt: now.addingTimeInterval(3 * 86400))
        let gateway = FakeWalletGateway(
            balance: CoinBalance(purchasedCoins: 0, earnedCoins: 15),
            snapshot: .fixture(purchased: 0, earned: 15, earnedExpiringSoon: notice)
        )
        let model = makeModel(gateway: gateway, now: { now })

        await model.begin()

        #expect(model.earnedBuckets.isEmpty)
        #expect(model.earnedExpiryWarning?.coins == 15)
        #expect(model.earnedExpiryWarning?.daysRemaining == 3)
        model.onDisappear()
    }

    @Test func yaklasanVadeYoksaNil() async {
        let now = Date(timeIntervalSince1970: 1_752_278_400)
        let gateway = FakeWalletGateway(
            balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0),
            snapshot: .fixture(purchased: 100, earned: 0)
        )
        let model = makeModel(gateway: gateway, now: { now })

        await model.begin()

        #expect(model.earnedExpiryWarning == nil)
        model.onDisappear()
    }
}
