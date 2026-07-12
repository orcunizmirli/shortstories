import Foundation

/// UserDefaults'ta saklanabilen tercih değeri tipleri.
public protocol PreferenceValue: Sendable, Equatable {}

extension Bool: PreferenceValue {}
extension Int: PreferenceValue {}
extension Double: PreferenceValue {}
extension String: PreferenceValue {}

/// Tipli tercih anahtarı; varsayılan değer koddadır.
public struct PreferenceKey<Value: PreferenceValue>: Sendable {
    public let name: String
    public let `default`: Value

    public init(name: String, default defaultValue: Value) {
        self.name = name
        self.default = defaultValue
    }
}

/// Kanonik tercih anahtarları (03 §9 UserDefaults satırı) — tohum set; feature'lar
/// kendi anahtarlarını kendi paketlerinde tanımlar.
public enum PreferenceKeys {
    public static let onboardingCompleted = PreferenceKey(name: "onboarding.completed", default: false)
    public static let autoplayEnabled = PreferenceKey(name: "playback.autoplay_enabled", default: true)
    public static let dataSaverEnabled = PreferenceKey(name: "playback.data_saver_enabled", default: false)
    public static let subtitleLanguageCode = PreferenceKey(name: "subtitles.language_code", default: "en")
}

/// Tip-güvenli UserDefaults erişimi (03 §9). Gizli/kişisel veri ve token BURAYA
/// YAZILMAZ — onlar `SecureStoring`'e gider.
public protocol PreferencesStoring: Sendable {
    func value<V: PreferenceValue>(for key: PreferenceKey<V>) -> V
    func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>)
    func removeValue<V: PreferenceValue>(for key: PreferenceKey<V>)
}

/// Canlı UserDefaults uygulaması.
/// UserDefaults thread-safe'tir (Apple dokümantasyonu) — @unchecked bu gerekçeyle güvenlidir.
public struct UserDefaultsPreferences: PreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value<V: PreferenceValue>(for key: PreferenceKey<V>) -> V {
        defaults.object(forKey: key.name) as? V ?? key.default
    }

    public func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) {
        defaults.set(value, forKey: key.name)
    }

    public func removeValue<V: PreferenceValue>(for key: PreferenceKey<V>) {
        defaults.removeObject(forKey: key.name)
    }
}
