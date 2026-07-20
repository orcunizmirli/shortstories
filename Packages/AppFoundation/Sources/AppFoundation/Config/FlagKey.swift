/// Flag snapshot'ında taşınabilen ham değer; remote config JSON'ı ile UserDefaults
/// arasındaki köprü tipi.
public enum FlagRawValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
}

/// `FlagKey<Value>`'nin değer tipleri. String anahtar erişimi YASAKTIR (03 §11) —
/// her flag tipli `FlagKey` sabitiyle tanımlanır.
public protocol FlagValue: Sendable, Equatable {
    init?(flagRawValue: FlagRawValue)
    var flagRawValue: FlagRawValue { get }
}

extension Bool: FlagValue {
    public init?(flagRawValue: FlagRawValue) {
        guard case let .bool(value) = flagRawValue else { return nil }
        self = value
    }

    public var flagRawValue: FlagRawValue {
        .bool(self)
    }
}

extension Int: FlagValue {
    public init?(flagRawValue: FlagRawValue) {
        guard case let .int(value) = flagRawValue else { return nil }
        self = value
    }

    public var flagRawValue: FlagRawValue {
        .int(self)
    }
}

extension Double: FlagValue {
    public init?(flagRawValue: FlagRawValue) {
        switch flagRawValue {
        case let .double(value): self = value
        case let .int(value): self = Double(value) // config 2.0 yerine 2 gönderebilir
        default: return nil
        }
    }

    public var flagRawValue: FlagRawValue {
        .double(self)
    }
}

extension String: FlagValue {
    public init?(flagRawValue: FlagRawValue) {
        guard case let .string(value) = flagRawValue else { return nil }
        self = value
    }

    public var flagRawValue: FlagRawValue {
        .string(self)
    }
}

/// Tipli flag anahtarı (03 §11). Varsayılan değer KODDADIR — config gelmezse uygulama
/// varsayılanla tam çalışır (ilk açılış / offline senaryosu).
public struct FlagKey<Value: FlagValue>: Sendable {
    public let name: String
    public let `default`: Value

    public init(name: String, default defaultValue: Value) {
        self.name = name
        self.default = defaultValue
    }
}

/// Kanonik flag sabitleri (03 §11). Yaşam döngüsü: her flag bir sahip + son temizlik
/// tarihiyle FlagRegistry.md'ye kaydedilir; ölü flag üç release içinde silinir.
public enum Flags {
    /// UnlockSheet "reklam izle" satırının ana şalteri (06 §6.2 `ads.rewarded_enabled`). F1'de KAPALI
    /// (yapı var, gizli); F2 SS-114 (AdMob köprüsü) açar. Günlük cap'ten (`rewardedDailyCap`) BAĞIMSIZ
    /// üst şalter; kapalıyken reklam satırı hiç render edilmez (istemci sürümü beklemeden server degrade).
    public static let rewardedAdsEnabled = FlagKey(name: "ads.rewarded_enabled", default: false)
    public static let rewardedDailyCap = FlagKey(name: "rewards.daily_ad_cap", default: 5)
    public static let dataSaverMaxHeight = FlagKey(name: "player.data_saver_max_height", default: 480)
}
