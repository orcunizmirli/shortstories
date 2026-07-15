import AppFoundation

/// Profil hesap kartının durumu (02 §4.13) — `SessionState`'ten türetilen SAF değer tipi.
/// Misafir → "Misafir" + "Hesabını bağla" CTA; bağlı → sağlayıcı; oturum düştü → yeniden giriş
/// (05 §4.2, F2 UI). İsim/e-posta gibi profil detayı `SessionManaging`'de YOKTUR (opak userID +
/// provider); tam profil çekimi ayrı bir port işidir (F1 kapsamı dışı) — bu tip sağlayıcıdan
/// türeyen görünen adı verir.
public struct AccountSummary: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case guest
        case linked(provider: AuthProvider)
        /// Bağlı hesabın refresh zinciri koptu — misafire DÖNÜLMEZ, yeniden giriş istenir.
        case sessionExpired(provider: AuthProvider)
    }

    public let kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public var isGuest: Bool {
        if case .guest = kind {
            true
        } else {
            false
        }
    }

    public var isLinked: Bool {
        if case .linked = kind {
            true
        } else {
            false
        }
    }

    public var provider: AuthProvider? {
        switch kind {
        case .guest: nil
        case let .linked(provider): provider
        case let .sessionExpired(provider): provider
        }
    }

    /// `SessionState` → hesap özeti (SAF). `unauthenticated` (misafir henüz kurulmadı) misafir
    /// gibi gösterilir; `loggedOut` yeniden giriş durumudur.
    public static func make(from state: SessionState) -> AccountSummary {
        switch state {
        case .unauthenticated, .guest:
            AccountSummary(kind: .guest)
        case let .linked(_, provider):
            AccountSummary(kind: .linked(provider: provider))
        case let .loggedOut(_, provider):
            AccountSummary(kind: .sessionExpired(provider: provider))
        }
    }
}

extension AuthProvider {
    /// Profil hesap satırının görünen sağlayıcı adı.
    var profileDisplayName: String {
        switch self {
        case .apple: "Apple"
        case .google: "Google"
        case .email: "E-posta"
        }
    }
}
