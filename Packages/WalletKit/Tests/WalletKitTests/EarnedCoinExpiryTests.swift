import Foundation
import Testing
@testable import WalletKit

/// Earned coin vadesi SAF mantığı (06 §2.5): yaklaşan-vade uyarısı, FEFO harcama ön-izlemesi,
/// bucket toplama. `now` enjekte edilir → deterministik, izole. Bakiye server-otoriter;
/// bu türevler yalnız gösterim içindir.
struct EarnedCoinExpiryTests {
    /// Sabit referans "şimdi" — 2026-07-12 00:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_752_278_400)

    private func daysFromNow(_ days: Double) -> Date {
        now.addingTimeInterval(days * 86400)
    }

    // MARK: - Yaklaşan-vade uyarısı

    @Test func esikIcindekiLotlarToplanir() {
        let buckets = [
            EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(2)),
            EarnedCoinBucket(amount: 20, expiresAt: daysFromNow(5))
        ]
        let notice = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now)

        #expect(notice?.coins == 50)
        #expect(notice?.bucketCount == 2)
        #expect(notice?.earliestExpiresAt == daysFromNow(2)) // en erken yanma
    }

    @Test func esikDisiLotlarSayilmaz() {
        // 7 gün eşiği: 10 gün sonrası pencere DIŞI.
        let buckets = [
            EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(3)),
            EarnedCoinBucket(amount: 100, expiresAt: daysFromNow(10))
        ]
        let notice = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now)

        #expect(notice?.coins == 30)
        #expect(notice?.bucketCount == 1)
    }

    @Test func suresiGecmisLotlarHaric() {
        // expiresAt <= now → sunucu zaten düştü; sayılmaz.
        let buckets = [
            EarnedCoinBucket(amount: 40, expiresAt: daysFromNow(-1)), // dün yandı
            EarnedCoinBucket(amount: 25, expiresAt: daysFromNow(4))
        ]
        let notice = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now)

        #expect(notice?.coins == 25)
        #expect(notice?.bucketCount == 1)
        #expect(notice?.earliestExpiresAt == daysFromNow(4))
    }

    @Test func tamAnindaExpireHaricSinirDahil() {
        // now anında expire → hariç; tam now+eşik → dahil (sınır kapsayıcı).
        let buckets = [
            EarnedCoinBucket(amount: 10, expiresAt: now), // now → hariç
            EarnedCoinBucket(
                amount: 15,
                expiresAt: now.addingTimeInterval(EarnedCoinExpiryPlanner.defaultThreshold)
            ) // tam sınır → dahil
        ]
        let notice = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now)

        #expect(notice?.coins == 15)
        #expect(notice?.bucketCount == 1)
    }

    @Test func uygunLotYoksaNil() {
        let buckets = [EarnedCoinBucket(amount: 50, expiresAt: daysFromNow(30))]
        #expect(EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now) == nil)
        #expect(EarnedCoinExpiryPlanner.upcomingExpiry(buckets: [], now: now) == nil)
    }

    @Test func sifirCoinLotSayilmaz() {
        let buckets = [
            EarnedCoinBucket(amount: 0, expiresAt: daysFromNow(2)),
            EarnedCoinBucket(amount: 12, expiresAt: daysFromNow(3))
        ]
        let notice = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now)

        #expect(notice?.coins == 12)
        #expect(notice?.bucketCount == 1)
    }

    @Test func esikYapilandirilabilir() {
        let buckets = [EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(10))]
        // Varsayılan 7 gün → nil; 14 gün eşiği → yakalar.
        #expect(EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now) == nil)
        let wide = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: buckets, now: now, within: 14 * 86400)
        #expect(wide?.coins == 30)
    }

    // MARK: - Bucket toplama

    @Test func totalUnexpiredSuresiGecmisiHaricTutar() {
        let buckets = [
            EarnedCoinBucket(amount: 40, expiresAt: daysFromNow(-2)), // geçmiş
            EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(3)),
            EarnedCoinBucket(amount: 20, expiresAt: daysFromNow(40)) // pencere dışı ama geçerli
        ]
        #expect(EarnedCoinExpiryPlanner.totalUnexpired(buckets: buckets, now: now) == 50)
    }

    // MARK: - FEFO sıralama

    @Test func fefoOrderEnErkenOnceVeGecmisiEler() {
        let buckets = [
            EarnedCoinBucket(amount: 20, expiresAt: daysFromNow(5)),
            EarnedCoinBucket(amount: 10, expiresAt: daysFromNow(-1)), // geçmiş → elenir
            EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(2))
        ]
        let ordered = EarnedCoinExpiryPlanner.fefoOrder(buckets, now: now)

        #expect(ordered.count == 2)
        #expect(ordered[0].expiresAt == daysFromNow(2)) // en erken önce
        #expect(ordered[1].expiresAt == daysFromNow(5))
    }

    // MARK: - Earned-önce FEFO harcama ön-izlemesi

    @Test func earnedSpendPreviewFEFOSirasiylaBoler() {
        // 45 earned harca: önce 30 (2 gün) tamamen, sonra 15 (5 gün) kısmi.
        let buckets = [
            EarnedCoinBucket(amount: 20, expiresAt: daysFromNow(5)),
            EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(2))
        ]
        let lines = EarnedCoinExpiryPlanner.earnedSpendPreview(earnedAmount: 45, buckets: buckets, now: now)

        #expect(lines.count == 2)
        #expect(lines[0] == EarnedSpendLine(coins: 30, expiresAt: daysFromNow(2))) // en erken tamamen
        #expect(lines[1] == EarnedSpendLine(coins: 15, expiresAt: daysFromNow(5))) // kısmi
    }

    @Test func earnedSpendPreviewTekLotKismi() {
        let buckets = [EarnedCoinBucket(amount: 100, expiresAt: daysFromNow(3))]
        let lines = EarnedCoinExpiryPlanner.earnedSpendPreview(earnedAmount: 40, buckets: buckets, now: now)

        #expect(lines == [EarnedSpendLine(coins: 40, expiresAt: daysFromNow(3))])
    }

    @Test func earnedSpendPreviewSuresiGecmisLottanCekmez() {
        let buckets = [
            EarnedCoinBucket(amount: 50, expiresAt: daysFromNow(-1)), // geçmiş → atlanır
            EarnedCoinBucket(amount: 25, expiresAt: daysFromNow(4))
        ]
        let lines = EarnedCoinExpiryPlanner.earnedSpendPreview(earnedAmount: 20, buckets: buckets, now: now)

        #expect(lines == [EarnedSpendLine(coins: 20, expiresAt: daysFromNow(4))])
    }

    @Test func earnedSpendPreviewMevcuttanFazlaIstenirseMevcutuVerir() {
        // Lotlar 25 taşıyor ama 40 earned isteniyor (partial server verisi) → 25 döner, çökmez.
        let buckets = [EarnedCoinBucket(amount: 25, expiresAt: daysFromNow(4))]
        let lines = EarnedCoinExpiryPlanner.earnedSpendPreview(earnedAmount: 40, buckets: buckets, now: now)

        #expect(lines == [EarnedSpendLine(coins: 25, expiresAt: daysFromNow(4))])
    }

    @Test func earnedSpendPreviewSifirVeyaNegatifBos() {
        let buckets = [EarnedCoinBucket(amount: 25, expiresAt: daysFromNow(4))]
        #expect(EarnedCoinExpiryPlanner.earnedSpendPreview(earnedAmount: 0, buckets: buckets, now: now).isEmpty)
        #expect(EarnedCoinExpiryPlanner.earnedSpendPreview(earnedAmount: -5, buckets: buckets, now: now).isEmpty)
    }
}
