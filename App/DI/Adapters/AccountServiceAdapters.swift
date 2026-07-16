import AppFoundation
import Foundation
import ProfileKit

// ProfileKit hesap portlarının canlı adaptörleri (SS-132/133, R8). Portlar ProfileKit'te tanımlı
// (tüketici); App onları `APIClient` (+ Keychain token kalıcılığı) üzerine köprüler. Beklenen sonuçlar
// (linked/conflict) DEĞER olarak döner → sunucu HER İKİ durumda 200 verir (APIClient 409 gövdesini
// tipli okumadığından conflict bir hata değil, 200 gövdesindeki ayraçtır); yalnız GERÇEK hatalar throw
// eder (05 §4.2 sözleşmesi, port dokümanı).

// MARK: - Hesap bağlama (POST /auth/link, POST /auth/switch)

/// ProfileKit `AccountLinkingServicing` → `APIClient` + `SecureStoring`. Başarıda dönen access/refresh
/// token'ları Keychain'e yazar (`AuthInterceptor` anında bağlı hesabın token'ını kullanır; relaunch'ta
/// `SessionManager.restoreFromKeychain` `.linked` görür) ve `AccountSummary` döner.
///
/// SINIR: `SessionManager` şu an bağlı-duruma canlı geçiş için public hook sunmaz (yalnız guest
/// bootstrap + refresh-failure). Bu yüzden adaptör Keychain'i günceller ama BELLEK-İÇİ `session.state`'i
/// canlı yükseltemez — o geçiş `SessionManager`'a bir link-hook eklenince (ayrı AppFoundation dilimi)
/// tamamlanır. Delegate (`hesapBaglamaDidLink`) App coordinator'ını bilgilendirir.
struct APIAccountLinkingService: AccountLinkingServicing {
    /// F1'de yalnız Apple bağlanır (Google/e-posta F2) — `HesapBaglamaModel.provider` ile aynı karar;
    /// o sabit @MainActor-izole olduğundan nonisolated adaptörde yerel eşdeğer tutulur.
    static let linkedProvider: AuthProvider = .apple

    private let client: any APIClientProtocol
    private let secureStore: any SecureStoring

    init(client: any APIClientProtocol, secureStore: any SecureStoring) {
        self.client = client
        self.secureStore = secureStore
    }

    func link(_ credential: AppleCredential) async throws -> AccountLinkOutcome {
        let wire = try await client.send(AuthLinkEndpoint(credential: credential))
        return try applyOutcome(wire)
    }

    func switchToExistingAccount(_ conflict: AccountLinkConflict) async throws -> AccountSummary {
        let wire = try await client.send(AuthSwitchEndpoint(switchToken: conflict.switchToken))
        persistSession(wire.session)
        return AccountSummary(kind: .linked(provider: Self.linkedProvider))
    }

    private func applyOutcome(_ wire: AuthLinkWire) throws -> AccountLinkOutcome {
        switch wire.status {
        case .linked:
            guard let session = wire.session else { throw AppError.auth(.linkingFailed) }
            persistSession(session)
            return .linked(AccountSummary(kind: .linked(provider: Self.linkedProvider)))
        case .conflict:
            guard let conflict = wire.conflict else { throw AppError.auth(.linkingFailed) }
            return .conflict(
                AccountLinkConflict(
                    existingAccountMasked: conflict.existingAccountMasked,
                    switchToken: conflict.switchToken,
                    willDiscardGuestData: conflict.willDiscardGuestData
                )
            )
        }
    }

    /// Bağlı hesabın token + kimlik snapshot'ını Keychain'e yazar. Snapshot `StoredSessionSnapshot`
    /// ile ŞEMA-UYUMLUDUR (`userID`/`provider` anahtarları, düz `JSONEncoder`) → relaunch'ta
    /// `SessionManager` bunu `.linked` olarak geri yükler.
    private func persistSession(_ session: SessionCredentialsWire) {
        try? secureStore.setString(session.accessToken, forKey: .accessToken)
        try? secureStore.setString(session.refreshToken, forKey: .refreshToken)
        let snapshot = SessionSnapshotMirror(userID: session.userId, provider: Self.linkedProvider)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? secureStore.setData(data, forKey: .sessionSnapshot)
        }
    }
}

