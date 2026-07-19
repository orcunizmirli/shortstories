import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// VIPAbonelik win-back KOMPOZİSYON kararları (SS-099 F1/F2). Çekirdek WinBack mantığı
/// (`WinBackSurface`/`WinBackEligibility`) DEĞİL, View'in okuduğu testable kararlar:
/// F1 — fiyatlı satın-alma CTA'sına BİTİŞİK §11.4 açıklaması HER modda (App Store 3.1.2);
///      normal fiyat/dönem StoreKit'ten, eksikse fiyatlı CTA gösterilmez (compliance > gösterim).
/// F2 — autoRenewOff banner bitiş cümlesini gösterirken managementSection'ın ayrı yenileme-tarihi
///      satırı bastırılır (tek kaynak; çift + format-tutarsız tarih gösterimi önlenir).
@MainActor
struct VIPSubscriptionWinBackDisclosureTests {
    private static let referenceNow = Date(timeIntervalSince1970: 1_752_278_400)
    private static let offer = WinBackOffer(
        displayPrice: "$2.99",
        paymentMode: .payUpFront,
        periodUnit: .week,
        periodValue: 1,
        periodCount: 1
    )

    private func yearlyProduct(displayPrice: String = "$49.99", winBack: WinBackOffer? = offer) -> StoreProduct {
        StoreProduct(
            id: SubscriptionPlan.yearly.productID,
            displayName: "VIP Yearly",
            displayPrice: displayPrice,
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

    private func plans(yearly: StoreProduct? = nil) -> [StoreProduct] {
        [yearly ?? yearlyProduct(), .vipWeekly(), .vipMonthly()]
    }

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

    private func autoRenewOffVIP() -> SubscriptionStatus {
        .vip(plan: .yearly, expiresAt: Self.referenceNow.addingTimeInterval(5 * 86400), willAutoRenew: false)
    }

    private func config(
        variant: WinBackVariant = .discount,
        serverSignal: WinBackServerSignal? = nil
    ) -> WinBackConfiguration {
        let now = Self.referenceNow
        return WinBackConfiguration(
            isRemoteConfigEnabled: true,
            variant: variant,
            serverSignal: serverSignal,
            frequency: .fresh,
            now: { now },
            expiryDateFormatter: { _ in "12 Ağustos 2026" }
        )
    }

    private func makeModel(
        subscription: SubscriptionStatus,
        products: [StoreProduct]? = nil,
        winBack: WinBackConfiguration
    ) -> VIPSubscriptionModel {
        VIPSubscriptionModel(
            source: .profil,
            loader: FakeStorefrontLoader(products: .success(products ?? plans())),
            wallet: FakeWalletGateway(subscription: subscription),
            purchasing: FakeWalletPurchasing(),
            analytics: MockAnalytics(),
            winBack: winBack,
            delegate: SpyVIPSubscriptionDelegate()
        )
    }

    // MARK: - F1 — §11.4 açıklaması fiyatlı CTA'ya bitişik, HER modda

    @Test func managementModundaFiyatliCTA11_4AciklamasiGerektirir() async {
        // autoRenewOff hâlâ-VIP → management modu; discount + offer → fiyatlı win-back CTA.
        let model = makeModel(subscription: autoRenewOffVIP(), winBack: config(variant: .discount))
        await model.begin()

        #expect(model.mode == .management)
        #expect(model.winBackRequiresRenewalDisclosure)
        let disclosure = model.winBackRenewalDisclosure
        // Offer haftalık, mevcut plan yıllık → dönem yanıltması açıklamada NET gösterilir.
        #expect(disclosure?.offerPrice == "$2.99")
        #expect(disclosure?.offerPeriod == "hafta")
        #expect(disclosure?.regularPrice == "$49.99")
        #expect(disclosure?.regularPeriod == "yıl")
        #expect(disclosure?.priceSummary == "İlk hafta $2.99, sonra $49.99/yıl")
        #expect(model.winBackBannerOfferPrice == "$2.99")
        model.onDisappear()
    }

    @Test func eskiVIPPurchaseModuFiyatliCTA11_4AciklamasiGerektirir() async {
        let model = makeModel(subscription: formerVIP(), winBack: config(variant: .discount))
        await model.begin()

        #expect(model.mode == .purchase)
        #expect(model.winBackRequiresRenewalDisclosure)
        #expect(model.winBackRenewalDisclosure?.offerPrice == "$2.99")
        #expect(model.winBackRenewalDisclosure?.regularPrice == "$49.99")
        model.onDisappear()
    }

    @Test func reminderFiyatsizCTAAciklamaGerektirmez() async {
        let model = makeModel(subscription: formerVIP(), winBack: config(variant: .reminder))
        await model.begin()

        #expect(model.winBackRequiresRenewalDisclosure == false)
        #expect(model.winBackRenewalDisclosure == nil)
        #expect(model.winBackBannerOfferPrice == nil)
        model.onDisappear()
    }

    @Test func normalFiyatEksikseFiyatliCTAGosterilmez() async {
        // Canlı katman offer'ı doldurmuş ama ürünün normal (offer-sonrası) fiyatı henüz boş →
        // §11.4 bilgisi TAM değil → fiyatlı CTA GÖSTERİLMEZ (compliance > gösterim).
        let model = makeModel(
            subscription: formerVIP(),
            products: plans(yearly: yearlyProduct(displayPrice: "")),
            winBack: config(variant: .discount)
        )
        await model.begin()

        #expect(model.winBackRenewalDisclosure == nil)
        #expect(model.winBackRequiresRenewalDisclosure == false)
        #expect(model.winBackBannerOfferPrice == nil)
        model.onDisappear()
    }

    // MARK: - F2 — çift/format-tutarsız bitiş tarihi (management yenileme satırı bastırılır)

    @Test func autoRenewOffBannerGorunurkenManagementYenilemeSatiriBastirilir() async {
        let model = makeModel(subscription: autoRenewOffVIP(), winBack: config(variant: .discount))
        await model.begin()

        #expect(model.winBackSurface.isVisible)
        #expect(model.winBackSurface.reason == .autoRenewOff)
        #expect(model.showsManagementRenewalText == false)
        model.onDisappear()
    }

    @Test func serverSegmentBanneriManagementYenilemeSatiriniBastirmaz() async {
        // Aktif, auto-renew AÇIK VIP + backend segment → banner görünür ama reason autoRenewOff DEĞİL;
        // banner bitiş tarihi göstermez → management yenileme satırı KALIR (çift gösterim yok).
        let activeVIP = SubscriptionStatus.vip(plan: .yearly, willAutoRenew: true)
        let model = makeModel(subscription: activeVIP, winBack: config(variant: .discount, serverSignal: .eligible))
        await model.begin()

        #expect(model.winBackSurface.reason == .serverSegment)
        #expect(model.showsManagementRenewalText)
        model.onDisappear()
    }

    @Test func bannerGizliykenManagementYenilemeSatiriKalir() async {
        let activeVIP = SubscriptionStatus.vip(plan: .yearly, willAutoRenew: true)
        let model = makeModel(subscription: activeVIP, winBack: .disabled)
        await model.begin()

        #expect(model.winBackSurface.isVisible == false)
        #expect(model.showsManagementRenewalText)
        model.onDisappear()
    }
}
