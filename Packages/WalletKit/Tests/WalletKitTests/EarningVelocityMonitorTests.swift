import AppFoundation
import Foundation
import Testing
@testable import WalletKit

/// SS-100: `EarningVelocityMonitor` saf birim testleri — enjekte saat/pencere/eşik ile normal vs
/// anormal hız, pencere kayması ve eşik sınırı deterministik doğrulanır (duvar-saati YOK). Monitör
/// yalnız danışma bayrağı üretir; bakiye mutasyonu / backend kararı içermez.
struct EarningVelocityMonitorTests {
    /// Testin ilerlettiği enjekte saat (kilitli — @Sendable closure'dan güvenli okunur/yazılır).
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Date
        init(_ start: Date) {
            value = start
        }

        var now: @Sendable () -> Date {
            { self.lock.withLock { self.value } }
        }

        func advance(_ seconds: TimeInterval) {
            lock.withLock { value = value.addingTimeInterval(seconds) }
        }

        func set(_ date: Date) {
            lock.withLock { value = date }
        }
    }

    private let start = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - Sinyal yokluğu

    @Test func penceresindeKazancYoksaNilDoner() {
        let monitor = EarningVelocityMonitor(window: 60, threshold: 100, now: { Date(timeIntervalSince1970: 1_000_000) })
        // Hiç recordEarn çağrılmadı → sinyal yok → header eklenmez.
        #expect(monitor.currentEarnVelocity() == nil)
    }

    @Test func penceredenKaymisTekOlaySinyaliSifirlar() {
        let clock = Clock(start)
        let monitor = EarningVelocityMonitor(window: 60, threshold: 100, now: clock.now)
        monitor.recordEarn(coins: 50)
        // Pencere içindeyken sinyal var (normal).
        #expect(monitor.currentEarnVelocity() == EarnVelocitySignal(level: .normal))
        // Tam `window` saniye sonra olay pencereden ÇIKAR (at == cutoff dışarıda) → nil.
        clock.advance(60)
        #expect(monitor.currentEarnVelocity() == nil)
    }

    // MARK: - Normal vs anormal hız

    @Test func esikAltiKumulatifKazancNormal() {
        let clock = Clock(start)
        let monitor = EarningVelocityMonitor(window: 300, threshold: 500, now: clock.now)
        monitor.recordEarn(coins: 100)
        clock.advance(30)
        monitor.recordEarn(coins: 200) // toplam 300 ≤ 500
        #expect(monitor.currentEarnVelocity() == EarnVelocitySignal(level: .normal))
    }

    @Test func esikUstuKumulatifKazancElevated() {
        let clock = Clock(start)
        let monitor = EarningVelocityMonitor(window: 300, threshold: 500, now: clock.now)
        monitor.recordEarn(coins: 300)
        clock.advance(10)
        monitor.recordEarn(coins: 250) // toplam 550 > 500
        #expect(monitor.currentEarnVelocity() == EarnVelocitySignal(level: .elevated))
    }

    // MARK: - Eşik sınırı (boundary)

    @Test func tamEsikNormalEsikArtiBirElevated() {
        let clock = Clock(start)
        // Eşiğe TAM eşit → normal (`> threshold` değil).
        let atThreshold = EarningVelocityMonitor(window: 300, threshold: 100, now: clock.now)
        atThreshold.recordEarn(coins: 100)
        #expect(atThreshold.currentEarnVelocity() == EarnVelocitySignal(level: .normal))

        // Eşik + 1 → elevated.
        let overThreshold = EarningVelocityMonitor(window: 300, threshold: 100, now: clock.now)
        overThreshold.recordEarn(coins: 101)
        #expect(overThreshold.currentEarnVelocity() == EarnVelocitySignal(level: .elevated))
    }

    // MARK: - Pencere kayması (sliding window) kümülatif düşüş

    @Test func penceredenKayanOlaylarToplamdanDuser() {
        let clock = Clock(start)
        let monitor = EarningVelocityMonitor(window: 100, threshold: 500, now: clock.now)
        monitor.recordEarn(coins: 400) // t=0
        clock.advance(50)
        monitor.recordEarn(coins: 400) // t=50; pencere içi toplam 800 > 500 → elevated
        #expect(monitor.currentEarnVelocity() == EarnVelocitySignal(level: .elevated))

        // t=120: ilk olay (t=0) pencereden çıktı (cutoff=20, 0 ≤ 20); yalnız t=50 kaldı (400 ≤ 500).
        clock.advance(70)
        #expect(monitor.currentEarnVelocity() == EarnVelocitySignal(level: .normal))

        // t=160: t=50 olayı da çıktı (cutoff=60) → sinyal yok.
        clock.advance(40)
        #expect(monitor.currentEarnVelocity() == nil)
    }

    // MARK: - Girdi hijyeni

    @Test func sifirVeNegatifKazancYokSayilir() {
        let monitor = EarningVelocityMonitor(window: 60, threshold: 100, now: { Date(timeIntervalSince1970: 1_000_000) })
        monitor.recordEarn(coins: 0)
        monitor.recordEarn(coins: -50) // harcama/iade kazanç değildir
        #expect(monitor.currentEarnVelocity() == nil)
    }

    // MARK: - EarnVelocityReporting sözleşmesi (interceptor `await` yolu)

    @Test func reportingPortuAsyncOlarakTuketilebilir() async {
        let reporter: any EarnVelocityReporting = EarningVelocityMonitor(
            window: 60,
            threshold: 100,
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        // Sinyal yokken port nil döner (senkron gövde async gereksinimi karşılar).
        let signal = await reporter.currentEarnVelocity()
        #expect(signal == nil)
    }
}
