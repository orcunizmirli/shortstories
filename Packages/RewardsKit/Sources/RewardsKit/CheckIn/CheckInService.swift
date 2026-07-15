import Foundation

/// Bir claim'de kredilenen ödül (05 §4.7 `reward`). SUNUCU belirler; istemci lokal HESAPLAMAZ.
public struct ClaimedReward: Sendable, Equatable {
    /// Kredilenen coin (earned bucket).
    public let coins: Int
    /// Bu claim streak bonusu içeriyor mu (7. gün) — `checkin_claim.is_streak_bonus` analitiği.
    public let isStreakBonus: Bool
    /// Earned coin son kullanma tarihi (varsa; 06 cüzdan kuralları). SS-115 vade gösterimi.
    public let expiresAt: Date?

    public init(coins: Int, isStreakBonus: Bool, expiresAt: Date?) {
        self.coins = coins
        self.isStreakBonus = isStreakBonus
        self.expiresAt = expiresAt
    }
}

/// Başarılı check-in claim'inin server yanıtı (05 §4.7). SERVER-OTORİTER: yeni cüzdan bakiyesi ve
/// güncel `CheckInState` sunucudan döner — istemci OPTİMİSTİK KREDİ VERMEZ, bu sonucu bekler.
public struct CheckInClaimResult: Sendable, Equatable {
    public let reward: ClaimedReward
    /// Claim sonrası güncel check-in durumu (cycleDay/streak/schedule).
    public let checkin: CheckInState
    /// Claim sonrası güncel toplam coin bakiyesi (server-otoriter; başlık bununla güncellenir).
    public let coinBalance: Int

    public init(reward: ClaimedReward, checkin: CheckInState, coinBalance: Int) {
        self.reward = reward
        self.checkin = checkin
        self.coinBalance = coinBalance
    }
}

/// Check-in claim özel hatası. Transport/ağ hataları `AppError` olarak fırlatılır; bu tip yalnız
/// idempotent çift-claim durumunu taşır (server'ın taze durumuyla).
public enum CheckInClaimError: Error, Sendable, Equatable {
    /// 409 ALREADY_CLAIMED (05 §4.7): bugün zaten alınmış. Yanıttaki taze `CheckInState` taşınır;
    /// istemci durumu SESSİZCE senkronlar (hata toast'ı GÖSTERMEZ, 07 §3.3).
    case alreadyClaimed(CheckInState)
}

/// Server-otoriter check-in servisi portu (SS-111, R8) — `RewardClaiming`. RewardsKit tanımlar
/// (tüketici), App canlı `APIClient`'a bağlar (üretici): `GET /rewards/checkin` + `POST
/// /rewards/checkin/claim`. Kalıp: LibraryKit `LibraryCatalogReading`, ProfileKit `WalletSummaryReading`.
///
/// Idempotency ve timezone TRANSPORT ayrıntısıdır ve App adaptörüne aittir: adaptör her claim POST'una
/// `Idempotency-Key` (UUID v4) ve IANA timezone header'ı ekler, yanıtsız kalan claim'i AYNI anahtarla
/// tekrarlar (05 §9). RewardsKit UUID/timezone/saat GÖRMEZ — "bugün claim edildi mi" server-state'ten
/// (`status()`) okunur, cihaz saatinden ASLA türetilmez (saat oynamasına dayanıklılık, 07 §3.2).
public protocol CheckInService: Sendable {
    /// `GET /rewards/checkin` → güncel durum. Transport hatası `AppError` fırlatır.
    func status() async throws -> CheckInState

    /// `POST /rewards/checkin/claim` → başarılı krediyle sonuç. Bugün zaten alınmışsa
    /// `CheckInClaimError.alreadyClaimed(fresh)`, transport hatasında `AppError` fırlatır.
    func claim() async throws -> CheckInClaimResult
}
