import AppFoundation
import Foundation

public final class MockPreferences: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: any PreferenceValue] = [:]
    private var setKeys: [String] = []

    public init() {}

    /// `set` çağrılarının anahtar sırası (spy).
    public var recordedSetKeys: [String] {
        lock.withLock { setKeys }
    }

    public func value<V: PreferenceValue>(for key: PreferenceKey<V>) -> V {
        lock.withLock { storage[key.name] as? V ?? key.default }
    }

    public func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) {
        lock.withLock {
            storage[key.name] = value
            setKeys.append(key.name)
        }
    }

    public func removeValue(for key: PreferenceKey<some PreferenceValue>) {
        lock.withLock { storage[key.name] = nil }
    }
}
