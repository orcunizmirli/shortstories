import Foundation

/// Sign in with Apple kimlik bilgisi — taşıma-bağımsız SAF değer tipi (05 §4.2 `POST /auth/link`).
/// Ham `ASAuthorization`/`ASAuthorizationAppleIDCredential` public API'de SIZMAZ (R6/03 §4): yalnız
/// backend'in `POST /auth/link` için ihtiyaç duyduğu alanlar taşınır. Bu sayede model+port testleri
/// gerçek Apple UI ve `AuthenticationServices` OLMADAN koşar (StoreKit sarmalı kalıbı).
public struct AppleCredential: Sendable, Equatable {
    /// Backend'e giden JWT (`identityToken`, UTF-8 decode edilmiş base64url string).
    public let identityToken: String
    /// Tek kullanımlık authorization code (backend ikinci-taraf teyidi için; opsiyonel).
    public let authorizationCode: String?
    /// Apple opak kullanıcı kimliği (`credential.user`) — cihazlar arası kararlı.
    public let userIdentifier: String
    /// Apple YALNIZ İLK yetkilendirmede döner; sonraki girişlerde `nil` (backend ilk seferde saklar).
    public let email: String?
    /// Apple YALNIZ İLK yetkilendirmede döner (görünen ad); sonra `nil`.
    public let fullName: String?

    public init(
        identityToken: String,
        authorizationCode: String? = nil,
        userIdentifier: String,
        email: String? = nil,
        fullName: String? = nil
    ) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.userIdentifier = userIdentifier
        self.email = email
        self.fullName = fullName
    }
}

/// Sign in with Apple sonucu hata sınıflandırması — ham `ASAuthorizationError` SIZMAZ (R6).
/// `cancelled` benign kullanıcı iptalidir (hata funnel'ına girmez); diğerleri gerçek hatadır.
public enum AppleSignInError: Error, Sendable, Equatable {
    /// Kullanıcı Apple sayfasını iptal etti (`ASAuthorizationError.canceled`).
    case cancelled
    /// Apple akışı başarısız (unknown/failed/notInteractive/matchedExcludedCredential vb.).
    case failed
    /// Credential döndü ama `identityToken` çözülemedi (beklenmedik yanıt).
    case invalidResponse
}

/// Sign in with Apple portu (SS-132). Canlı sarmalayıcı `AppleSignInService`
/// (`ASAuthorizationController`); testler fake port ile başarı/iptal/hata senaryolarını
/// gerçek Apple UI OLMADAN kurar. Yalnız kimlik-bilgisi ÜRETİR — backend bağlama işi
/// ayrı `AccountLinkingServicing` portundadır (tek sorumluluk).
public protocol AppleSignInProviding: Sendable {
    /// Apple yetkilendirme sayfasını sunar ve SAF `AppleCredential` döner.
    /// Kullanıcı iptalinde `AppleSignInError.cancelled` fırlatır.
    func requestCredential() async throws -> AppleCredential
}
