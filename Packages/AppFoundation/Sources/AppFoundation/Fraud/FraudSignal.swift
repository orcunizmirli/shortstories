/// Anormal kazanç hızı **danışma sinyali** (SS-100, F2). İstemci-taraflı bir rate-limit İPUCU'dur:
/// kısa pencerede beklenenden hızlı coin kazanımı (çok claim/ödül) tespit edilirse `elevated` bayrağı
/// üretilir. İstemci BLOKLAMAZ — yalnız bayrağı işaretler; anormal kazanç KARARINI backend verir
/// (double-entry + audit trail sunucu tarafında — 09 R6). Ham sayaç/zaman damgası TAŞINMAZ (PII/
/// fingerprinting yok); yalnız kaba seviye header'a girer.
public struct EarnVelocitySignal: Sendable, Equatable {
    /// Kaba kazanç-hızı seviyesi (advisory). Wire değeri `rawValue`'dur ("normal"/"elevated").
    public enum Level: String, Sendable, Equatable, CaseIterable {
        /// Kazanç hızı istemci-taraflı eşiğin altında.
        case normal
        /// Kazanç hızı istemci-taraflı eşiği aştı — backend için danışma uyarısı.
        case elevated
    }

    public let level: Level

    public init(level: Level) {
        self.level = level
    }
}

/// Kazanç-hızı RAPOR portu (SS-100). Kazanç durumu WalletKit'in `WalletStore` actor'ında yaşar; bu
/// port o durumdan kaba bir danışma seviyesi türetir. AppFoundation feature paketlerini import ETMEZ:
/// port burada tanımlanır (tüketici), canlı uygulama WalletKit'te (üretici) yazılır ve kompozisyon
/// kökünde `FraudSignalInterceptor`'a ENJEKTE edilir (kalıp: `EntitlementChecking`). `nil` = sinyal
/// yok (yakın zamanda kazanç aktivitesi yok ya da henüz bağlanmadı) → velocity header eklenmez.
public protocol EarnVelocityReporting: Sendable {
    func currentEarnVelocity() async -> EarnVelocitySignal?
}

/// İstemci fraud danışma sinyallerinin birleşik değer tipi (SS-100). Cihaz bütünlüğü HER authed
/// istekte taşınır (tek seferlik prob, kompozisyonda değerlenir); kazanç-hızı yalnız sinyal varken
/// eklenir. Bu tip `FraudSignalHeaders` üreticisine girilir → wire header sözlüğü.
public struct FraudSignal: Sendable, Equatable {
    public let integrity: DeviceIntegritySignal
    public let earnVelocity: EarnVelocitySignal?

    public init(integrity: DeviceIntegritySignal, earnVelocity: EarnVelocitySignal? = nil) {
        self.integrity = integrity
        self.earnVelocity = earnVelocity
    }
}