/// `POST /auth/link` (05 §4.2). Apple kimliğini misafir hesaba bağlar; `userId` korunur (sunucu merge).
private struct AuthLinkEndpoint: Endpoint {
    typealias Response = AuthLinkWire

    struct RequestBody: Encodable, Sendable {
        let identityToken: String
        let authorizationCode: String?
        let userIdentifier: String
        let email: String?
        let fullName: String?
    }

    let credential: AppleCredential

    var path: String {
        "/auth/link"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        RequestBody(
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            userIdentifier: credential.userIdentifier,
            email: credential.email,
            fullName: credential.fullName
        )
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

/// `POST /auth/switch` (05 §4.2) — 409 sonrası "mevcut hesabıma geç" (`switchToken`).
private struct AuthSwitchEndpoint: Endpoint {
    typealias Response = AuthSwitchWire

    struct RequestBody: Encodable, Sendable {
        let switchToken: String
    }

    let switchToken: String

    var path: String {
        "/auth/switch"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        RequestBody(switchToken: switchToken)
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

// MARK: - Hesap silme + veri indirme (POST /account/delete, POST /account/data-export)

/// ProfileKit `AccountDeletionServicing` → `APIClient`. Ağ-yalnız: silme sonrası oturum sıfırlama
/// App'tedir (model delegate'i). Backend geri-alma penceresi + abonelik uyarısı KURALINI döner.
struct APIAccountDeletionService: AccountDeletionServicing {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func requestDeletion() async throws -> AccountDeletionReceipt {
        let wire = try await client.send(AccountDeleteEndpoint())
        return AccountDeletionReceipt(
            undoDeadline: wire.undoDeadline,
            requiresStoreSubscriptionCancellation: wire.requiresStoreSubscriptionCancellation
        )
    }

    func requestDataDownload() async throws -> DataExportReceipt {
        let wire = try await client.send(DataExportEndpoint())
        return DataExportReceipt(deliveryEmailMasked: wire.deliveryEmailMasked)
    }
}

private struct AccountDeleteEndpoint: Endpoint {
    typealias Response = AccountDeleteWire

    var path: String {
        "/account/delete"
    }

    var method: HTTPMethod {
        .post
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

private struct DataExportEndpoint: Endpoint {
    typealias Response = DataExportWire

    var path: String {
        "/account/data-export"
    }

    var method: HTTPMethod {
        .post
    }

    var retryPolicy: RetryPolicy {
        .never
    }
}

// MARK: - Wire

/// `StoredSessionSnapshot` şema aynası (App-yerel): relaunch'ta `SessionManager`'ın düz `JSONDecoder`'ı
/// ile geri okunur (`userID`/`provider` anahtarları birebir).
private struct SessionSnapshotMirror: Encodable {
    let userID: String
    let provider: AuthProvider?
}

/// Bağlı hesap oturum kimlik-bilgileri (05 §4.2 link/switch yanıtı).
struct SessionCredentialsWire: Decodable, Sendable {
    let userId: String
    let accessToken: String
    let refreshToken: String
}

/// `POST /auth/link` 200 zarfı: `status` ayracıyla linked/conflict.
struct AuthLinkWire: Decodable, Sendable {
    enum Status: String, Decodable, Sendable {
        case linked
        case conflict
    }

    struct ConflictWire: Decodable, Sendable {
        let existingAccountMasked: String
        let switchToken: String
        let willDiscardGuestData: Bool
    }

    let status: Status
    let session: SessionCredentialsWire?
    let conflict: ConflictWire?
}

struct AuthSwitchWire: Decodable, Sendable {
    let session: SessionCredentialsWire
}

struct AccountDeleteWire: Decodable, Sendable {
    let undoDeadline: Date?
    let requiresStoreSubscriptionCancellation: Bool
}

struct DataExportWire: Decodable, Sendable {
    let deliveryEmailMasked: String?
}
