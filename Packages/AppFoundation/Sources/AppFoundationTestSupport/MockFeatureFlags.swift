import AppFoundation
import Foundation

/// Programlanabilir flag store'u: override edilmeyen anahtarlar kod içi varsayılana düşer.
public final class MockFeatureFlags: FeatureFlagReading, @unchecked Sendable {
    private let lock = NSLock()
    private var overrides: [String: FlagRawValue] = [:]
    private var reads: [String] = []

    public init() {}

    public func set<V: FlagValue>(_ value: V, for key: FlagKey<V>) {
        lock.withLock { overrides[key.name] = value.flagRawValue }
    }

    public func removeOverride(for key: FlagKey<some FlagValue>) {
        lock.withLock { overrides[key.name] = nil }
    }

    /// Okunan flag adları (spy).
    public var recordedReads: [String] {
        lock.withLock { reads }
    }

    public func value<V: FlagValue>(for key: FlagKey<V>) -> V {
        lock.withLock {
            reads.append(key.name)
            return overrides[key.name].flatMap(V.init(flagRawValue:)) ?? key.default
        }
    }
}
