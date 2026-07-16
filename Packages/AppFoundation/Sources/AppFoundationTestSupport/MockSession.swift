import AppFoundation
import Foundation

public final class MockSession: SessionManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var currentState: SessionState
    private var continuations: [AsyncStream<SessionState>.Continuation] = []
    private var bootstrapCalls = 0
    private var stubbedBootstrapError: AppError?

    public init(state: SessionState = .guest(userID: "mock-guest")) {
        currentState = state
    }

    // MARK: - Stub / spy

    public var bootstrapCallCount: Int {
        lock.withLock { bootstrapCalls }
    }

    public func setBootstrapError(_ error: AppError?) {
        lock.withLock { stubbedBootstrapError = error }
    }

    /// Testten durum değiştirir ve tüm `stateUpdates` abonelerine yayınlar.
    public func send(_ newState: SessionState) {
        let subscribers = lock.withLock {
            currentState = newState
            return continuations
        }
        for continuation in subscribers {
            continuation.yield(newState)
        }
    }

    // MARK: - SessionManaging

    public var state: SessionState {
        get async { lock.withLock { currentState } }
    }

    public var stateUpdates: AsyncStream<SessionState> {
        AsyncStream { continuation in
            let current = lock.withLock {
                continuations.append(continuation)
                return currentState
            }
            continuation.yield(current)
        }
    }

    @discardableResult
    public func bootstrapGuestSessionIfNeeded() async throws -> SessionState {
        let (error, state) = lock.withLock {
            bootstrapCalls += 1
            return (stubbedBootstrapError, currentState)
        }
        if let error {
            throw error
        }
        return state
    }

    /// Canlı `SessionManager` ile aynı sözleşme: durumu `.linked`e yükseltir ve abonelere yayar.
    /// Tekrar-idempotent (durum zaten hedefse yayın yapılmaz); token'lar mock'ta yok sayılır.
    public func linkSession(
        userID: String,
        provider: AuthProvider,
        accessToken _: String,
        refreshToken _: String
    ) {
        let newState = SessionState.linked(userID: userID, provider: provider)
        let subscribers: [AsyncStream<SessionState>.Continuation]? = lock.withLock {
            guard currentState != newState else { return nil }
            currentState = newState
            return continuations
        }
        guard let subscribers else { return }
        for continuation in subscribers {
            continuation.yield(newState)
        }
    }
}
