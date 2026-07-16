import Foundation

/// `#Preview` ve F0 stub kompozisyonu için in-memory, no-op bağımlılık seti (03 §5.2).
/// `EnvironmentValues.dependencies`'in varsayılanıdır. Bu dosyadaki no-op/in-memory
/// uygulamalar App target'ın F0 `LiveDependencies` kompozisyonunda da (canlı impl'ler
/// gelene dek — SS-021, SS-024, F1) kullanılabilir.
public struct PreviewDependencies: Dependencies {
    public let apiClient: any APIClientProtocol
    public let session: any SessionManaging
    public let featureFlags: any FeatureFlagReading
    public let logger: any Logging
    public let analytics: any AnalyticsTracking
    public let secureStore: any SecureStoring
    public let preferences: any PreferencesStoring

    public init(
        apiClient: any APIClientProtocol = UnimplementedAPIClient(),
        session: any SessionManaging = StubSessionManager(),
        featureFlags: any FeatureFlagReading = FeatureFlagStore(snapshot: [:]),
        logger: any Logging = NoopLogger(),
        analytics: any AnalyticsTracking = NoopAnalyticsTracker(),
        secureStore: any SecureStoring = InMemorySecureStore(),
        preferences: any PreferencesStoring = InMemoryPreferences()
    ) {
        self.apiClient = apiClient
        self.session = session
        self.featureFlags = featureFlags
        self.logger = logger
        self.analytics = analytics
        self.secureStore = secureStore
        self.preferences = preferences
    }
}

// MARK: - No-op / in-memory uygulamalar

/// Her isteği `AppError.network(.offline)` ile düşüren istemci — preview'lar ağ görmez.
public struct UnimplementedAPIClient: APIClientProtocol {
    public init() {}

    public func send<E: Endpoint>(_ endpoint: E) async throws -> E.Response {
        throw AppError.network(.offline)
    }
}

public struct NoopLogger: Logging {
    public init() {}

    public func log(_ level: LogLevel, _ message: String) {}
}

public struct NoopAnalyticsTracker: AnalyticsTracking {
    public init() {}

    public func track(_ name: String, parameters: [String: AnalyticsValue]) {}
}

/// Sabit durumlu oturum stub'ı; canlı uygulama `SessionManager`'dır.
public final class StubSessionManager: SessionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentState: SessionState

    public init(state: SessionState = .guest(userID: "preview-guest")) {
        currentState = state
    }

    public var state: SessionState {
        get async { lock.withLock { currentState } }
    }

    public var stateUpdates: AsyncStream<SessionState> {
        let current = lock.withLock { currentState }
        return AsyncStream { continuation in
            continuation.yield(current)
            continuation.finish()
        }
    }

    @discardableResult
    public func bootstrapGuestSessionIfNeeded() async throws -> SessionState {
        lock.withLock { currentState }
    }

    public func linkSession(
        userID: String,
        provider: AuthProvider,
        accessToken _: String,
        refreshToken _: String
    ) {
        lock.withLock { currentState = .linked(userID: userID, provider: provider) }
    }
}

/// In-memory Keychain stub'ı; canlı uygulama `KeychainSecureStore`'dur.
public final class InMemorySecureStore: SecureStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [SecureStoreKey: Data] = [:]

    public init() {}

    public func data(forKey key: SecureStoreKey) throws -> Data? {
        lock.withLock { storage[key] }
    }

    public func setData(_ data: Data, forKey key: SecureStoreKey) throws {
        lock.withLock { storage[key] = data }
    }

    public func removeData(forKey key: SecureStoreKey) throws {
        lock.withLock { storage[key] = nil }
    }
}

public final class InMemoryPreferences: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: any PreferenceValue] = [:]

    public init() {}

    public func value<V: PreferenceValue>(for key: PreferenceKey<V>) -> V {
        lock.withLock { storage[key.name] as? V ?? key.default }
    }

    public func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) {
        lock.withLock { storage[key.name] = value }
    }

    public func removeValue(for key: PreferenceKey<some PreferenceValue>) {
        lock.withLock { storage[key.name] = nil }
    }
}
