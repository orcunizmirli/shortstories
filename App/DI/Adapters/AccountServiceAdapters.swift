import AppFoundation
import Foundation
import ProfileKit

// ProfileKit hesap portlarının canlı adaptörleri (SS-132/133, R8). Portlar ProfileKit'te tanımlı
// (tüketici); App onları `APIClient` (+ Keychain token kalıcılığı) üzerine köprüler. Beklenen sonuçlar
// (linked/conflict) DEĞER olarak döner → sunucu HER İKİ durumda 200 verir (APIClient 409 gövdesini
// tipli okumadığından conflict bir hata değil, 200 gövdesindeki ayraçtır); yalnız GERÇEK hatalar throw
// eder (05 §4.2 sözleşmesi, port dokümanı).

// MARK: - Hesap bağlama (POST /auth/link, POST /auth/switch)

/// ProfileKit `AccountLinkingServicing` → `APIClient` + AppFoundation `SessionManaging`. Başarıda
/// sunucunun döndürdüğü kimlik + rotasyonlu token'ları `SessionManaging.linkSession(...)` hook'una
/// verir: hook bellek-içi oturumu CANLI `.linked`e yükseltir, `stateUpdates`e YAYAR (`ProfilModel`
/// relaunch'sız tazelenir — `hesapBaglamaDidLink` yalnız sheet'i kapatır) VE token + kimlik
/// snapshot'ını Keychain'e yazar (relaunch tutarlılığı). `userId` sunucu-otoriter korunur;
/// bakiye/VIP/entitlement sunucuda tutulduğundan client hiçbir varlığı kaybetmez; tekrar çağrı
/// idempotenttir (durum zaten `.linked` ise yayın yapılmaz). Beklenen conflict sonucu DEĞER olarak
/// döner (sunucu 200 verir); yalnız GERÇEK hatalar throw eder (05 §4.2 sözleşmesi, port dokümanı).
struct APIAccountLinkingService: AccountLinkingServicing {
    /// F1'de yalnız Apple bağlanır (Google/e-posta F2) — `HesapBaglamaModel.provider` ile aynı karar;
    /// o sabit @MainActor-izole olduğundan nonisolated adaptörde yerel eşdeğer tutulur.
    static let linkedProvider: AuthProvider = .apple

    private let client: any APIClientProtocol
    private let session: any SessionManaging

    init(client: any APIClientProtocol, session: any SessionManaging) {
        self.client = client
        self.session = session
    }

    func link(_ credential: AppleCredential) async throws -> AccountLinkOutcome {
        let wire = try await client.send(AuthLinkEndpoint(credential: credential))
        switch wire.status {
        case .linked:
            guard let credentials = wire.session else { throw AppError.auth(.linkingFailed) }
            await activateLinkedSession(credentials)
            return .linked(AccountSummary(kind: .linked(provider: Self.linkedProvider)))
        case .conflict:
            guard let conflict = wire.conflict else { throw AppError.auth(.linkingFailed) }
            return .conflict(Self.linkConflict(from: conflict))
        }
    }

    func switchToExistingAccount(_ conflict: AccountLinkConflict) async throws -> AccountSummary {
        let wire = try await client.send(AuthSwitchEndpoint(switchToken: conflict.switchToken))
        await activateLinkedSession(wire.session)
        return AccountSummary(kind: .linked(provider: Self.linkedProvider))
    }

    /// Bağlama/switch başarısını CANLI oturuma yansıtır. `SessionManaging.linkSession` bellek-içi
    /// durumu `.linked`e yükseltir + yayar VE token/snapshot'ı Keychain'e yazar — adaptör artık
    /// Keychain'e ELLE yazmaz (tek yol). Canlı witness @MainActor senkrondur; `any SessionManaging`
    /// üzerinden `await`lenir.
    private func activateLinkedSession(_ credentials: SessionCredentialsWire) async {
        await session.linkSession(
            userID: credentials.userId,
            provider: Self.linkedProvider,
            accessToken: credentials.accessToken,
            refreshToken: credentials.refreshToken
        )
    }

    /// Saf dönüşüm (izole test edilir): 409 conflict wire → ProfileKit `AccountLinkConflict`.
    static func linkConflict(from wire: AuthLinkWire.ConflictWire) -> AccountLinkConflict {
        AccountLinkConflict(
            existingAccountMasked: wire.existingAccountMasked,
            switchToken: wire.switchToken,
            willDiscardGuestData: wire.willDiscardGuestData
        )
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
