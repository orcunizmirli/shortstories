import AppFoundation
import Foundation
import LibraryKit
import ProfileKit

// ProfileKit hesap portlarının canlı adaptörleri (SS-132/133, R8). Portlar ProfileKit'te tanımlı
// (tüketici); App onları `APIClient` (+ Keychain token kalıcılığı) üzerine köprüler. Beklenen sonuçlar
// (linked/conflict) DEĞER olarak döner → sunucu HER İKİ durumda 200 verir (APIClient 409 gövdesini
// tipli okumadığından conflict bir hata değil, 200 gövdesindeki ayraçtır); yalnız GERÇEK hatalar throw
// eder (05 §4.2 sözleşmesi, port dokümanı).

// MARK: - Hesap değişimi yerel-veri orkestrasyonu (05 §3.3 / §575)

/// 409 "mevcut hesabıma geç" (`switchToExistingAccount`) başarısında ZORUNLU yerel-veri yaşam
/// döngüsü (05 §3.3/§575). Sıra: (a) flush → (b) POST /auth/switch → (c) reset → (d) refetch.
/// `SessionState` mutasyonu SessionManager'da KALIR; bu port yalnız YEREL store'a dokunur (izleme
/// geçmişi + favoriler). Adaptörü test-edilebilir kılmak + LibraryKit servislerini App
/// kompozisyon köküne hapsetmek için ayrı port; canlı uygulaması `LiveAccountSwitchDataCoordinator`.
protocol AccountSwitchDataCoordinating: Sendable {
    /// Switch ÖNCESİ: bekleyen misafir kayıtlarını misafir hesabına yükle (misafir token'ı hâlâ
    /// geçerliyken). BEST-EFFORT — throw ETMEZ: ağ hatası switch'i engellemez ve veriyi kaybetmez
    /// (yükleme başarısızsa `pendingUpload` kalır, `markSynced` yalnız başarıda çalışır).
    func flushPendingGuestData() async
    /// Switch SONRASI: yerel kullanıcı verisini (izleme geçmişi + favoriler) SIFIRLA — yeni hesap
    /// önceki misafirin verisini GÖRMEZ ve sonraki senkron misafir pending'lerini yükleMEZ.
    func resetLocalUserData() async
    /// Reset SONRASI: yeni hesabın sunucu durumunu çek (bir sonraki senkron/açılış sunucudan çeker).
    func refetchForNewAccount() async
}

/// Canlı `AccountSwitchDataCoordinating` (05 §3.3/§575). Flush + refetch tek-kaynak servislerin
/// (`ContinueWatchingService`/`FavoritesService`) `synchronize()`'ıyla yürür (synchronize önce
/// bekleyenleri PUSH eder, sonra sunucu geçmişini PULL edip birleştirir); reset AppFoundation
/// repository `deleteAll()`'larıyla. TÜM adımlar BEST-EFFORT (`try?`): hesap değişimi bilinçli bir
/// kullanıcı kararıdır (`willDiscardGuestData` ile uyarılır) ve yerel-veri temizliği asıl güvenlik
/// amacıdır — ağ hatası akışı bloklamamalı. Flush başarısızsa `pendingUpload` kalır (veri kaybolmaz),
/// reset onu bilinçli olarak siler (yeni hesap misafir verisini görmez).
struct LiveAccountSwitchDataCoordinator: AccountSwitchDataCoordinating {
    private let continueWatching: ContinueWatchingService
    private let favorites: FavoritesService
    private let watchHistoryRepository: any WatchHistoryRepository
    private let favoritesRepository: any FavoritesRepository

    init(
        continueWatching: ContinueWatchingService,
        favorites: FavoritesService,
        watchHistoryRepository: any WatchHistoryRepository,
        favoritesRepository: any FavoritesRepository
    ) {
        self.continueWatching = continueWatching
        self.favorites = favorites
        self.watchHistoryRepository = watchHistoryRepository
        self.favoritesRepository = favoritesRepository
    }

    func flushPendingGuestData() async {
        // switch ÖNCESİ misafir token'ıyla: bekleyen misafir kayıtları misafir hesabına PUSH edilir.
        try? await continueWatching.synchronize()
        try? await favorites.synchronize()
    }

    func resetLocalUserData() async {
        // switch SONRASI: yerel kullanıcı verisi tamamen silinir → yeni hesap misafir verisini görmez
        // ve sonraki senkron misafir pending'lerini yeni hesaba yükleyemez (hesaplar-arası kirlenme yok).
        try? await watchHistoryRepository.deleteAll()
        try? await favoritesRepository.deleteAll()
    }

