import Foundation
import Testing
@testable import WalletKit

/// Win-back offer SAF türetimi (SS-099 F2): üründen GRACEFUL okuma, offer yoksa `nil` (06 §8.2
/// intro deseni), fiyat StoreKit `displayPrice`'tan (hardcode YASAK, 06 §11.2).
struct WinBackOfferTests {
    private func vip(winBack: WinBackOffer?) -> StoreProduct {
        StoreProduct(
            id: SubscriptionPlan.weekly.productID,
            displayName: "VIP",
            displayPrice: "$5.99",
            price: 5.99,
            kind: .subscription,
            subscription: SubscriptionInfo(
                isEligibleForIntroOffer: false,
                introOffer: nil,
                periodUnit: .week,
                periodValue: 1,
                winBackOffer: winBack
            )
        )
    }

    private static let offer = WinBackOffer(
        displayPrice: "$2.99",
        paymentMode: .payUpFront,
        periodUnit: .week,
        periodValue: 1,
        periodCount: 1
    )

    @Test func offerVarsaTuretilir() {
        let product = vip(winBack: Self.offer)
        #expect(WinBackOffer.resolve(from: product) == Self.offer)
    }

    @Test func offerYoksaNil() {
        // Abonelik var ama win-back offer yok (canlı katman doldurmadı) → graceful nil.
        #expect(WinBackOffer.resolve(from: vip(winBack: nil)) == nil)
    }

    @Test func abonelikDegilseNil() {
        let coin = StoreProduct(
            id: "com.shortseries.coins.tier1",
            displayName: "Coins",
            displayPrice: "$0.99",
            price: 0.99,
            kind: .coinPack,
            subscription: nil
        )
        #expect(WinBackOffer.resolve(from: coin) == nil)
    }

    @Test func fiyatUrundenGelirHardcodeDegil() {
        // Farklı storefront fiyatı olduğu gibi taşınır (USD hardcode değil).
        let product = vip(winBack: WinBackOffer(
            displayPrice: "₺89,99",
            paymentMode: .payAsYouGo,
            periodUnit: .month,
            periodValue: 1,
            periodCount: 3
        ))
        #expect(WinBackOffer.resolve(from: product)?.displayPrice == "₺89,99")
    }
}
