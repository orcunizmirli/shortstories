import Foundation
import Testing
@testable import WalletKit

/// Yaklaşan-vade uyarısının saf SUNUM türevi (SS-115 D1; 06 §2.5): görünürlük kararı, "N gün"
/// türetimi ve mesaj. `now` enjekte → deterministik. Vade SERVER-otoriter; bu tip bakiye/lot
/// HESAPLAMAZ, yalnız gösterim türetir (çok-lotlu lotlar → yoksa tekil banda geriye-uyum).
struct EarnedExpiryWarningTests {
    /// Sabit referans "şimdi" — 2026-07-12 00:00:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_752_278_400)

    private func daysFromNow(_ days: Double) -> Date {
        now.addingTimeInterval(days * 86400)
    }

    // MARK: - Görünürlük kararı

    @Test func lotVeBantYokIseNil() {
        #expect(EarnedExpiryWarning.resolve(buckets: [], notice: nil, now: now) == nil)
    }

    @Test func lotlardanEsikIciTuretilir() {
        let buckets = [
            EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(2)),
            EarnedCoinBucket(amount: 20, expiresAt: daysFromNow(5))
        ]
        let warning = EarnedExpiryWarning.resolve(buckets: buckets, notice: nil, now: now)

        #expect(warning?.coins == 50)
        #expect(warning?.daysRemaining == 2) // en erken lot belirler
    }

    @Test func esikDisiLotBantCizilmez() {
        let buckets = [EarnedCoinBucket(amount: 30, expiresAt: daysFromNow(10))]
        #expect(EarnedExpiryWarning.resolve(buckets: buckets, notice: nil, now: now) == nil)
    }

    // MARK: - Tekil bant geriye-uyum (lot yokken; 05 §2.5 WIRE TODO)

    @Test func lotYoksaTekilBandaDuser() {
        let notice = ExpiryNotice(amount: 15, expiresAt: daysFromNow(3))
        let warning = EarnedExpiryWarning.resolve(buckets: [], notice: notice, now: now)

        #expect(warning?.coins == 15)
        #expect(warning?.daysRemaining == 3)
    }

    @Test func tekilBantEsikDisiIseNil() {
        let notice = ExpiryNotice(amount: 15, expiresAt: daysFromNow(10))
        #expect(EarnedExpiryWarning.resolve(buckets: [], notice: notice, now: now) == nil)
    }

    @Test func tekilBantGecmisIseNil() {
        let notice = ExpiryNotice(amount: 15, expiresAt: daysFromNow(-1))
        #expect(EarnedExpiryWarning.resolve(buckets: [], notice: notice, now: now) == nil)
    }

    @Test func tekilBantSifirCoinIseNil() {
        let notice = ExpiryNotice(amount: 0, expiresAt: daysFromNow(3))
        #expect(EarnedExpiryWarning.resolve(buckets: [], notice: notice, now: now) == nil)
    }

    @Test func lotlarTekilBandaGoreOnceliklidir() {
        // Hem lot hem bant varsa çok-lotlu (otoriter) kaynak kazanır; bant yok sayılır.
        let buckets = [EarnedCoinBucket(amount: 40, expiresAt: daysFromNow(2))]
        let notice = ExpiryNotice(amount: 999, expiresAt: daysFromNow(1))
        let warning = EarnedExpiryWarning.resolve(buckets: buckets, notice: notice, now: now)

        #expect(warning?.coins == 40)
        #expect(warning?.daysRemaining == 2)
    }

    // MARK: - "N gün" türetimi (yukarı yuvarlama, min 1)

    @Test func gunYukariYuvarlanir() {
        // 3.4 gün → "4 gün içinde" (pencere semantiği: içinde yanacak).
        let buckets = [EarnedCoinBucket(amount: 10, expiresAt: daysFromNow(3.4))]
        #expect(EarnedExpiryWarning.resolve(buckets: buckets, notice: nil, now: now)?.daysRemaining == 4)
    }

    @Test func birGundenAzIseBirGun() {
        // 12 saat kaldı → "0 gün" değil "1 gün".
        let buckets = [EarnedCoinBucket(amount: 10, expiresAt: now.addingTimeInterval(12 * 3600))]
        #expect(EarnedExpiryWarning.resolve(buckets: buckets, notice: nil, now: now)?.daysRemaining == 1)
    }

    @Test func tamYediGunSinir() {
        let buckets = [EarnedCoinBucket(
            amount: 10,
            expiresAt: now.addingTimeInterval(EarnedCoinExpiryPlanner.defaultThreshold)
        )]
        #expect(EarnedExpiryWarning.resolve(buckets: buckets, notice: nil, now: now)?.daysRemaining == 7)
    }

    // MARK: - Mesaj türetimi (tek kaynak; View verbatim çizer)

    @Test func mesajGunVeCoinIcerir() {
        let warning = EarnedExpiryWarning(coins: 50, daysRemaining: 2)
        #expect(warning.message == "2 gün içinde 50 kazanılmış coin sona erecek")
    }
}
