import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// VIPAbonelik: canlı entitlement aktivasyonunda didActivate (finding #2, idempotent) ve
/// subscription_cancel_intent product_id (specAnalytics #4, bilinmeyen plan dahil).
@MainActor
struct VIPSubscriptionActivationTests {
    private func plans() -> [StoreProduct] {
        [.vipYearly(), .vipWeekly(), .vipMonthly()]
    }

    private func makeModel(
        gateway: FakeWalletGateway,
        purchasing: FakeWalletPurchasing = FakeWalletPurchasing(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: SpyVIPSubscriptionDelegate
    ) -> VIPSubscriptionModel {
        VIPSubscriptionModel(
            source: .unlockSheet,
            loader: FakeStorefrontLoader(products: .success(plans())),
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

    @Test func canliEntitlementAktivasyonuDidActivateTetiklerVeIdempotenttir() async {
        // Finding #2: satın alma await'teyken başka cihaz/family/pending onayı VIP aktifleştirir →
        // canlı gözlem didActivate'i tetiklemeli. Sonra StoreKit .cancelled dönse bile aktivasyon
        // TEKRAR atılmaz (idempotent).
        let gateway = FakeWalletGateway(subscription: .none)
        let purchasing = FakeWalletPurchasing()
        let gate = AsyncGate()
        purchasing.purchaseGate = { await gate.wait() }
        purchasing.purchaseResults = [.cancelled]
        let delegate = SpyVIPSubscriptionDelegate()
        let model = makeModel(gateway: gateway, purchasing: purchasing, delegate: delegate)
        await model.begin()

        async let sub: Void = model.subscribe()
        await waitUntil { model.purchasePhase.isPurchasing }

        gateway.setSubscription(.vip(plan: .weekly))
        gateway.pushEntitlement(EntitlementSnapshot(
            isVIP: true,
            vipExpiresAt: nil,
            isInGracePeriod: false,
            lastUnlockedEpisode: nil
        ))
        await waitUntil { delegate.activations == 1 }

        await gate.open()
        await sub

        #expect(delegate.activations == 1) // .cancelled çift-atım yapmaz
        #expect(model.mode == .management)
        model.onDisappear()
    }

    @Test func zatenVIPYonetimModuSahteAktivasyonTetiklemez() async {
        // Yönetim modunda açılan (zaten VIP) ekran, canlı entitlement replay'inde didActivate ATMAZ.
        let gateway = FakeWalletGateway(subscription: .vip(plan: .monthly))
        let delegate = SpyVIPSubscriptionDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        gateway.pushEntitlement(EntitlementSnapshot(
            isVIP: true,
            vipExpiresAt: nil,
            isInGracePeriod: false,
            lastUnlockedEpisode: nil
        ))
        for _ in 0 ..< 200 {
            await Task.yield()
        } // gözleme işleme fırsatı

        #expect(delegate.activations == 0)
        model.onDisappear()
    }

    @Test func yonetimBilinmeyenPlanCancelIntentProductIDTasir() async {
        // specAnalytics #4: plan .unknown olsa bile subscription_cancel_intent product_id düşürmez.
        let gateway = FakeWalletGateway(subscription: .vip(plan: .unknown))
        let analytics = MockAnalytics()
        let model = makeModel(gateway: gateway, analytics: analytics, delegate: SpyVIPSubscriptionDelegate())
        await model.begin()

        model.manageSubscription()

        let intent = analytics.events.first { $0.name == "subscription_cancel_intent" }
        #expect(intent?.parameters["product_id"] == .string("vip_unknown"))
        model.onDisappear()
    }
}
