import Foundation

/// Google Sign-In kimlik bilgisi — taşıma-bağımsız SAF değer tipi (SS-132 F2; 05 §4.2
/// `POST /auth/link`, `provider: "google"`). Ham `GIDGoogleUser`/`GIDSignInResult` public API'de
/// SIZMAZ (R6/03 §4): yalnız backend'in ikinci-taraf teyidi için ihtiyaç duyduğu opak jeton alanları
/// taşınır → model+port testleri gerçek Google SDK ve UI OLMADAN koşar (Apple/StoreKit sarmalı kalıbı).
public struct GoogleCredential: Sendable, Equatable {
    /// Backend'e giden opak OIDC kimlik jetonu (`idToken`); ProfileKit içeriğini yorumlaMAZ, TAŞIR.
    public let idToken: String
    /// Tek kullanımlık sunucu auth code (backend ikinci-taraf teyidi için; opsiyonel).
    public let authorizationCode: String?
    /// Google hesap e-postası (varsa; backend eşleme için opsiyonel — UI'da gösterilmez).
    public let email: String?

    public init(idToken: String, authorizationCode: String? = nil, email: String? = nil) {
        self.idToken = idToken
        self.authorizationCode = authorizationCode
        self.email = email
    }
}

/// Google Sign-In sonucu hata sınıflandırması — ham `GIDSignInError` SIZMAZ (R6). `cancelled`
/// benign kullanıcı iptalidir (success/failed funnel'ına GİRMEZ, model `.cancelled`'e düşer);
/// diğerleri gerçek hatadır (model `.failed(.googleUnavailable)`).
public enum GoogleSignInError: Error, Sendable, Equatable {
    /// Kullanıcı Google sayfasını iptal etti.
    case cancelled
    /// Google akışı başarısız (SDK/ağ/beklenmedik).
    case failed
    /// Sonuç döndü ama `idToken` çözülemedi (beklenmedik yanıt).
    case invalidResponse
}

/// Google Sign-In portu (SS-132 F2). ProfileKit TANIMLAR (tüketici); yalnız kimlik-bilgisi ÜRETİR —
/// backend bağlama ayrı `AccountLinkingServicing` portundadır (tek sorumluluk, `AppleSignInProviding`
/// ile birebir). `Sendable`: canlı adaptör Google SDK sınırında @MainActor-izole olacağından
/// (`AppleSignInService` kalıbı) sözleşmeyi karşılar; Google SDK ProfileKit'e sızmaz (enjekte edilir).
///
/// - Note: Canlı `GIDSignIn` adaptörü port ARKASINA ertelendi — bu, App-tarafı prep bekler
///   (Google Sign-In SDK bağımlılığı + `GIDConfiguration` OAuth client-ID + `URL scheme`). Hazır
///   olana kadar App `MockGoogleSignInProvider`'ı enjekte eder; model/akış hazır (uyarlama noktası).
///   TODO: [SS-132 F2] Canlı `GoogleSignInService` (`GIDSignIn.signIn(withPresenting:)` sarmalı →
///   SAF `GoogleCredential`; ham `GIDGoogleUser` HAPSOLUR) — Google SDK/OAuth client-ID prep sonrası.
public protocol GoogleSignInProviding: Sendable {
    /// Google yetkilendirme sayfasını sunar ve SAF `GoogleCredential` döner.
    /// Kullanıcı iptalinde `GoogleSignInError.cancelled` fırlatır.
    func signIn() async throws -> GoogleCredential
}

/// Yer-tutucu Google Sign-In sağlayıcısı (SS-132 F2) — canlı `GIDSignIn` adaptörü prep beklerken App
/// bu MOCK'u port ARKASINA enjekte eder. Deterministik SAHTE `GoogleCredential` döner; gerçek Google
/// UI/SDK ÇAĞRILMAZ (Google SDK ProfileKit'e sızmaz). Gerçek adaptör hazır olunca DI'da değişir —
/// model/akış aynı kalır (port sözleşmesi sabittir).
public struct MockGoogleSignInProvider: GoogleSignInProviding {
    private let credential: GoogleCredential

    public init(credential: GoogleCredential = GoogleCredential(idToken: "mock.google.idtoken")) {
        self.credential = credential
    }

    public func signIn() async throws -> GoogleCredential {
        credential
    }
}
