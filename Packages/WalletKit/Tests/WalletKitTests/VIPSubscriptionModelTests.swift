import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// VIPAbonelik ekran modeli (SS-096): plan yükleme/sıralama, intro gösterimi, satın alma,
/// yönetim modu, iptal/iade sonrası entitlement düşürme yansıması + analitik.
@MainActor
struct VIPSubscriptionModelTests {
    private func plans(introEligible: Bool = false) -> [StoreProduct] {
        [
            .vipYearly(),
            .vipWeekly(eligibleIntro: introEligible, intro: introEligible ? .weeklyThreeNinetyNine : nil),
            .vipMonthly()
        ]
    }

    private func makeModel(
        loader: FakeStorefrontLoader,
        gateway: FakeWalletGateway,
        purchasing: FakeWalletPurchasing,
        analytics: MockAnalytics = MockAnalytics(),
        delegate: SpyVIPSubscriptionDelegate,
        source: VIPSource = .unlockSheet
    ) -> VIPSubscriptionModel {
        VIPSubscriptionModel(
            source: source,
            loader: loader,
            wallet: gateway,
            purchasing: purchasing,
            analytics: analytics,
            delegate: delegate
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() {
            await Task.yield()
        }
    }

    @Test func beginYuklerSiralarVarsayilanYillik() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let analytics = MockAnalytics()
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: FakeWalletPurchasing(),
            analytics: analytics,
            delegate: SpyVIPSubscriptionDelegate()
        )

        await model.begin()

