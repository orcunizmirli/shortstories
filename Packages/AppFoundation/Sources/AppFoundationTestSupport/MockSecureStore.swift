import Foundation
import AppFoundation

public final class MockSecureStore: SecureStoring, @unchecked Sendable {
    public enum Operation: Sendable, Equatable {
        case read(SecureStoreKey)
        case write(SecureStoreKey)
        case remove(SecureStoreKey)
    }

    private let lock = NSLock()
    private var storage: [SecureStoreKey: Data] = [:]
    private var operations: [Operation] = []
    private var stubbedError: AppError?

    public init() {}

    // MARK: - Stub / spy

    public var recordedOperations: [Operation] {
        lock.withLock { operations }
    }

    /// Ayarlandığında tüm çağrılar bu hatayı fırlatır
    /// (ör. `AppError.storage(.keychainUnavailable)`).
    public func setError(_ error: AppError?) {
        lock.withLock { stubbedError = error }
    }

    // MARK: - SecureStoring

    public func data(forKey key: SecureStoreKey) throws -> Data? {
        try lock.withLock {
            operations.append(.read(key))
            if let stubbedError { throw stubbedError }
            return storage[key]
        }
    }

    public func setData(_ data: Data, forKey key: SecureStoreKey) throws {
        try lock.withLock {
            operations.append(.write(key))
            if let stubbedError { throw stubbedError }
            storage[key] = data
        }
    }

    public func removeData(forKey key: SecureStoreKey) throws {
        try lock.withLock {
            operations.append(.remove(key))
            if let stubbedError { throw stubbedError }
            storage[key] = nil
        }
    }
}
