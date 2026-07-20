import AppFoundation
import Foundation

/// Kazanç olaylarını (earned-coin kredisi) WalletKit'e RAPORLAYAN dar yazma portu (SS-100).
/// `WalletStore` earned-kese artışlarını buraya işler; monitör bunu pencere-içi hıza çevirir.
/// Ayrı protokol → `WalletStore` somut `EarningVelocityMonitor`'ı DEĞİL bu soyutlamayı tutar
/// (interface segregation + test için casus enjekte edilebilir). SENKRON: `WalletStore`'un aktör
/// içi senkron `applyWallet` yolundan Task açmadan çağrılır (sayaç kilitle korunur, aktör değil).
public protocol EarnVelocityRecording: Sendable {
    /// Bir kazanç olayını kaydeder. `coins` bu olayda kazanılan (pozitif) earned-coin miktarıdır;
    /// ≤ 0 yok sayılır (harcama/iade kazanç değildir). Zaman damgası monitörün enjekte saatinden.
    func recordEarn(coins: Int)
}

/// Anormal **kazanç hızı** izleyicisi (SS-100, F2; 07 §7.2 coin-farming / 09 R6). Kayan pencere
/// içinde kazanılan earned-coin toplamını izler; toplam eşiği aşarsa `EarnVelocitySignal.elevated`,
/// aşmazsa `.normal`, penceresinde hiç kazanç yoksa `nil` (sinyal yok → header eklenmez) döner.
///
/// **DANIŞMA / DEFANSİF:** İstemci BLOKLAMAZ ve karar VERMEZ — yalnız kaba bir rate-limit bayrağı
/// üretir; anormal-kazanç KARARINI backend kendi sunucu-taraflı muhasebesiyle (double-entry + audit)
/// verir (05 §1 kural 2; 09 R6). Bakiye MUTASYONA UĞRATILMAZ; sayaç/durum WalletKit-yereldir.
///
/// **Deterministik:** saat, pencere ve eşik ENJEKTE edilir → testler duvar-saatine dokunmadan normal/
/// anormal hızı, pencere kaymasını ve eşik sınırını kurar. `@unchecked Sendable` + `NSLock`: senkron
/// `recordEarn`/`currentEarnVelocity` (aktör değil) — `WalletStore`'un senkron `applyWallet` yolundan
/// Task-hop olmadan beslenir (kalıp: `ExperimentClient` kilitli okuma). Senkron `currentEarnVelocity`,
/// `EarnVelocityReporting`'in `async` gereksinimini karşılar (interceptor `await` eder).
///
/// **Header'a PII/ham sayaç GİTMEZ:** yalnız kaba `normal`/`elevated` seviye taşınır (bkz.
/// `FraudSignalHeaders`); zaman damgaları/miktarlar yalnız istemci-içi pencerede yaşar.
public final class EarningVelocityMonitor: EarnVelocityReporting, EarnVelocityRecording, @unchecked Sendable {
    /// Tek kazanç olayı: ne zaman + kaç earned-coin.
    private struct EarnEvent {
        let at: Date
        let coins: Int
    }

    /// Kayan pencerenin uzunluğu (saniye). Bu süreden daha eski olaylar hızdan düşer.
    private let window: TimeInterval
    /// Pencere içindeki kümülatif earned-coin ÜST SINIRI. Toplam bunu AŞARSA (`> threshold`)
    /// sinyal `elevated`; eşit/altı `normal`. Danışma tuning değeri — backend otoritatiftir.
    private let threshold: Int
    private let now: @Sendable () -> Date

    private let lock = NSLock()
    /// Pencere-içi kazanç olayları (kronolojik). Her yazma/okumada geçmiş budanır → sınırsız büyümez.
    private var events: [EarnEvent] = []

    /// - Parameters:
    ///   - window: kayan pencere (saniye). Varsayılan 300 sn (5 dk) — danışma tuning değeri.
    ///   - threshold: pencere-içi earned-coin üst sınırı; aşılırsa `elevated`. Varsayılan 500 —
    ///     danışma tuning değeri (backend kendi eşiğiyle otoriter kararı verir).
    ///   - now: enjekte saat (deterministik test); varsayılan `Date()`.
    public init(
        window: TimeInterval = 300,
        threshold: Int = 500,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.window = window
        self.threshold = threshold
        self.now = now
    }

    // MARK: - EarnVelocityRecording

    public func recordEarn(coins: Int) {
        guard coins > 0 else { return }
        let at = now()
        lock.withLock {
            events.append(EarnEvent(at: at, coins: coins))
            prune(reference: at)
        }
    }

    // MARK: - EarnVelocityReporting

    /// Pencere-içi kümülatif kazanç → danışma seviyesi. Hiç olay yoksa `nil` (header eklenmez).
    /// Senkron gövde `EarnVelocityReporting.currentEarnVelocity() async`'i karşılar.
    public func currentEarnVelocity() -> EarnVelocitySignal? {
        let reference = now()
        return lock.withLock {
            prune(reference: reference)
            guard !events.isEmpty else { return nil }
            let total = events.reduce(0) { $0 + $1.coins }
            return EarnVelocitySignal(level: total > threshold ? .elevated : .normal)
        }
    }

    // MARK: - İç

    /// `reference - window`'dan eski (dahil) olayları düşürür → kayan pencere. Sınır: tam `window`
    /// saniye önceki olay (at == cutoff) pencereden ÇIKAR (yarı-açık aralık `(cutoff, reference]`).
    /// Kilit ÇAĞIRAN tarafından tutulur.
    private func prune(reference: Date) {
        let cutoff = reference.addingTimeInterval(-window)
        events.removeAll { $0.at <= cutoff }
    }
}
