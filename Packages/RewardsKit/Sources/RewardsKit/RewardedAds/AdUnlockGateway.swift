import Foundation

/// Rewarded ad ödül teyidi PORTU (SS-113, 05 §4.7 `POST /rewards/ad-unlock`). RewardsKit tanımlar
/// (tüketici), App canlı `APIClient`'a bağlar (üretici). Kalıp: `CheckInService`, `RewardClaiming`.
///
/// SERVER-OTORİTER + SSV (06 §9.4): istemci client callback'ine GÜVENMEZ ve KREDİ VERMEZ — yalnız
/// sağlayıcı-bağımsız kanıt zarfını (`RewardProof`) iletir; server `provider`'a göre doğrulayıcı seçer
/// (AdMob → SSV, S2S imzalı callback) ve unlock/coin grant'ini + cap sayacını YAZAR. `Idempotency-Key`
/// (05 §9) ve nonce eşlemesi TRANSPORT ayrıntısıdır ve App adaptörüne aittir — adaptör yanıtsız isteği
/// AYNI anahtarla tekrarlar; RewardsKit UUID/header GÖRMEZ.
public protocol AdUnlockGateway: Sendable {
    /// `POST /rewards/ad-unlock {provider, proofPayload}` → server-otoriter sonuç. Cap aşımında
    /// `AdUnlockError.capReached` (429), kanıt reddinde `AdUnlockError.rewardRejected`, transport
    /// hatasında `AppError` fırlatır.
    func requestAdUnlock(_ request: AdUnlockRequest) async throws -> AdUnlockOutcome
}

/// Rewarded ad ile açılacak hedef (06 §9.1). Aynı günlük cap havuzunu paylaşırlar (06 §9.2).
public enum AdRewardTarget: Sendable, Equatable {
    /// UnlockSheet: belirli bölümün kilidini aç (05 §4.7 `episodeId`). Coin düşmez/grant edilmez;
    /// unlock ledger'a `method: rewardedAd`, `coinsSpent: 0` yazılır (05 §2.7).
    case episode(id: String)
    /// OdulMerkezi kartı: küçük earned coin ödülü (bölüm yok, 06 §9.1). Vade/miktar server belirler.
    case coinReward
}

/// Ad-unlock isteği zarfı (05 §4.7 sağlayıcı-bağımsız). Hedef + opak kanıt; server SSV doğrular.
public struct AdUnlockRequest: Sendable, Equatable {
    public let target: AdRewardTarget
    public let proof: RewardProof

    public init(target: AdRewardTarget, proof: RewardProof) {
        self.target = target
        self.proof = proof
    }
}

/// Ad-unlock server yanıtı (05 §4.7; `POST /wallet/unlock` ile aynı zarf). SERVER-OTORİTER — istemci
/// bu değerleri GÖSTERİR, bunlardan bakiye/hak TÜRETMEZ (05 §963, 03 §9).
public struct AdUnlockOutcome: Sendable, Equatable {
    /// Kilidi açılan/ödül verilen hedef (isteğin `target`'ıyla eşleşir; idempotent tekrar da aynısını döner).
    public let target: AdRewardTarget
    /// Bu işlemden SONRA kalan günlük hak (server "N/5"); istemci ASLA kendi saymaz. `nil` = server bildirmedi.
    public let remainingToday: Int?
    /// İşlem sonrası güncel toplam coin bakiyesi (yalnız gösterim; coinReward yolunda kredi burada görünür).
    /// `nil` = yanıtta yok. İstemci bu değerle cüzdanı MUTASYONA UĞRATMAZ — server-otoriter snapshot.
    public let coinBalance: Int?

    public init(target: AdRewardTarget, remainingToday: Int?, coinBalance: Int?) {
        self.target = target
        self.remainingToday = remainingToday
        self.coinBalance = coinBalance
    }
}

/// Ad-unlock özel hatası (transport/ağ hataları `AppError` olarak fırlatılır). Bu tip yalnız
/// server'ın ödülü VERMEDİĞİ iki iş durumunu taşır.
public enum AdUnlockError: Error, Sendable, Equatable {
    /// 429 AD_UNLOCK_CAP_REACHED (05 §4.7): günlük cap doldu. `resetsAt` = `details.resetsAt` (hakların
    /// yenileneceği an). Ödül YOK; yüzey capReached durumuna geçer.
    case capReached(resetsAt: Date?)
    /// Server SSV kanıtını REDDETTİ (06 §9.4 client callback'ine güvenilmez): sahte/eşleşmeyen kanıt.
    /// Ödül YOK; kilit AÇILMAZ.
    case rewardRejected
}
