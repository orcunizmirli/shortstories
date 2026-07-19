import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// VIPAbonelik win-back banner seam'i (SS-099 F2): model'in App-enjekte remote-config/varyant/
/// segment/frekans girdilerinden `WinBackSurface`'i türetmesi. Server-otoriter (istemci karar
/// vermez), remote-config OFF varsayılanı (banner yok = mevcut davranış), A/B varyant, offer
/// graceful, CTA satın-alma akışına bağlanır. `now` + tarih biçimleyici enjekte → deterministik.
@MainActor
struct VIPSubscriptionWinBackTests {
    private static let referenceNow = Date(timeIntervalSince1970: 1_752_278_400)
    private static let offer = WinBackOffer(
        displayPrice: "$2.99",
        paymentMode: .payUpFront,
        periodUnit: .week,
        periodValue: 1,
        periodCount: 1
    )

    // MARK: - Fixtures

    /// Yıllık VIP ürünü + (opsiyonel) win-back offer'ı — offer'ın graceful okunuşunu test etmek için.
    private func yearlyProduct(winBack: WinBackOffer? = offer) -> StoreProduct {
        StoreProduct(
            id: SubscriptionPlan.yearly.productID,
            displayName: "VIP Yearly",
            displayPrice: "$49.99",
            price: 49.99,
            kind: .subscription,
            subscription: SubscriptionInfo(
                isEligibleForIntroOffer: false,
                introOffer: nil,
                periodUnit: .year,
                periodValue: 1,
                winBackOffer: winBack
            )
        )
    }

    private func plans(winBack: WinBackOffer? = offer) -> [StoreProduct] {
        [yearlyProduct(winBack: winBack), .vipWeekly(), .vipMonthly()]
    }

    /// Eski VIP: abonelik bitmiş (isVIP=false), üzerinden 10 gün geçmiş (>7 gün eşiği).
    private func formerVIP() -> SubscriptionStatus {
        SubscriptionStatus(
            isVIP: false,
            plan: .yearly,
            expiresAt: Self.referenceNow.addingTimeInterval(-10 * 86400),
            willAutoRenew: false,
            isInGracePeriod: false,
            isInIntroOffer: false,
            dailyBonusCoins: 0,
            dailyBonusClaimedToday: false
        )
    }

    /// Hâlâ VIP ama auto-renew kapalı, dönem sonu 5 gün sonra (churn-risk).
    private func autoRenewOffVIP() -> SubscriptionStatus {
        .vip(
            plan: .yearly,
            expiresAt: Self.referenceNow.addingTimeInterval(5 * 86400),
            willAutoRenew: false
        )
    }

    private func config(
        enabled: Bool = true,
        variant: WinBackVariant = .discount,
        serverSignal: WinBackServerSignal? = nil,
        frequency: WinBackFrequency = .fresh,
        onBannerShown: (@Sendable (WinBackVariant, WinBackEligibility.Reason) -> Void)? = nil
    ) -> WinBackConfiguration {
        let now = Self.referenceNow
        return WinBackConfiguration(
            isRemoteConfigEnabled: enabled,
            variant: variant,
            serverSignal: serverSignal,
            frequency: frequency,
            now: { now },
            expiryDateFormatter: { _ in "12 Ağustos 2026" },
            onBannerShown: onBannerShown
        )
    }

