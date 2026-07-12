/// Bağlı hesap sağlayıcısı (kanon: Apple/Google/e-posta bağlama, aynı kullanıcı ID'si korunur).
public enum AuthProvider: String, Sendable, Equatable, Codable {
    case apple
    case google
    case email
}

/// Oturum/kimlik durumu (03 §6.2): sahibi `AppFoundation.SessionManager` (SS-021),
/// feature'lar sadece okur; mutasyon yalnız auth akışları (`ProfileKit`) üzerinden.
public enum SessionState: Sendable, Equatable {
    /// İlk açılış — misafir hesabı henüz oluşturulmadı.
    case unauthenticated
    /// Otomatik oluşturulan anonim misafir hesabı (kanon kimlik modeli).
    case guest(userID: String)
    /// Apple/Google/e-posta ile bağlanmış hesap.
    case linked(userID: String, provider: AuthProvider)

    /// Opak kullanıcı kimliği; log'larda kullanıcı YALNIZ bununla anılır (PII kuralı).
    public var userID: String? {
        switch self {
        case .unauthenticated: nil
        case let .guest(userID): userID
        case let .linked(userID, _): userID
        }
    }

    public var isAuthenticated: Bool {
        userID != nil
    }
}

/// Oturum yönetimi protokolü — F0'da STUB; canlı `SessionManager` (misafir bootstrap,
/// Keychain'e token yazımı, single-flight refresh ile işbirliği) SS-021'de gelir.
public protocol SessionManaging: Sendable {
    var state: SessionState { get async }
    /// Durum değişim akışı; abone olunduğunda mevcut durumu yayınlayarak başlar.
    var stateUpdates: AsyncStream<SessionState> { get }
    /// İlk açılışta anonim misafir hesabını kurar; hesap zaten varsa no-op.
    /// Başarısızlık `AppError.auth(.guestBootstrapFailed)` olarak fırlar.
    @discardableResult
    func bootstrapGuestSessionIfNeeded() async throws -> SessionState
}
