import Foundation
import Testing
@testable import WalletKit

/// VIP win-back uygunluk kararının SAF mantığı (SS-099 F2): server-otoriter sinyal önceliği,
/// grace istisnası, auto-renew-off churn-risk ve eski-VIP 7-gün eşiği. `now` enjekte →
/// deterministik. Churn/segment SERVER-OTORİTERdir; istemci yalnız yerel hızlı-yol türetir.
struct WinBackEligibilityTests {
    /// Sabit referans "şimdi" — 2026-07-12 00:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_752_278_400)

    private func daysFromNow(_ days: Double) -> Date {
        now.addingTimeInterval(days * 86400)
    }

    /// Eski/lapsed VIP: artık VIP değil, aboneliği `expiredDaysAgo` gün önce bitti.
    private func formerVIP(expiredDaysAgo days: Double) -> SubscriptionStatus {
        SubscriptionStatus(
            isVIP: false,
            plan: .weekly,
            expiresAt: daysFromNow(-days),
            willAutoRenew: false,
            isInGracePeriod: false,
            isInIntroOffer: false,
            dailyBonusCoins: 0,
            dailyBonusClaimedToday: false
        )
    }

    // MARK: - Sunucu otoritesi (istemci churn'e karar vermez)

    @Test func serverEligibleHerZamanUygun() {
        // Aktif, otomatik yenilenen VIP olsa bile sunucu segmenti otoriterdir.
        let result = WinBackEligibility.evaluate(
            subscription: .vip(willAutoRenew: true),
            serverSignal: .eligible,
            now: now
        )
        #expect(result == .eligible(.serverSegment))
    }

    @Test func serverExcludedYerelTetikleyiciyiEzer() {
        // Yerel olarak eski-VIP (30 gün) tetiklenirdi; sunucu holdout/fraud dışlaması ezer.
        let result = WinBackEligibility.evaluate(
            subscription: formerVIP(expiredDaysAgo: 30),
            serverSignal: .excluded,
            now: now
        )
        #expect(result == .ineligible)
    }

    // MARK: - Grace / billing-retry churn değil (06 §8.4)

    @Test func gracePeriodUygunDegil() {
        let sub = SubscriptionStatus(
            isVIP: true, plan: .monthly, expiresAt: daysFromNow(3),
            willAutoRenew: false, isInGracePeriod: true, isInIntroOffer: false,
            dailyBonusCoins: 0, dailyBonusClaimedToday: false
        )
        #expect(WinBackEligibility.evaluate(subscription: sub, serverSignal: nil, now: now) == .ineligible)
    }

    // MARK: - Auto-renew kapalı churn-risk (06 §5.1/§8.3)

    @Test func vipAutoRenewKapaliGelecekBitis() {
        let sub = SubscriptionStatus.vip(expiresAt: daysFromNow(5), grace: false, willAutoRenew: false)
        #expect(WinBackEligibility.evaluate(subscription: sub, serverSignal: nil, now: now) == .eligible(.autoRenewOff))
    }

    @Test func aktifOtomatikYenilenenVIPUygunDegil() {
        let sub = SubscriptionStatus.vip(expiresAt: daysFromNow(5), grace: false, willAutoRenew: true)
        #expect(WinBackEligibility.evaluate(subscription: sub, serverSignal: nil, now: now) == .ineligible)
    }

    @Test func vipAutoRenewKapaliAmaBitisGecmisUygunDegil() {
        // isVIP hâlâ true ama expiry geçmişte (tutarsız/geçiş anı) → churn-risk penceresi yok.
        let sub = SubscriptionStatus.vip(expiresAt: daysFromNow(-1), grace: false, willAutoRenew: false)
        #expect(WinBackEligibility.evaluate(subscription: sub, serverSignal: nil, now: now) == .ineligible)
    }

    @Test func vipAutoRenewKapaliExpiryNilUygunDegil() {
        let sub = SubscriptionStatus.vip(expiresAt: nil, grace: false, willAutoRenew: false)
        #expect(WinBackEligibility.evaluate(subscription: sub, serverSignal: nil, now: now) == .ineligible)
    }

    // MARK: - nearExpiryWindow ("dönem sonuna yakın")

    @Test func nearExpiryPenceresiDisindaUygunDegil() {
        let sub = SubscriptionStatus.vip(expiresAt: daysFromNow(20), grace: false, willAutoRenew: false)
        let result = WinBackEligibility.evaluate(
            subscription: sub, serverSignal: nil, now: now, nearExpiryWindow: 7 * 86400
        )
        #expect(result == .ineligible)
    }

    @Test func nearExpiryPenceresiIcindeUygun() {
        let sub = SubscriptionStatus.vip(expiresAt: daysFromNow(3), grace: false, willAutoRenew: false)
        let result = WinBackEligibility.evaluate(
            subscription: sub, serverSignal: nil, now: now, nearExpiryWindow: 7 * 86400
        )
        #expect(result == .eligible(.autoRenewOff))
    }

    // MARK: - Eski VIP 7-gün eşiği (07 §7)

    @Test func eskiVIPSekizGunUygun() {
        #expect(
            WinBackEligibility.evaluate(subscription: formerVIP(expiredDaysAgo: 8), serverSignal: nil, now: now)
                == .eligible(.formerVIP)
        )
    }

    @Test func eskiVIPTazeChurnUcGunUygunDegil() {
        #expect(
            WinBackEligibility.evaluate(subscription: formerVIP(expiredDaysAgo: 3), serverSignal: nil, now: now)
                == .ineligible
        )
    }

    @Test func eskiVIPTamYediGunSinirUygun() {
        // now >= expiry + 7 gün → sınır dahil.
        #expect(
            WinBackEligibility.evaluate(subscription: formerVIP(expiredDaysAgo: 7), serverSignal: nil, now: now)
                == .eligible(.formerVIP)
        )
    }

    @Test func hicAboneOlmamisUygunDegil() {
        #expect(WinBackEligibility.evaluate(subscription: .none, serverSignal: nil, now: now) == .ineligible)
    }

    @Test func ozelGunEsigiOverride() {
        // 5 gün önce bitti, eşik 3'e düşürülürse uygun.
        let result = WinBackEligibility.evaluate(
            subscription: formerVIP(expiredDaysAgo: 5), serverSignal: nil, now: now, formerVIPGraceDays: 3
        )
        #expect(result == .eligible(.formerVIP))
    }

    // MARK: - Erişimciler

    @Test func isEligibleVeReasonErisimcileri() {
        let eligible = WinBackEligibility.eligible(.formerVIP)
        #expect(eligible.isEligible)
        #expect(eligible.reason == .formerVIP)

        let ineligible = WinBackEligibility.ineligible
        #expect(!ineligible.isEligible)
        #expect(ineligible.reason == nil)
    }
}
