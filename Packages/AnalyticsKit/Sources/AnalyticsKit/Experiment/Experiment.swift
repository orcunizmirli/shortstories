import AppFoundation
import Foundation

/// A/B deney tanımı (docs/08 §7.1). Server-otoriter: tanım remote config'den yüklenir
/// (`ExperimentCatalog`), client sabit deney varsaymaz. Oturum ortasında değişmez
/// (immutable value tipi) — yeni config yalnız bir sonraki oturumda etkinleşir (§7.1).
public struct Experiment: Sendable, Equatable, Codable, Identifiable {
    /// Deney anahtarı; `ab_exposure.exp_key` ve `ab_variants` bileşeni.
    public let key: String
    /// Deneye özgü salt → deneyler arası atama korelasyonu yok (§7.2). Ramp'te değişmez.
    public let salt: String
    /// Yaşam döngüsü durumu (§7.4). Yalnız `.running` atama üretir.
    public let status: ExperimentStatus
    /// Deneye dahil edilen trafik payı, 0...10_000 baz puan (§7.2). Ramp yalnız bunu yükseltir.
    public let trafficBasisPoints: Int
    /// Varyantlar (control dahil), göreli ağırlıklarıyla.
    public let variants: [ExperimentVariant]

    public var id: String {
        key
    }

    public init(
        key: String,
        salt: String,
        status: ExperimentStatus,
        trafficBasisPoints: Int,
        variants: [ExperimentVariant]
    ) {
        self.key = key
        self.salt = salt
        self.status = status
        self.trafficBasisPoints = trafficBasisPoints
        self.variants = variants
    }

    /// Yalnız `.running` durumu canlı atama üretir (§7.2).
    public var isActive: Bool {
        status.isActive
    }

    /// Ağırlıklı atama için varyant ağırlıkları toplamı.
    public var totalWeight: Int {
        variants.reduce(0) { $0 + $1.weight }
    }

    /// Kimliğe göre varyant (server override / debug force için).
    public func variant(withID id: String) -> ExperimentVariant? {
        variants.first { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case key
        case salt
        case status
        case trafficBasisPoints = "traffic_basis_points"
        case variants
    }
}

/// Deney yaşam döngüsü durumu (docs/08 §7.4: draft → running → completed).
public enum ExperimentStatus: String, Sendable, Equatable, Codable {
    case draft
    case running
    case paused
    case completed

    /// Yalnız `.running` kullanıcıları deneye atar; diğer durumlar → varyantsız (kontrol).
    public var isActive: Bool {
        self == .running
    }
}

/// Bir deney varyantı: kimlik + göreli ağırlık + varyant payload'ı (config).
/// `id`, `ab_exposure.variant` alanına ve `ab_variants` ortak parametresine birebir yazılır.
public struct ExperimentVariant: Sendable, Equatable, Codable, Identifiable {
    /// Varyant kimliği (ör. "control", "v1"). Analitik boyutu olarak taşınır.
    public let id: String
    /// Ağırlıklı atamada göreli pay (>= 0). Eşit ağırlık = eşit dağılım.
    public let weight: Int
    /// Varyanta özgü config değerleri (ör. buton stili, serbest bölüm sayısı).
    /// Tipli okuma `value(for:)` ile `FlagValue` çözümlemesine köprülenir.
    public let payload: [String: ExperimentValue]

    public init(id: String, weight: Int = 1, payload: [String: ExperimentValue] = [:]) {
        self.id = id
        self.weight = weight
        self.payload = payload
    }

    /// Payload değerini tipli okur (`FlagValue` çözümlemesini yeniden kullanır: int→double
    /// esnekliği dahil). Anahtar yoksa / tip uymuyorsa `nil`.
    public func value<V: FlagValue>(for key: String) -> V? {
        payload[key].flatMap { V(flagRawValue: $0.flagRawValue) }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case weight
        case payload
    }

    /// `weight` ve `payload` remote config'de opsiyoneldir (varsayılan 1 / boş).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        weight = try container.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        payload = try container.decodeIfPresent([String: ExperimentValue].self, forKey: .payload) ?? [:]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(weight, forKey: .weight)
        if !payload.isEmpty {
            try container.encode(payload, forKey: .payload)
        }
    }
}

/// Varyant payload'ındaki JSON skaler değeri. Remote config'den Codable ile yüklenir;
/// `FlagRawValue`'ya köprülenerek mevcut tipli flag çözümlemesi yeniden kullanılır.
public enum ExperimentValue: Sendable, Equatable, Codable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)

    /// Mevcut `FlagValue` çözümleyicilerini kullanmak için `FlagRawValue` köprüsü.
    public var flagRawValue: FlagRawValue {
        switch self {
        case let .bool(value): .bool(value)
        case let .int(value): .int(value)
        case let .double(value): .double(value)
        case let .string(value): .string(value)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Sıra önemli: JSON bool'u Int/Double'a düşmeden yakala; tam sayı Double'dan önce.
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
                debugDescription: "Desteklenmeyen deney payload değeri (bool/int/double/string bekleniyor)."
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
