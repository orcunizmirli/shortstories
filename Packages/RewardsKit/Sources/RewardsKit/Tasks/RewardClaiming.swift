/// Server-otoriter görev ödülü claim portu (SS-112, R8) — `RewardClaiming`. RewardsKit tanımlar
/// (tüketici), App canlı `APIClient`'a bağlar (üretici): `POST /missions/{id}/claim`. Kalıp:
/// `CheckInService` (check-in claim), LibraryKit `LibraryCatalogReading`.
///
/// PARA GÜVENLİĞİ (06 §, fraud R6): kredi SERVER-OTORİTER + IDEMPOTENT. İstemci OPTİMİSTİK KREDİ
/// VERMEZ — bu sonucu bekler; yeni bakiye ve güncel görev sunucudan döner. `Idempotency-Key` (UUID v4)
/// TRANSPORT ayrıntısıdır ve App adaptörüne aittir (05 §9); adaptör yanıtsız claim'i AYNI anahtarla
/// tekrarlar. RewardsKit UUID GÖRMEZ.
public protocol RewardClaiming: Sendable {
    /// `POST /missions/{id}/claim` → başarılı krediyle sonuç. Görev claim-edilebilir değilse
    /// `RewardClaimError.notClaimable(fresh)`, transport hatasında `AppError` fırlatır.
    func claimTask(id: String) async throws -> RewardTaskClaimResult
}

/// Başarılı görev claim'inin server yanıtı (05 §4.7). SERVER-OTORİTER: yeni cüzdan bakiyesi ve
/// güncel `RewardTask` sunucudan döner — istemci OPTİMİSTİK KREDİ VERMEZ, bu sonucu bekler.
public struct RewardTaskClaimResult: Sendable, Equatable {
    /// Kredilenen ödül (`ClaimedReward` — check-in ile ortak; görevlerde `isStreakBonus` daima false).
    public let reward: ClaimedReward
    /// Claim sonrası güncel görev (state artık `.claimed`).
    public let task: RewardTask
    /// Claim sonrası güncel toplam coin bakiyesi (server-otoriter; başlık bununla güncellenir).
    public let coinBalance: Int

    public init(reward: ClaimedReward, task: RewardTask, coinBalance: Int) {
        self.reward = reward
        self.task = task
        self.coinBalance = coinBalance
    }
}

/// Görev claim özel hatası. Transport/ağ hataları `AppError` olarak fırlatılır; bu tip yalnız
/// idempotent "claim edilemez" durumunu taşır (server'ın taze durumuyla).
public enum RewardClaimError: Error, Sendable, Equatable {
    /// 409 MISSION_NOT_CLAIMABLE (05 §4.7): görev claim-edilebilir değil (zaten alınmış / süresi
    /// dolmuş / henüz tamamlanmamış). Yanıttaki taze `RewardTask` taşınır; istemci durumu SESSİZCE
    /// senkronlar (hata toast'ı GÖSTERMEZ, kredi VERMEZ — idempotent tekrar).
    case notClaimable(RewardTask)
}