        #expect(model.loadPhase == .loaded)
        #expect(model.plans.map(\.plan) == [.weekly, .monthly, .yearly]) // displayOrder sıralaması
        #expect(model.selectedPlan == .yearly) // varsayılan en avantajlı
        #expect(model.mode == .purchase)
        #expect(analytics.events.first { $0.name == "subscription_view" }?.parameters["source"] == .string("unlock_sheet"))
        model.onDisappear()
    }

    @Test func aboneyseYonetimModu() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let gateway = FakeWalletGateway(subscription: .vip(plan: .monthly))
        let model = makeModel(
            loader: loader,
            gateway: gateway,
            purchasing: FakeWalletPurchasing(),
            delegate: SpyVIPSubscriptionDelegate()
        )

        await model.begin()

        #expect(model.mode == .management)
        #expect(model.subscription.plan == .monthly)
        model.onDisappear()
    }

    @Test func introUygunHaftalikGosterilir() async throws {
        let loader = FakeStorefrontLoader(products: .success(plans(introEligible: true)))
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: FakeWalletPurchasing(),
            delegate: SpyVIPSubscriptionDelegate()
        )
        await model.begin()

        let weekly = try #require(model.plans.first { $0.plan == .weekly })
        #expect(weekly.showsIntroOffer)
        #expect(weekly.effectiveIntroOffer?.displayPrice == "$3.99")
        model.onDisappear()
    }

    @Test func basariliAboneAktivasyonuVeAnalitik() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let gateway = FakeWalletGateway(subscription: .none)
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.completed(transactionID: "sub_txn_1")]
        let analytics = MockAnalytics()
        let delegate = SpyVIPSubscriptionDelegate()
        let model = makeModel(loader: loader, gateway: gateway, purchasing: purchasing, analytics: analytics, delegate: delegate)
        await model.begin()
        gateway.setSubscription(.vip(plan: .yearly)) // server aktifleştirdi

        await model.subscribe()

        #expect(model.purchasePhase == .success(productID: SubscriptionPlan.yearly.productID))
        #expect(model.mode == .management)
        #expect(delegate.activations == 1)
        let start = analytics.events.first { $0.name == "subscription_start" }
        #expect(start?.parameters["product_id"] == .string("vip_yearly"))
        #expect(abs((start?.double("price_usd") ?? 0) - 49.99) < 0.001)
        #expect(start?.parameters["has_intro_offer"] == .bool(false))
        let success = analytics.events.first { $0.name == "subscription_success" }
        #expect(success != nil)
        // 08 §3.4: subscription_success zorunlu transaction_id.
        #expect(success?.parameters["transaction_id"] == .string("sub_txn_1"))
        model.onDisappear()
    }

    @Test func introSecildiHasIntroTrue() async {
        let loader = FakeStorefrontLoader(products: .success(plans(introEligible: true)))
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.completed(transactionID: "sub_txn_2")]
        let gateway = FakeWalletGateway(subscription: .none)
        let analytics = MockAnalytics()
        let model = makeModel(
            loader: loader,
            gateway: gateway,
            purchasing: purchasing,
            analytics: analytics,
            delegate: SpyVIPSubscriptionDelegate()
        )
        await model.begin()
        model.select(.weekly)
        gateway.setSubscription(.vip(plan: .weekly))

        await model.subscribe()

        let start = analytics.events.first { $0.name == "subscription_start" }
        #expect(start?.parameters["product_id"] == .string("vip_weekly"))
        #expect(start?.parameters["has_intro_offer"] == .bool(true))
        model.onDisappear()
    }

    @Test func iptalSessiz() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.cancelled]
        let analytics = MockAnalytics()
        let delegate = SpyVIPSubscriptionDelegate()
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            analytics: analytics,
            delegate: delegate
        )
        await model.begin()

        await model.subscribe()

        #expect(model.purchasePhase == .idle)
        #expect(delegate.activations == 0)
        #expect(!analytics.eventNames.contains("subscription_success"))
        model.onDisappear()
    }

    @Test func hataSubscriptionFail() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.failed(.network(.timeout))]
        let analytics = MockAnalytics()
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            analytics: analytics,
            delegate: SpyVIPSubscriptionDelegate()
        )
        await model.begin()

        await model.subscribe()

        let fail = analytics.events.first { $0.name == "subscription_fail" }
        #expect(fail?.parameters["product_id"] == .string("vip_yearly"))
        #expect(fail?.parameters["error_code"] == .string("timeout"))
        #expect(fail?.parameters["stage"] == .string("storekit"))
        model.onDisappear()
    }

    @Test func yonetimAcilisiCancelIntent() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let gateway = FakeWalletGateway(subscription: .vip(plan: .weekly))
        let analytics = MockAnalytics()
        let delegate = SpyVIPSubscriptionDelegate()
        let model = makeModel(
            loader: loader,
            gateway: gateway,
            purchasing: FakeWalletPurchasing(),
            analytics: analytics,
            delegate: delegate
        )
        await model.begin()

        model.manageSubscription()

        #expect(delegate.manageRequests == 1)
        let intent = analytics.events.first { $0.name == "subscription_cancel_intent" }
        #expect(intent?.parameters["product_id"] == .string("vip_weekly"))
        model.onDisappear()
    }

    @Test func iadeSonrasiEntitlementDusurmeYansir() async {
        // 06 §8.4: iade/expiry → entitlement düşer; ekran yönetim→satın alma moduna geçer.
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let gateway = FakeWalletGateway(subscription: .vip(plan: .yearly))
        let model = makeModel(
            loader: loader,
            gateway: gateway,
            purchasing: FakeWalletPurchasing(),
            delegate: SpyVIPSubscriptionDelegate()
        )
        await model.begin()
        #expect(model.mode == .management)

        gateway.setSubscription(.none)
        gateway.pushEntitlement(EntitlementSnapshot(
            isVIP: false,
            vipExpiresAt: nil,
            isInGracePeriod: false,
            lastUnlockedEpisode: nil
        ))

        await waitUntil { model.mode == .purchase }
        #expect(model.mode == .purchase)
        model.onDisappear()
    }

    @Test func gracePeriodOdemeSorunuBanner() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let gateway = FakeWalletGateway(subscription: .vip(plan: .monthly, grace: true))
        let model = makeModel(
            loader: loader,
            gateway: gateway,
            purchasing: FakeWalletPurchasing(),
            delegate: SpyVIPSubscriptionDelegate()
        )
        await model.begin()

        #expect(model.showsPaymentIssueBanner)
        model.onDisappear()
    }

    @Test func planlarYuklenemezseFailed() async {
        let loader = FakeStorefrontLoader(products: .failure(.network(.offline)))
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: FakeWalletPurchasing(),
            delegate: SpyVIPSubscriptionDelegate()
        )

        await model.begin()

        #expect(model.loadPhase == .failed)
        model.onDisappear()
    }

    @Test func restoreCagriVeAnalitik() async {
        let loader = FakeStorefrontLoader(products: .success(plans()))
        let purchasing = FakeWalletPurchasing()
        let analytics = MockAnalytics()
        let model = makeModel(
            loader: loader,
            gateway: FakeWalletGateway(),
            purchasing: purchasing,
            analytics: analytics,
            delegate: SpyVIPSubscriptionDelegate()
        )
        await model.begin()

        await model.restore()

        #expect(purchasing.restoreCount == 1)
        #expect(analytics.eventNames.contains("restore_tapped"))
        model.onDisappear()
    }
}
