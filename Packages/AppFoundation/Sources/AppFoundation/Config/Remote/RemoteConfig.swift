import Foundation

/// `GET /config` yükünün istemci sözleşmesi (05 §4.10). Wire formatı camelCase'tir
/// (05 §1.7) ve property adları wire adlarıyla birebir eşleşir — bu yüzden ek
/// `CodingKeys` eşlemesi gerekmez. Model NEUTRAL'dır: `AnalyticsKit` import EDİLMEZ;
/// deney atamaları `RemoteExperimentAssignment` [key, variant] biçiminde taşınır ve
/// App katmanı bunları `ExperimentCatalog`'a köprüler.
///
/// Eksik alan toleransı (03 §11: "config gelmezse uygulama varsayılanla tam çalışır"):
/// her alan opsiyonel decode edilir; yoksa güvenli koddaki varsayılana düşer. Bu tip
/// hem wire'dan decode edilir hem de cache round-trip'i için encode edilir — gizli/PII
/// veri İÇERMEZ (product ID'leri, flag'ler, sürüm, deney atamaları), cache'e yazılması
/// güvenlidir.
public struct RemoteConfig: Sendable, Equatable, Codable {
    /// Zorunlu minimum istemci sürümü (05 §4.10; force-update kapısı). Yoksa "0.0.0"
    /// (hiçbir sürümü bloklamayan güvenli varsayılan).
    public let minSupportedVersion: String
    /// Coin ürün kimlikleri (StoreKit product ID'leri, sıralı).
    public let coinProducts: [String]
    /// VIP abonelik ürün kimlikleri.
    public let vipProducts: [String]
    /// Reklamla kilit açma günlük üst sınırı (05 §4.10; 5–10 aralığı, 03 §11).
    public let adUnlockDailyCap: Int
    /// Feature flag snapshot'ı ham değerleriyle. `FeatureFlagStore.persistSnapshot` ile
    /// bir sonraki launch için yazılır (freeze-per-launch, 03 §11).
    public let flags: [String: FlagRawValue]
    /// Server-otoriter deney atamaları (NEUTRAL [key, variant]). App katmanı
    /// `AnalyticsKit.ExperimentCatalog`'a köprüler.
    public let experiments: [RemoteExperimentAssignment]

    public init(
        minSupportedVersion: String = "0.0.0",
        coinProducts: [String] = [],
        vipProducts: [String] = [],
        adUnlockDailyCap: Int = 5,
        flags: [String: FlagRawValue] = [:],
        experiments: [RemoteExperimentAssignment] = []
    ) {
        self.minSupportedVersion = minSupportedVersion
        self.coinProducts = coinProducts
        self.vipProducts = vipProducts
        self.adUnlockDailyCap = adUnlockDailyCap
        self.flags = flags
        self.experiments = experiments
    }

    private enum CodingKeys: String, CodingKey {
        case minSupportedVersion
        case coinProducts
        case vipProducts
        case adUnlockDailyCap
        case flags
        case experiments
    }

    /// Eksik alanlar koddaki güvenli varsayılana düşer; bozuk (tipçe uyumsuz) alan
    /// gerçek bir decoding hatası olarak yüzer (çağıran graceful yakalar).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minSupportedVersion = try container.decodeIfPresent(String.self, forKey: .minSupportedVersion) ?? "0.0.0"
        coinProducts = try container.decodeIfPresent([String].self, forKey: .coinProducts) ?? []
        vipProducts = try container.decodeIfPresent([String].self, forKey: .vipProducts) ?? []
        adUnlockDailyCap = try container.decodeIfPresent(Int.self, forKey: .adUnlockDailyCap) ?? 5
        flags = try container.decodeIfPresent([String: FlagRawValue].self, forKey: .flags) ?? [:]
        experiments = try container.decodeIfPresent([RemoteExperimentAssignment].self, forKey: .experiments) ?? []
    }
}

/// Deney atamasının NEUTRAL istemci sözleşmesi (05 §4.10: `{ key, variant }`).
/// `AnalyticsKit`'ten bağımsızdır — AppFoundation deney istemcisini import etmez;
/// App katmanı bu atamaları deney kataloğuna köprüler (docs/08 §7.1).
public struct RemoteExperimentAssignment: Sendable, Equatable, Codable {
    /// Deney anahtarı (ör. "paywall_layout"). `ab_exposure.exp_key` bileşeni.
    public let key: String
    /// Atanan varyant kimliği (ör. "B"). `ab_exposure.variant` bileşeni.
    public let variant: String

    public init(key: String, variant: String) {
        self.key = key
        self.variant = variant
    }
}

/// `FlagRawValue`'nun wire/cache Codable köprüsü. Heterojen JSON skalerleri (bool/int/
/// double/string) tek-değer container ile çözülür; sıra ÖNEMLİDİR — JSON `false` Int'e
/// düşmeden bool olarak, tam sayı Double'dan önce yakalanır (`ExperimentValue` ile aynı
/// kalıp, AnalyticsKit). Cache round-trip'i için encode de aynı skaleri geri yazar.
extension FlagRawValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Desteklenmeyen flag değeri (bool/int/double/string bekleniyor)."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .bool(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .double(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }
}
