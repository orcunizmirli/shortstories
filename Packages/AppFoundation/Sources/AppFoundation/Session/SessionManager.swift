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
    /// Oturum-kimliği epoch'u (audit MEDIUM): her `linkSession` (bağlama/switch) bunu artırır. UÇUŞTAKİ
    /// misafir bootstrap yanıtı, await ÖNCESİ bu değeri yakalar; storeGuestSession/setState ÖNCESİ
    /// eşleşmezse araya bir link girmiştir → misafir yanıtı bayattır ve UYGULANMAZ (linked oturumu ezip
    /// hesabı sessizce misafire indirgemesin). MainActor serileştirdiği için yakalama+kontrol atomiktir.
    @ObservationIgnored private var sessionGeneration = 0

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
        // `try`: restore GEÇİCİ Keychain hatasını (keychainUnavailable — securityd glitch / ilk-kilit
        // öncesi) yok-oturum'dan AYIRIR ve FIRLATIR → misafir bootstrap'a DÜŞMEZ (aksi halde bağlı
        // oturumun token/snapshot'ı misafir tokenlarıyla EZİLİP hesap sessizce misafire iniyordu, audit
        // MEDIUM). Çağıran (soğuk açılış) sonra tekrar dener; yalnız GENUINE yokluk (nil) bootstrap'a gider.
        if let restored = try restoreFromKeychain() {
            setState(restored)
            return restored
        }
        return try await singleFlightGuestBootstrap()
    }

    /// Misafir bootstrap'ı TEK-UÇUŞLU yürütür (audit LOW): uçuştaki `bootstrapTask` varsa onu bekler,
    /// yoksa oluşturur. `handleRefreshFailure` de bunu kullanır (doğrudan `performGuestBootstrap` yerine)
    /// → eşzamanlı iki misafir kurulumu çift `POST /auth/guest` üretmez.
    private func singleFlightGuestBootstrap() async throws -> SessionState {
        if let bootstrapTask {
            return try await bootstrapTask.value
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
        // Uçuştaki misafir bootstrap yanıtını fence et: bu link, o yanıttan SONRA gelirse yanıt bu
        // linked token'ları ezmemeli (audit MEDIUM). MainActor senkron → yakalama+kontrol atomik.
        sessionGeneration &+= 1
        // Keychain yazımı best-effort: başarısızlığı bellek-içi yükseltmeyi ENGELLEMEZ (canlı durum yayını
        // asıl amaç). 3 anahtar (refresh/access/snapshot) ATOMİK yazılır (`setAtomically`): herhangi biri
        // koparsa TÜMÜ yedeklere geri alınır → torn-write YOK (audit MEDIUM: snapshot-torn "guest snapshot +
        // linked token" ayrışması engellenir; eskiden refresh-önce sıralaması yalnız token-torn'u kapatıyordu).
        do {
            let snapshot = StoredSessionSnapshot(userID: userID, provider: provider)
            try secureStore.setAtomically([
                (.refreshToken, Data(refreshToken.utf8)),
                (.accessToken, Data(accessToken.utf8)),
                (.sessionSnapshot, JSONEncoder().encode(snapshot))
            ])
        } catch {
            // Atomik yazım koptu → keychain yedeklere geri alındı (tutarlı eski hal; torn YOK). Bellek-içi
            // yükseltme yine yapılır (canlı oturum doğru; relaunch'ta re-auth ile kalıcılaşır).
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
            let generation = sessionGeneration // await ÖNCESİ yakala (audit MEDIUM)
            let endpoint = GuestAuthEndpoint(requestBody: GuestAuthEndpoint.RequestBody(
                deviceId: persistentDeviceID(),
                platform: clientInfo.platform,
                appVersion: clientInfo.appVersion,
                locale: clientInfo.locale
            ))
            let response = try await apiClient.send(endpoint)
            // Bootstrap uçuştayken bir link geldiyse (generation değişti) bu misafir yanıtı BAYATTIR →
            // storeGuestSession/setState ATLANIR (linked token'ları/snapshot'ı ezip hesabı sessizce
            // misafire indirgemesin). MainActor senkron → kontrol+erken-dönüş atomik.
            guard generation == sessionGeneration else {
                return state
            }
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

    private func restoreFromKeychain() throws -> SessionState? {
        guard let snapshot = try storedSnapshot() else {
            return nil
        }
        // `try`: geçici okuma hatası FIRLATILIR (bootstrap'a düşmez); yalnız GENUINE yokluk (nil → "")
        // aşağıdaki tokensız-snapshot yoluna gider.
        let accessToken = try secureStore.string(forKey: .accessToken) ?? ""
        let refreshToken = try secureStore.string(forKey: .refreshToken) ?? ""
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

    /// `try`: `data(...)` GEÇİCİ hatası (keychainUnavailable) FIRLATILIR (çağıran ayırt eder); yalnız
    /// GENUINE yokluk (`nil`) veya bozuk-decode `nil` döner. Bozuk snapshot decode'u yokluk sayılır
    /// (bilinçli — geçici hata DEĞİL).
    private func storedSnapshot() throws -> StoredSessionSnapshot? {
        guard let snapshotData = try secureStore.data(forKey: .sessionSnapshot) else {
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
        let linkedIdentity: (userID: String, provider: AuthProvider)?
        if case let .linked(userID, provider) = state {
            linkedIdentity = (userID, provider)
        } else {
            // State `.linked` değil → snapshot'tan linked kimliği belirle. `try` DEĞİL `try?` (audit MEDIUM,
            // self-review): GEÇİCİ okuma hatası (keychainUnavailable) linked/guest ayrımını imkansız kılar; `try?`
            // onu `nil`e çevirip YIKICI guest-fallback'e (token+snapshot SİLME, guest'e düşürme) sokuyordu →
            // linked kullanıcı SESSİZCE guest olur (05 §4.2 ihlali). Geçici hatada HİÇBİR ŞEY bozmadan nil dön
            // (sonraki 401 tekrar dener); yalnız GENUINE yokluk (nil/decode-fail) guest-fallback'e gider.
            do {
                if let snapshot = try storedSnapshot(), let provider = snapshot.provider {
                    linkedIdentity = (snapshot.userID, provider)
                } else {
                    linkedIdentity = nil
                }
            } catch {
                return nil
            }
        }

        clearStoredTokens()

        if let linkedIdentity {
            // Snapshot bilinçli SİLİNMEZ: tokensız bağlı snapshot, relaunch'ta
            // `restoreFromKeychain`in gördüğü kalıcı loggedOut kaydıdır (misafir kurulmaz).
            setState(.loggedOut(previousUserID: linkedIdentity.userID, provider: linkedIdentity.provider))
            return nil
        }
        try? secureStore.removeData(forKey: .sessionSnapshot)
        guard await (try? singleFlightGuestBootstrap()) != nil else {
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
        // Teslimat KİLİT İÇİNDE (audit MEDIUM): aksi halde `current` güncellemesi ile teslimat arasına
        // yeni bir `stream()` aboneliği girip, o abonenin ilk-snapshot'ı (kilit dışında yield'lenen) BU
        // yeni durumdan SONRA teslim olup bayat state'i son değer yapabiliyordu → oturum geçersizlemesi
        // geri alınırdı. AsyncStream.yield non-blocking (buffer'a enqueue) → kilit altında güvenli.
        lock.withLock {
            current = state
            for continuation in continuations.values {
                continuation.yield(state)
            }
        }
    }

    func stream() -> AsyncStream<SessionState> {
        AsyncStream { continuation in
            let id = UUID()
            // Kayıt + `current` okuma + ilk-snapshot teslimi ATOMİK (kilit içinde): araya bir `yield()`
            // giremez → abone hep tutarlı bir sırayla (mevcut durum, sonra sonraki yield'ler) alır.
            lock.withLock {
                continuations[id] = continuation
                continuation.yield(current)
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock { continuations[id] = nil }
    }
}
