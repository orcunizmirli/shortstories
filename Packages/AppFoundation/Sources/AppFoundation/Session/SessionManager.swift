import Foundation
import Observation

/// Misafir bootstrap istek gövdesinin cihaz/uygulama bağlamı (05 §4.2).
public struct SessionClientInfo: Sendable {
    public let platform: String
    public let appVersion: String
    public let locale: String

    public init(platform: String = "ios", appVersion: String, locale: String) {
        self.platform = platform
        self.appVersion = appVersion
        self.locale = locale
    }

    public static func current() -> SessionClientInfo {
        SessionClientInfo(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            locale: Locale.current.identifier(.bcp47)
        )
    }
}

/// Keychain'de saklanan oturum kimliği (`SecureStoreKey.sessionSnapshot`).
/// `provider == nil` → misafir; dolu → bağlı hesap.
struct StoredSessionSnapshot: Codable, Sendable, Equatable {
    let userID: String
    let provider: AuthProvider?
}

/// Canlı oturum yöneticisi (03 §6.2 sahiplik; 05 §4.2 sözleşmesi): ilk açılışta Keychain'de
/// oturum varsa devam eder, yoksa `POST /auth/guest` ile anonim misafir hesabı kurar.
/// Access+refresh token ve kimlik snapshot'ı Keychain'dedir.
@Observable @MainActor
public final class SessionManager: SessionManaging {
    public private(set) var state: SessionState = .unauthenticated

    @ObservationIgnored private let apiClient: any APIClientProtocol
    @ObservationIgnored private let secureStore: any SecureStoring
    @ObservationIgnored private let clientInfo: SessionClientInfo
    @ObservationIgnored private let broadcaster = SessionStateBroadcaster(initial: .unauthenticated)
    @ObservationIgnored private var bootstrapTask: Task<SessionState, Error>?

    public init(
        apiClient: any APIClientProtocol,
        secureStore: any SecureStoring,
        clientInfo: SessionClientInfo = .current()
    ) {
        self.apiClient = apiClient
        self.secureStore = secureStore
        self.clientInfo = clientInfo
    }

    public nonisolated var stateUpdates: AsyncStream<SessionState> {
        broadcaster.stream()
    }

    @discardableResult
    public func bootstrapGuestSessionIfNeeded() async throws -> SessionState {
        if state.isAuthenticated {
            return state
        }
        // Bağlı hesapta oturum düştüyse misafire DÖNÜLMEZ (05 §4.2): loggedOut kalıcıdır,
        // yeniden giriş Profil üzerinden yürür (F2).
        if case .loggedOut = state {
            return state
        }
        if let bootstrapTask {
            return try await bootstrapTask.value
        }
        if let restored = restoreFromKeychain() {
            setState(restored)
            return restored
        }
        let task = Task { try await performGuestBootstrap() }
        bootstrapTask = task
        defer { bootstrapTask = nil }
        return try await task.value
    }

    // MARK: - Canlı bağlama yükseltmesi (05 §4.2)