    private func makeModel(
        subscription: SubscriptionStatus,
        products: [StoreProduct]? = nil,
        winBack: WinBackConfiguration,
        purchasing: FakeWalletPurchasing = FakeWalletPurchasing()
    ) -> VIPSubscriptionModel {
        VIPSubscriptionModel(
            source: .profil,
            loader: FakeStorefrontLoader(products: .success(products ?? plans())),
            wallet: FakeWalletGateway(subscription: subscription),
            purchasing: purchasing,
            analytics: MockAnalytics(),
            winBack: winBack,
            delegate: SpyVIPSubscriptionDelegate()
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - Remote-config OFF varsayılanı (mevcut davranış korunur)

    @Test func varsayilanDisabledBannerGizli() async {
        // .disabled seam (App bağlamadı) → uygun kullanıcıda bile banner yok.
        let model = makeModel(subscription: formerVIP(), winBack: .disabled)
        await model.begin()
        #expect(model.winBackSurface == .hidden)
        #expect(model.winBackSurface.isVisible == false)
        model.onDisappear()
    }

    @Test func remoteConfigKapaliGizli() async {
        let model = makeModel(subscription: formerVIP(), winBack: config(enabled: false))
        await model.begin()
        #expect(model.winBackSurface.isVisible == false)
        model.onDisappear()
    }

    // MARK: - Eski VIP + A/B varyant

    @Test func eskiVIPDiscountFiyatliBanner() async {
        let model = makeModel(subscription: formerVIP(), winBack: config(variant: .discount))
        await model.begin()

        let surface = model.winBackSurface
        #expect(surface.isVisible)
        #expect(surface.variant == .discount)
        #expect(surface.reason == .formerVIP)
        #expect(surface.message == "VIP'e indirimli dön: $2.99.")
        #expect(surface.offerDisplayPrice == "$2.99")
        model.onDisappear()
    }

    @Test func eskiVIPReminderFiyatsiz() async {
        let model = makeModel(subscription: formerVIP(), winBack: config(variant: .reminder))
        await model.begin()

        let surface = model.winBackSurface
        #expect(surface.isVisible)
        #expect(surface.variant == .reminder)
        #expect(surface.message == "Seni özledik. VIP avantajları seni bekliyor.")
        #expect(surface.offerDisplayPrice == nil)
        model.onDisappear()
    }

    @Test func controlVaryantHoldoutGizli() async {
        let model = makeModel(subscription: formerVIP(), winBack: config(variant: .control))
        await model.begin()
        #expect(model.winBackSurface.isVisible == false)
        model.onDisappear()
    }

    // MARK: - Auto-renew kapalı: bitiş tarihi (App enjekte formatter kullanılır)

    @Test func autoRenewOffBitisTarihiVeFiyat() async {
        let model = makeModel(subscription: autoRenewOffVIP(), winBack: config(variant: .discount))
        await model.begin()

        let surface = model.winBackSurface
        #expect(surface.isVisible)
        #expect(surface.reason == .autoRenewOff)
        // Enjekte formatter'ın ürettiği tarih cümlede birebir görünür (saf mantık biçimlemez).
        #expect(surface.message == "Aboneliğin 12 Ağustos 2026 tarihinde sona erecek. İndirimli fiyatla sürdür: $2.99.")
        #expect(surface.offerDisplayPrice == "$2.99")
        model.onDisappear()
    }

    // MARK: - Offer graceful yokluğu (06 §8.2)

    @Test func offerYokGracefulFiyatsiz() async {
        let model = makeModel(
            subscription: formerVIP(),
            products: plans(winBack: nil), // canlı katman offer'ı doldurmadı
            winBack: config(variant: .discount)
        )
        await model.begin()

        let surface = model.winBackSurface
        #expect(surface.isVisible)
        #expect(surface.message == "Seni özledik. VIP avantajları seni bekliyor.")
        #expect(surface.offerDisplayPrice == nil)
        model.onDisappear()
    }

    // MARK: - Frekans tavanı (07 §5.3)

    @Test func frekansTavaniDolduGizli() async {
        let freq = WinBackFrequency(lastShownAt: Self.referenceNow.addingTimeInterval(-10 * 86400), shownCount: 3)
        let model = makeModel(subscription: formerVIP(), winBack: config(frequency: freq))
        await model.begin()
        #expect(model.winBackSurface.isVisible == false)
        model.onDisappear()
    }

    // MARK: - Server-otoriter (istemci karar vermez)

    @Test func serverSignalExcludedYerelUygunOlsaBileGizli() async {
        // Yerel olarak eski VIP uygun ama backend dışladı (holdout/fraud) → gizli.
        let model = makeModel(subscription: formerVIP(), winBack: config(serverSignal: .excluded))
        await model.begin()
        #expect(model.winBackSurface.isVisible == false)
        model.onDisappear()
    }

    @Test func serverSignalEligibleYerelUygunsuzOlsaBileGorunur() async {
        // Aktif, auto-renew AÇIK VIP → yerel türev uygun DEĞİL; ama backend segmente aldı → görünür.
        let activeVIP = SubscriptionStatus.vip(plan: .yearly, willAutoRenew: true)
        let model = makeModel(subscription: activeVIP, winBack: config(variant: .discount, serverSignal: .eligible))
        await model.begin()

        let surface = model.winBackSurface
        #expect(surface.isVisible)
        #expect(surface.reason == .serverSegment)
        #expect(surface.message == "VIP'e indirimli dön: $2.99.")
        model.onDisappear()
    }

    // MARK: - App frekans persist seam (banner göründü bildirimi)

    @Test func bannerGorununceOnShownBirKezTetiklenir() async {
        let recorder = ShownRecorder()
        let model = makeModel(
            subscription: formerVIP(),
            winBack: config(variant: .discount, onBannerShown: { recorder.record($0, $1) })
        )
        await model.begin()

        model.winBackBannerAppeared()
        model.winBackBannerAppeared() // idempotent
        #expect(recorder.calls.count == 1)
        #expect(recorder.calls.first?.0 == .discount)
        #expect(recorder.calls.first?.1 == .formerVIP)
        model.onDisappear()
    }

    @Test func gizliBannerdaOnShownTetiklenmez() async {
        let recorder = ShownRecorder()
        let model = makeModel(
            subscription: formerVIP(),
            winBack: config(variant: .control, onBannerShown: { recorder.record($0, $1) })
        )
        await model.begin()

        model.winBackBannerAppeared()
        #expect(recorder.calls.isEmpty)
        model.onDisappear()
    }

    // MARK: - CTA mevcut satın-alma akışına bağlanır (coin/entitlement mutasyonu yok)

    @Test func winBackCTASatinAlmaAkisiniTetikler() async {
        let purchasing = FakeWalletPurchasing()
        purchasing.purchaseResults = [.completed(transactionID: "wb_txn_1")]
        let model = makeModel(subscription: formerVIP(), winBack: config(variant: .discount), purchasing: purchasing)
        await model.begin()

        model.subscribeViaWinBack()
        await waitUntil { purchasing.purchaseCallCount == 1 }

        #expect(purchasing.purchaseCallCount == 1)
        // Offer'ın ait olduğu (yıllık) plan seçilip satın alma akışına bağlanır.
        #expect(model.selectedPlan == .yearly)
        model.onDisappear()
    }
}

/// Frekans-persist seam'inin @Sendable kapanışından güvenli kayıt için küçük kutu.
private final class ShownRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(WinBackVariant, WinBackEligibility.Reason)] = []

    var calls: [(WinBackVariant, WinBackEligibility.Reason)] {
        lock.withLock { _calls }
    }

    func record(_ variant: WinBackVariant, _ reason: WinBackEligibility.Reason) {
        lock.withLock { _calls.append((variant, reason)) }
    }
}
