import Foundation

/// E-posta bağlama kimlik bilgisi — taşıma-bağımsız SAF değer tipi (SS-132 F2; 05 §4.2.1). E-posta
/// bağlama `identityToken` kalıbına UYMAZ (kod-doğrulama alt akışı: `start → verify → password`); bu
/// alt akış `EmailLinkProviding` portu İÇİNDE koşar ve backend'in bağlamayı sonlandırmak için ihtiyaç
/// duyduğu opak jetonu döner. Ham parola burada TUTULMAZ (port tüketir); yalnız opak `verificationToken`
/// taşınır — model+testler gerçek uç ÇAĞIRMADAN koşar (Apple/Google kalıbı).
public struct EmailCredential: Sendable, Equatable {
    /// Kullanıcının bağladığı e-posta (backend eşleme + bağlı-hesap özeti; UI teyidi).
    public let email: String
    /// OTP doğrulama + şifre adımı sonrası backend'in döndürdüğü opak bağlama jetonu (`passwordToken`
    /// / verify token, 05 §4.2.1); ProfileKit yorumlaMAZ, yalnız `AccountLinkingServicing.link`e TAŞIR.
    public let verificationToken: String

    public init(email: String, verificationToken: String) {
        self.email = email
        self.verificationToken = verificationToken
    }
}

/// E-posta bağlama alt akışı hata sınıflandırması — ham `APIErrorBody`/`AppError` SIZMAZ (R6).
/// `cancelled` benign kullanıcı iptalidir (form kapatıldı; model `.cancelled`'e düşer); diğerleri
/// gerçek hatadır (model `.failed(.emailUnavailable)`).
public enum EmailLinkError: Error, Sendable, Equatable {
    /// Kullanıcı e-posta formunu/kod ekranını iptal etti.
    case cancelled
    /// Geçersiz/süresi dolmuş kod (CODE_INVALID/CODE_EXPIRED) — kullanıcı yeni kod ister.
    case invalidCode
    /// Zayıf şifre (WEAK_PASSWORD).
    case weakPassword
    /// Ağ/5xx/beklenmedik hata.
    case failed
}

/// E-posta bağlama portu (SS-132 F2). ProfileKit TANIMLAR; kod-doğrulama alt akışının TAMAMINI
/// (`POST /auth/email/start → verify → password`, 05 §4.2.1) port İÇİNDE sarar ve SAF `EmailCredential`
/// döner → model sağlayıcıdan bağımsız TEK yoldan bağlar. Yalnız kimlik-bilgisi ÜRETİR; backend bağlama
/// ayrı `AccountLinkingServicing` portundadır (tek sorumluluk).
///
/// - Note: Canlı adaptör port ARKASINA ertelendi (App-tarafı prep: `/auth/email/*` uçları + kod-giriş
///   alt-UI). Hazır olana kadar App `MockEmailLinkProvider`'ı enjekte eder.
///   TODO: [SS-132 F2] Canlı `EmailLinkService` (`start/verify/password` orkestrasyonu + kod-giriş
///   sunumu → SAF `EmailCredential`) — e-posta uçları donduğunda.
public protocol EmailLinkProviding: Sendable {
    /// E-posta + parola (+ OTP doğrulama, port İÇİNDE) → SAF `EmailCredential`. Ham parola port dışına
    /// SIZMAZ; iptalde `EmailLinkError.cancelled` fırlatır.
    func linkCredential(email: String, password: String) async throws -> EmailCredential
}

/// Yer-tutucu e-posta bağlama sağlayıcısı (SS-132 F2) — canlı `/auth/email/*` orkestrasyonu prep
/// beklerken App bu MOCK'u port ARKASINA enjekte eder. Girilen e-postayı yansıtan deterministik SAHTE
/// `EmailCredential` döner; gerçek uç ÇAĞRILMAZ. Gerçek adaptör hazır olunca DI'da değişir.
public struct MockEmailLinkProvider: EmailLinkProviding {
    public init() {}

    public func linkCredential(email: String, password _: String) async throws -> EmailCredential {
        EmailCredential(email: email, verificationToken: "mock.email.token")
    }
}
