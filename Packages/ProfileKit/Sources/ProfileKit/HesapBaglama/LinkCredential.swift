import AppFoundation

/// Sağlayıcı-bağımsız hesap-bağlama kimlik bilgisi (SS-132 F2; 05 §4.2 `POST /auth/link`). Apple /
/// Google / e-posta kimlik-bilgilerini TEK tipte taşır → `AccountLinkingServicing.link` ve
/// `HesapBaglamaModel` akışı sağlayıcıdan BAĞIMSIZ tek yoldan işler (sıfır-kayıp + çakışma dalı
/// hepsinde ortak). Her case yalnız SAF değer taşır — ham SDK nesnesi (`ASAuthorization`,
/// `GIDGoogleUser`) public yüzeye SIZMAZ (R6/03 §4). Backend isteği `provider` alanını bu tipten
/// türetir; e-posta `identityToken` kalıbına uymaz (opak `verificationToken`, 05 §4.2.1) ama aynı
/// bağlama sonucunu (`AccountLinkOutcome`) üretir.
public enum LinkCredential: Sendable, Equatable {
    case apple(AppleCredential)
    case google(GoogleCredential)
    case email(EmailCredential)

    /// `POST /auth/link` istek gövdesinin `provider` alanı (05 §4.2) ve analitik `link_account_*
    /// {provider}` (02 §4.13) — adaptör bunu ham gövdeye yazar, ProfileKit yorumlaMAZ.
    public var provider: AuthProvider {
        switch self {
        case .apple: .apple
        case .google: .google
        case .email: .email
        }
    }
}
