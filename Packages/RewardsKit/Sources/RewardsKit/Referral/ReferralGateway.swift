import Foundation

/// Kendi davet durumum (05 §4.7 `<state>`). SAF domain; ağ/Codable/UUID YOK (kalıp: `CheckInState`).
/// DOĞRULUK KAYNAĞI SUNUCU: sayaçlar/kod/`inviteURL` server-state'ten gelir, cihazdan TÜRETİLMEZ.
public struct ReferralStatus: Sendable, Equatable {
    /// Bu kullanıcının paylaşacağı davet kodu (server üretir).
    public let inviteCode: String
    /// Hazır davet deep-link'i (server verir; istemci KURMAZ). Yoksa App `DeepLinkFactory` ile kurar.
    public let inviteURL: URL?
    /// Bu kullanıcının kodunu kullanan toplam davet sayısı.
    public let invitedCount: Int
    /// Ödül kazandıran (nitelikli) davet sayısı.
    public let rewardedCount: Int
    /// Henüz nitelenmemiş (beklemede) davet sayısı.
    public let pendingCount: Int
    /// Nitelikli davet başına kazanılan coin (remote-config; gösterim için).
    public let rewardPerReferral: Int
    /// Ödüllendirilen azami davet sayısı (varsa; server kuralı).
    public let maxReferrals: Int?
    /// Bu kullanıcı bir davet kodu kullanabilir mi (yeni-kullanıcı penceresi vb. — server-otoriter).
    public let canRedeem: Bool

    public init(
        inviteCode: String,
        inviteURL: URL?,
        invitedCount: Int,
        rewardedCount: Int,
        pendingCount: Int,
        rewardPerReferral: Int,
        maxReferrals: Int?,
        canRedeem: Bool
    ) {
        self.inviteCode = inviteCode
        self.inviteURL = inviteURL
        self.invitedCount = invitedCount
        self.rewardedCount = rewardedCount
        self.pendingCount = pendingCount
        self.rewardPerReferral = rewardPerReferral
        self.maxReferrals = maxReferrals
        self.canRedeem = canRedeem
    }
}

/// Bir davet kodu kullanmanın (redeem) sonucu. Görev/check-in claim'inden FARKI: iş-kuralı çakışması
/// FIRLATILMAZ, değer olarak döner — çünkü çakışmalar (geçersiz kod / kendine-davet) kullanıcıya
/// GÖSTERİLİR (check-in 409'u sessiz senkrondu). SERVER-OTORİTER: `.credited` yalnız server 200'ünde
/// üretilir; istemci OPTİMİSTİK KREDİ VERMEZ. Transport/ağ hataları `AppError` olarak fırlatılır.
///
/// NOT (kapsam): coin BAKİYESİ bu ekranda gösterilmez (OdulMerkezi'nin işi — davet ekranı oradan
/// açılır). `.credited` yalnız kazanılan ödül miktarını (`reward.coins`) taşır; running-total DEĞİL.
public enum ReferralRedeemOutcome: Sendable, Equatable {
    /// Kod kabul edildi; server krediyi yazdı. Kazanılan ödül + güncel davet durumu taşınır.
    case credited(reward: ClaimedReward, referral: ReferralStatus)
    /// Kod reddedildi — kullanıcıya-görünür iş kuralı; kredi YOK.
    case conflict(ReferralConflict)
}

/// Redeem iş-kuralı çakışmaları (kullanıcıya-görünür; kredi vermez).
public enum ReferralConflict: Sendable, Equatable {
    /// 404 REFERRAL_CODE_INVALID — kod yok/hatalı.
    case invalidCode
    /// 410 REFERRAL_CODE_EXPIRED — kodun süresi dolmuş.
    case expired
    /// 422 REFERRAL_SELF — kendi kodunu kullanmaya çalıştı.
    case selfReferral
    /// 409 REFERRAL_ALREADY_REDEEMED — bu kullanıcı zaten bir kod kullandı. Taze durum EKLİDİR (varsa);
    /// taze-durum GET'i başarısız olursa `nil` — çakışma mesajı yine gösterilir, durum bir sonraki
    /// yüklemede senkronlanır (adaptör taze GET'i best-effort yapar, transport hatasını yutar).
    case alreadyRedeemed(ReferralStatus?)
}

/// Server-otoriter referral portu (RWD-07, R8). RewardsKit TANIMLAR (tüketici), App canlı `APIClient`'a
/// bağlar (üretici): `GET /rewards/referral` + `POST /rewards/referral/redeem`. Kalıp: `CheckInService`.
///
/// Idempotency-Key ve timezone TRANSPORT ayrıntısıdır ve App adaptörüne aittir (redeem POST'una
/// `Idempotency-Key` (UUID v4) eklenir, yanıtsız kalan istek AYNI anahtarla tekrarlanır, 05 §9).
/// RewardsKit UUID/timezone GÖRMEZ.
public protocol ReferralGateway: Sendable {
    /// `GET /rewards/referral` → güncel davet durumu. Transport hatası `AppError` fırlatır.
    func status() async throws -> ReferralStatus

    /// `POST /rewards/referral/redeem` → kredilenmiş sonuç veya kullanıcıya-görünür çakışma.
    /// Transport hatasında `AppError` fırlatır.
    func redeem(code: String) async throws -> ReferralRedeemOutcome
}
