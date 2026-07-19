import Foundation
import Testing
@testable import WalletKit

/// Win-back yüzey görünürlük + mesaj kararının SAF mantığı (SS-099 F2): dört kapı (remote config /
/// uygunluk / varyant-holdout / frekans tavanı), A/B varyant mesaj/treatment seçimi, bitiş tarihi
/// cümlesi (06 §8.2) ve fiyat gösterim kuralı (yalnız discount + offer; 06 §8.2). `now` enjekte.
struct WinBackSurfaceTests {
    private let now = Date(timeIntervalSince1970: 1_752_278_400)

    private static let offer = WinBackOffer(
        displayPrice: "$2.99",
        paymentMode: .payUpFront,
        periodUnit: .week,
        periodValue: 1,
        periodCount: 1
    )

    private func resolve(
        eligibility: WinBackEligibility = .eligible(.formerVIP),
        remoteConfigEnabled: Bool = true,
        variant: WinBackVariant = .discount,
        frequency: WinBackFrequency = .fresh,
        policy: WinBackFrequencyPolicy = .default,
        offer: WinBackOffer? = offer,
        expiryDateText: String? = "12 Ağustos 2026"
    ) -> WinBackSurface {
        WinBackSurface.resolve(
            eligibility: eligibility,
            remoteConfigEnabled: remoteConfigEnabled,
            variant: variant,
            frequency: frequency,
            policy: policy,
            offer: offer,
            expiryDateText: expiryDateText,
            now: now
        )
    }

    // MARK: - Görünürlük kapıları

    @Test func remoteConfigKapaliGizli() {
        #expect(resolve(remoteConfigEnabled: false) == .hidden)
    }

    @Test func uygunDegilseGizli() {
        #expect(resolve(eligibility: .ineligible) == .hidden)
    }

    @Test func controlVaryantHoldoutGizli() {
        #expect(resolve(variant: .control) == .hidden)
    }

    @Test func frekansTavaniDolduGizli() {
        // Varsayılan maxShows = 3; shownCount 3 → tavan dolu.
        let freq = WinBackFrequency(lastShownAt: now.addingTimeInterval(-10 * 86400), shownCount: 3)
        #expect(resolve(frequency: freq).isVisible == false)
    }

    @Test func frekansMinAralikGecmemisGizli() {
        // Son gösterim 2 saat önce; minInterval 24 saat → henüz gösterilemez.
        let freq = WinBackFrequency(lastShownAt: now.addingTimeInterval(-2 * 3600), shownCount: 1)
        #expect(resolve(frequency: freq).isVisible == false)
    }

    @Test func minAralikGectiVeTavanAltiGorunur() {
        let freq = WinBackFrequency(lastShownAt: now.addingTimeInterval(-2 * 86400), shownCount: 1)
        #expect(resolve(frequency: freq).isVisible)
    }

    @Test func tumKapilarAcikGorunur() {
        let surface = resolve()
        #expect(surface.isVisible)
        #expect(surface.variant == .discount)
        #expect(surface.reason == .formerVIP)
    }

    // MARK: - Eski VIP mesajı + fiyat kuralı

    @Test func eskiVIPDiscountFiyatGosterir() {
        let surface = resolve(eligibility: .eligible(.formerVIP), variant: .discount)
        #expect(surface.message == "VIP'e indirimli dön: $2.99.")
        #expect(surface.offerDisplayPrice == "$2.99")
    }

    @Test func eskiVIPDiscountOfferYoksaFiyatsiz() {
        // Offer yok → fiyat gösterilmez (06 §8.2), yapısal alan da nil.
        let surface = resolve(eligibility: .eligible(.formerVIP), variant: .discount, offer: nil)
        #expect(surface.message == "Seni özledik. VIP avantajları seni bekliyor.")
        #expect(surface.offerDisplayPrice == nil)
    }

    @Test func eskiVIPReminderFiyatAnmaz() {
        // reminder treatment fayda-odaklı; offer olsa bile fiyat anmaz, yapısal alan nil.
        let surface = resolve(eligibility: .eligible(.formerVIP), variant: .reminder)
        #expect(surface.message == "Seni özledik. VIP avantajları seni bekliyor.")
        #expect(surface.offerDisplayPrice == nil)
    }

    @Test func serverSegmentEskiVIPGibiMesajlanir() {
        let surface = resolve(eligibility: .eligible(.serverSegment), variant: .discount)
        #expect(surface.message == "VIP'e indirimli dön: $2.99.")
    }

    // MARK: - Auto-renew kapalı: bitiş tarihi cümlesi (06 §8.2)

    @Test func autoRenewOffBitisTarihiVeFiyat() {
        let surface = resolve(eligibility: .eligible(.autoRenewOff), variant: .discount)
        #expect(surface.message == "Aboneliğin 12 Ağustos 2026 tarihinde sona erecek. İndirimli fiyatla sürdür: $2.99.")
        #expect(surface.offerDisplayPrice == "$2.99")
    }

    @Test func autoRenewOffReminderFiyatsiz() {
        let surface = resolve(eligibility: .eligible(.autoRenewOff), variant: .reminder)
        let expected = "Aboneliğin 12 Ağustos 2026 tarihinde sona erecek. "
            + "VIP avantajlarını korumak için dilediğin an yenileyebilirsin."
        #expect(surface.message == expected)
        #expect(surface.offerDisplayPrice == nil)
    }

    @Test func autoRenewOffTarihMetniYoksaCumleDuser() {
        // App bitiş tarihini biçimleyemediyse (nil) tarih cümlesi graceful atlanır.
        let surface = resolve(eligibility: .eligible(.autoRenewOff), variant: .discount, expiryDateText: nil)
        #expect(surface.message == "İndirimli fiyatla sürdür: $2.99.")
    }

    // MARK: - Frekans politikası birim davranışı

    @Test func ozelPolitikaTavani() {
        let policy = WinBackFrequencyPolicy(maxShows: 1, minInterval: 0)
        #expect(resolve(frequency: WinBackFrequency(lastShownAt: nil, shownCount: 1), policy: policy).isVisible == false)
        #expect(resolve(frequency: .fresh, policy: policy).isVisible)
    }
}