    func refetchForNewAccount() async {
        // reset SONRASI yeni hesap token'ıyla: sunucu durumu PULL edilir (push edilecek pending yok).
        try? await continueWatching.synchronize()
        try? await favorites.synchronize()
    }
}

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
    private let client: any APIClientProtocol
    private let session: any SessionManaging
    private let switchDataCoordinator: any AccountSwitchDataCoordinating

    init(
        client: any APIClientProtocol,
        session: any SessionManaging,
        switchDataCoordinator: any AccountSwitchDataCoordinating
    ) {
        self.client = client
        self.session = session
        self.switchDataCoordinator = switchDataCoordinator
    }

    /// SAĞLAYICI-BAĞIMSIZ bağlama (SS-132 F2): `LinkCredential` → `POST /auth/link`. İstek gövdesinin
    /// `provider` alanı + jeton alanı `credential`'dan türer (Apple/Google `identityToken`; e-posta opak
    /// `verificationToken`, 05 §4.2/§4.2.1) — Apple/Google/e-posta TEK yoldan geçer. Başarıda oturum
    /// `credential.provider` ile `.linked`e yükselir; `userId` sunucu-otoriter KORUNUR (sıfır-kayıp,
    /// §3.3). Beklenen conflict sonucu DEĞER olarak döner (sunucu 200); yalnız GERÇEK hatalar throw eder.
    func link(_ credential: LinkCredential) async throws -> AccountLinkOutcome {
        let wire = try await client.send(AuthLinkEndpoint(credential: credential))
        switch wire.status {
        case .linked:
            guard let credentials = wire.session else { throw AppError.auth(.linkingFailed) }
            // Sağlayıcı istemci-otoriter: sunucu yanıtı `provider` taşırsa onu tercih et, yoksa
            // bağladığımız kimliğin sağlayıcısı (gönderdiğimizle birebir).
            let provider = credentials.provider ?? credential.provider
            await activateLinkedSession(credentials, provider: provider)
            return .linked(AccountSummary(kind: .linked(provider: provider)))
        case .conflict:
            guard let conflict = wire.conflict else { throw AppError.auth(.linkingFailed) }
            return .conflict(Self.linkConflict(from: conflict))
        }
    }

    func switchToExistingAccount(_ conflict: AccountLinkConflict) async throws -> AccountSummary {
        // (a) FLUSH (switch ÖNCESİ, misafir token'ı hâlâ geçerliyken): bekleyen misafir kayıtlarını
        // misafir hesabına yükle — best-effort, throw etmez (ağ hatası switch'i engellemez, veri
        // kaybolmaz; yükleme başarısızsa pendingUpload kalır). 05 §3.3 sırasının ilk adımı.
        await switchDataCoordinator.flushPendingGuestData()

        // (b) POST /auth/switch → oturumu `.linked`e yükselt (Keychain token ROTASYONU: sonraki
        // istekler yeni hesap token'ıyla gider). GERÇEK hata burada throw ederse store SIFIRLANMAZ
        // (yerel misafir verisi korunur — sıfır-kayıp). Geçilen hesabın sağlayıcısı SUNUCU-otoriter;
        // alan yoksa geriye-uyumlu `.apple` (F1 REGRESYONSUZ).
        // TODO: [SS-132 F2] `/auth/switch` sözleşmesi donduğunda `provider` alanını zorunlu kıl.
        let wire = try await client.send(AuthSwitchEndpoint(switchToken: conflict.switchToken))
        let provider = wire.provider ?? .apple
        await activateLinkedSession(wire.session, provider: provider)

        // (c) RESET (switch SONRASI): yerel kullanıcı verisini sıfırla → yeni hesap misafir verisini
        // GÖRMEZ ve sonraki senkron misafir pending'lerini yeni hesaba yükleyemez.
        await switchDataCoordinator.resetLocalUserData()

        // (d) REFETCH: yeni hesabın sunucu durumunu çek (bir sonraki senkron/açılış tazeler).
        await switchDataCoordinator.refetchForNewAccount()

        return AccountSummary(kind: .linked(provider: provider))
    }

    /// Bağlama/switch başarısını CANLI oturuma yansıtır. `SessionManaging.linkSession` bellek-içi
    /// durumu `.linked`e yükseltir + yayar VE token/snapshot'ı Keychain'e yazar — adaptör artık
    /// Keychain'e ELLE yazmaz (tek yol; SessionState sahibi SessionManager). Canlı witness @MainActor
    /// senkrondur; `any SessionManaging` üzerinden `await`lenir.
    private func activateLinkedSession(_ credentials: SessionCredentialsWire, provider: AuthProvider) async {
        await session.linkSession(
            userID: credentials.userId,
            provider: provider,
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

/// `POST /auth/link` (05 §4.2) SAĞLAYICI-BAĞIMSIZ istek gövdesi. `provider` alanı + jeton alanları
/// `LinkCredential`'dan türer: Apple/Google `identityToken` kalıbına uyar; e-posta uymaz → opak
/// `verificationToken` taşır (05 §4.2.1). Yalnız İLGİLİ sağlayıcının alanları dolar, diğerleri `nil`
/// (encoder atlar). SAF dönüşüm — `linkConflict(from:)` gibi izole test edilir.
struct AuthLinkRequestBody: Encodable, Sendable, Equatable {
    /// `POST /auth/link` `provider` alanı (05 §4.2) — `AuthProvider.rawValue` ("apple"/"google"/"email").
    let provider: String
    /// Apple/Google OIDC kimlik jetonu (JWT). E-postada `nil`.
    let identityToken: String?
    /// E-posta bağlama opak doğrulama jetonu (05 §4.2.1). Apple/Google'da `nil`.
    let verificationToken: String?
    /// Tek kullanımlık sunucu auth code (opsiyonel; Apple/Google).
    let authorizationCode: String?
    /// Apple opak kullanıcı kimliği (yalnız Apple).
    let userIdentifier: String?
    /// Sağlayıcı e-postası (varsa; backend eşleme — Apple yalnız ilk yetkilendirmede).
    let email: String?
    /// Apple görünen ad (yalnız Apple, ilk yetkilendirme).
    let fullName: String?

    /// `LinkCredential` → gövde: her case yalnız kendi alanlarını doldurur; `provider` tek kaynaktan
    /// (`credential.provider.rawValue`) türer → sağlayıcı eklendiğinde tek yerde genişler.
    static func make(from credential: LinkCredential) -> AuthLinkRequestBody {
        switch credential {
        case let .apple(apple):
            AuthLinkRequestBody(
                provider: credential.provider.rawValue,
                identityToken: apple.identityToken,
                verificationToken: nil,
                authorizationCode: apple.authorizationCode,
                userIdentifier: apple.userIdentifier,
                email: apple.email,
                fullName: apple.fullName
            )
        case let .google(google):
            AuthLinkRequestBody(
                provider: credential.provider.rawValue,
                identityToken: google.idToken,
                verificationToken: nil,
                authorizationCode: google.authorizationCode,
                userIdentifier: nil,
                email: google.email,
                fullName: nil
            )
        case let .email(email):
            AuthLinkRequestBody(
                provider: credential.provider.rawValue,
                identityToken: nil,
                verificationToken: email.verificationToken,
                authorizationCode: nil,
                userIdentifier: nil,
                email: email.email,
                fullName: nil
            )
        }
    }
}

/// `POST /auth/link` (05 §4.2). Misafir hesabına SAĞLAYICI-BAĞIMSIZ kimlik bağlar; `userId` korunur
/// (sunucu merge). İstek gövdesi `LinkCredential`'dan türer (`AuthLinkRequestBody.make`).
private struct AuthLinkEndpoint: Endpoint {
    typealias Response = AuthLinkWire

    let credential: LinkCredential

    var path: String {
        "/auth/link"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        AuthLinkRequestBody.make(from: credential)
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
    /// Sunucu-otoriter sağlayıcı (opsiyonel). Varsa `link` bunu tercih eder; yoksa istemci
    /// `credential.provider`'a düşer (gönderdiğimizle birebir). Geriye-uyumlu ekleme.
    let provider: AuthProvider?
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
    /// Geçilen mevcut hesabın SUNUCU-otoriter sağlayıcısı (opsiyonel). `switchToExistingAccount`
    /// protokolü sağlayıcı taşımadığından değer buradan okunur; yoksa geriye-uyumlu `.apple`.
    let provider: AuthProvider?
}

struct AccountDeleteWire: Decodable, Sendable {
    let undoDeadline: Date?
    let requiresStoreSubscriptionCancellation: Bool
}

struct DataExportWire: Decodable, Sendable {
    let deliveryEmailMasked: String?
}
