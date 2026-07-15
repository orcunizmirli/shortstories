/// Misafir→bağlı hesap yükseltme sonucu (05 §4.2 `POST /auth/link`). Başarıda sunucu `userId`'yi
/// KORUR (aynı hesaba kimlik eklenir) → coin bakiyesi, kilitli bölümler, VIP, Listem SUNUCU-otoriter
/// korunur, client hiçbir varlığı kaybetmez (ONB-06 KC1 / §3.3). Çakışmada 409 birleştirme kararı.
public enum AccountLinkOutcome: Sendable, Equatable {
    /// Bağlandı — güncel hesap özeti (oturum bağlıya yükseldi; `userId` değişmedi).
    case linked(AccountSummary)
    /// 409 `ACCOUNT_ALREADY_LINKED` — bu Apple kimliği başka hesaba bağlı; kullanıcı karar verir.
    case conflict(AccountLinkConflict)
}

/// 409 çakışma yükü (05 §4.2). Ham hata gövdesi (`APIErrorBody`) SIZMAZ — yalnız UI'nin gösterip
/// birleştirme kararına ihtiyaç duyduğu alanlar.
public struct AccountLinkConflict: Sendable, Equatable {
    /// Maskeli mevcut hesap kimliği ("usr_**12ef") — çakışma diyaloğunda gösterilir.
    public let existingAccountMasked: String
    /// `POST /auth/switch` için opak token (`switchToken`). App kullanır; ProfileKit yalnız TAŞIR,
    /// içeriğini yorumlaMAZ. "Mevcut hesabıma geç" seçilirse geri portun `switch`'ine verilir.
    public let switchToken: String
    /// Bu hesaba geçilirse misafirdeki yerel varlıkların kaybolup kaybolmayacağı (backend belirler).
    /// `true` ise UI açıkça uyarır (ONB-06 KC2: "misafir varlıkları kaybolacaksa açıkça uyarılır").
    public let willDiscardGuestData: Bool

    public init(existingAccountMasked: String, switchToken: String, willDiscardGuestData: Bool) {
        self.existingAccountMasked = existingAccountMasked
        self.switchToken = switchToken
        self.willDiscardGuestData = willDiscardGuestData
    }
}

/// Hesap bağlama backend portu (SS-132, R8). ProfileKit TANIMLAR (tüketici); App `SessionManager`
/// + `APIClient`'a bağlar (üretici) — `WalletSummaryReading` kalıbıyla birebir. Başarıda App
/// oturumu `.linked`'e yükseltip güncel `AccountSummary` döner; ProfileKit `SessionState` mutasyonuna
/// DOKUNMAZ (kanon: mutasyon yalnız auth akışında, sahibi `SessionManager`).
///
/// Beklenen iki sonuç (`linked`/`conflict`) DEĞER olarak döner; yalnız GERÇEK hatalar (ağ, 5xx,
/// beklenmedik yanıt) `throw` eder → model `.failed`'e düşer.
public protocol AccountLinkingServicing: Sendable {
    /// `POST /auth/link` — Apple kimliğini misafir hesaba bağlar (`userId` korunur, sunucu merge).
    func link(_ credential: AppleCredential) async throws -> AccountLinkOutcome

    /// 409 sonrası "mevcut hesabıma geç" → `POST /auth/switch` + `switchToken`. Geçişte yerel veri
    /// kuralı §3.3 (App: `pendingUpload` flush → store sıfırla → sunucudan çek). Bağlı özet döner.
    func switchToExistingAccount(_ conflict: AccountLinkConflict) async throws -> AccountSummary
}