    /// `POST /auth/link`/`switch` başarısında ProfileKit adaptörü çağırır: bellek-içi durumu
    /// `.linked`e yükseltir ve YAYAR (`ProfilModel.observeSession` anında görür; relaunch
    /// gerekmez), rotasyonlu token + kimlik snapshot'ını Keychain'e yazar. `userId` sunucu-otoriter
    /// korunur — client bakiye/entitlement gibi hiçbir varlığı kaybetmez. Tekrar-idempotent.
    public func linkSession(
        userID: String,
        provider: AuthProvider,
        accessToken: String,
        refreshToken: String
    ) {
        // Keychain yazımı best-effort: başarısızlığı bellek-içi yükseltmeyi ENGELLEMEZ (canlı
        // durum yayını asıl amaçtır; snapshot yalnız relaunch tutarlılığı içindir). Snapshot,
        // `StoredSessionSnapshot` şemasıyla `restoreFromKeychain`in `.linked` gördüğü kayıttır.
        try? secureStore.setString(accessToken, forKey: .accessToken)
        try? secureStore.setString(refreshToken, forKey: .refreshToken)
        let snapshot = StoredSessionSnapshot(userID: userID, provider: provider)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? secureStore.setData(data, forKey: .sessionSnapshot)
        }
        // Tekrar-idempotent: durum zaten hedefse gereksiz yayın YAPILMAZ (abonelere kopya .linked
        // gönderilmez).
        let newState = SessionState.linked(userID: userID, provider: provider)
        guard state != newState else {
            return
        }
        setState(newState)
    }

    // MARK: - Bootstrap

    private func performGuestBootstrap() async throws -> SessionState {
        do {
            let endpoint = GuestAuthEndpoint(requestBody: GuestAuthEndpoint.RequestBody(
                deviceId: persistentDeviceID(),
                platform: clientInfo.platform,
                appVersion: clientInfo.appVersion,
                locale: clientInfo.locale
            ))
            let response = try await apiClient.send(endpoint)
            try storeGuestSession(response)
            let newState = SessionState.guest(userID: response.userId)
            setState(newState)
            return newState
        } catch is CancellationError {
            // İptal bir hata DEĞİLDİR: guestBootstrapFailed'e dönüştürülmeden yüzer.
            throw CancellationError()
        } catch {
            throw AppError.auth(.guestBootstrapFailed)
        }
    }

    private func persistentDeviceID() -> String {
        if let existing = try? secureStore.string(forKey: .deviceID), !existing.isEmpty {
            return existing
        }
        let newID = UUID().uuidString
        try? secureStore.setString(newID, forKey: .deviceID)
        return newID
    }

    private func storeGuestSession(_ response: GuestAuthResponse) throws {
        try secureStore.setString(response.accessToken, forKey: .accessToken)
        try secureStore.setString(response.refreshToken, forKey: .refreshToken)
        let snapshot = StoredSessionSnapshot(userID: response.userId, provider: nil)
        try secureStore.setData(JSONEncoder().encode(snapshot), forKey: .sessionSnapshot)
    }

    // MARK: - Keychain'den devam

    private func restoreFromKeychain() -> SessionState? {
        guard let snapshot = storedSnapshot() else {
            return nil
        }
        let accessToken = (try? secureStore.string(forKey: .accessToken)) ?? ""
        let refreshToken = (try? secureStore.string(forKey: .refreshToken)) ?? ""
        guard !accessToken.isEmpty, !refreshToken.isEmpty else {
            // Tokensız bağlı snapshot = kalıcı loggedOut kaydı (05 §4.2: misafire dönülmez;
            // `handleRefreshFailure` tokenları siler, snapshot'ı bilinçli korur). Tokensız
            // misafir snapshot'ı ise sessizce yeniden bootstrap ile kurtarılır.
            if let provider = snapshot.provider {
                return .loggedOut(previousUserID: snapshot.userID, provider: provider)
            }
            return nil
        }
        if let provider = snapshot.provider {
            return .linked(userID: snapshot.userID, provider: provider)
        }
        return .guest(userID: snapshot.userID)
    }

    private func storedSnapshot() -> StoredSessionSnapshot? {
        guard let snapshotData = try? secureStore.data(forKey: .sessionSnapshot) else {
            return nil
        }
        return try? JSONDecoder().decode(StoredSessionSnapshot.self, from: snapshotData)
    }

    private func setState(_ newState: SessionState) {
        state = newState
        broadcaster.yield(newState)
    }
}

// MARK: - Refresh zinciri koptuğunda (05 §4.2)

extension SessionManager: RefreshFailureHandling {
    /// Misafir (veya hiç oturum yok): tokenlar temizlenir, sessizce `POST /auth/guest` ile
    /// yeniden kurulur ve yeni access token döner — `deviceId` korunduğu için sunucu aynı
    /// misafir hesabını döndürebilir. Bağlı hesap: `.loggedOut`a geçilir, `nil` döner (F2).
    public func handleRefreshFailure() async -> String? {
        let linkedIdentity: (userID: String, provider: AuthProvider)? = {
            if case let .linked(userID, provider) = state {
                return (userID, provider)
            }
            if let snapshot = storedSnapshot(), let provider = snapshot.provider {
                return (snapshot.userID, provider)
            }
            return nil
        }()

        clearStoredTokens()

        if let linkedIdentity {
            // Snapshot bilinçli SİLİNMEZ: tokensız bağlı snapshot, relaunch'ta
            // `restoreFromKeychain`in gördüğü kalıcı loggedOut kaydıdır (misafir kurulmaz).
            setState(.loggedOut(previousUserID: linkedIdentity.userID, provider: linkedIdentity.provider))
            return nil
        }
        try? secureStore.removeData(forKey: .sessionSnapshot)
        guard await (try? performGuestBootstrap()) != nil else {
            return nil
        }
        return try? secureStore.string(forKey: .accessToken)
    }

    /// Token kayıtlarını siler; `deviceID` bilinçli KORUNUR (reinstall'da devam kanonu).
    private func clearStoredTokens() {
        try? secureStore.removeData(forKey: .accessToken)
        try? secureStore.removeData(forKey: .refreshToken)
    }
}

// MARK: - Durum yayını

/// `stateUpdates` aboneliklerini `@MainActor` dışından da kurulabilir kılan yayın merkezi;
/// abone olunduğunda mevcut durumu yayınlayarak başlar (SessionManaging sözleşmesi).
final class SessionStateBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var current: SessionState
    private var continuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    init(initial: SessionState) {
        current = initial
    }

    func yield(_ state: SessionState) {
        let subscribers = lock.withLock {
            current = state
            return Array(continuations.values)
        }
        for continuation in subscribers {
            continuation.yield(state)
        }
    }

    func stream() -> AsyncStream<SessionState> {
        AsyncStream { continuation in
            let id = UUID()
            let currentState = lock.withLock {
                continuations[id] = continuation
                return current
            }
            continuation.yield(currentState)
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock { continuations[id] = nil }
    }
}
