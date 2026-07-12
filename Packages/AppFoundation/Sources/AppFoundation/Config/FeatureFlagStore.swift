import Foundation

/// Salt-okunur flag erişimi (03 §5.1, §11).
public protocol FeatureFlagReading: Sendable {
    func value<V: FlagValue>(for key: FlagKey<V>) -> V
}

/// UserDefaults snapshot tabanlı store (F0 dar kapsamı — plan §5).
/// Remote `GET /config` fetch'i SS-024'te gelir; F0 davranışı: UserDefaults'taki son
/// snapshot init'te BİR KEZ okunup dondurulur, yoksa kod içi varsayılanlar kullanılır.
/// Oturum ortasında flag değişimi UI'ı canlı DEĞİŞTİRMEZ (03 §11) — tip immutable'dır;
/// yeni snapshot ancak yeni launch'ta (yeni instance) etkili olur. Acil kill-switch
/// yeniden okuma istisnası SS-024 kapsamındadır.
public struct FeatureFlagStore: FeatureFlagReading {
    public static let snapshotDefaultsKey = "featureFlags.snapshot"

    private let snapshot: [String: FlagRawValue]

    public init(snapshot: [String: FlagRawValue]) {
        self.snapshot = snapshot
    }

    public init(userDefaults: UserDefaults = .standard) {
        let stored = userDefaults.dictionary(forKey: Self.snapshotDefaultsKey) ?? [:]
        self.snapshot = stored.compactMapValues(FlagRawValue.init(bridging:))
    }

    public func value<V: FlagValue>(for key: FlagKey<V>) -> V {
        snapshot[key.name].flatMap(V.init(flagRawValue:)) ?? key.default
    }

    /// Bir sonraki launch'ta okunacak snapshot'ı yazar — SS-024 remote fetch'in yazma
    /// yolu; F0'da test ve tohumlama için.
    public static func persistSnapshot(_ snapshot: [String: FlagRawValue],
                                       to userDefaults: UserDefaults = .standard) {
        userDefaults.set(snapshot.mapValues(\.propertyListObject),
                         forKey: snapshotDefaultsKey)
    }
}

extension FlagRawValue {
    /// UserDefaults'tan dönen `Any` değeri köprüler. NSNumber'ın bool/int/double ayrımı
    /// CFBoolean/CFNumber tip kontrolüyle yapılır (Swift'in NSNumber bridging'i gevşektir).
    init?(bridging object: Any) {
        if let number = object as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        } else if let string = object as? String {
            self = .string(string)
        } else {
            return nil
        }
    }

    var propertyListObject: Any {
        switch self {
        case .bool(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .string(let value): return value
        }
    }
}
