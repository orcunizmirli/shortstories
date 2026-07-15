import Foundation

/// Günlük check-in durumu (SS-111) — RewardsKit-sahipli SAF domain değeri; 05 §2.10 `CheckInState`
/// sözleşmesinin istemci karşılığı. Ağ/Codable kaygısı burada YOKTUR: App adaptörü API JSON'ını
/// bu tipe map eder (kalıp: LibraryKit `LibrarySeriesInfo`, ProfileKit `WalletSummary`).
///
/// Doğruluk kaynağı SUNUCUDUR: `todayClaimed`/`cycleDay`/`streakDays` server-state'ten gelir; istemci
/// "bugün claim edildi mi"yi cihaz saatinden ASLA türetmez (07 §3.2, saat oynamasına dayanıklılık).
public struct CheckInState: Sendable, Equatable {
    /// 1...7 — 7 günlük artan döngüdeki bugünün günü. Gün atlanırsa sunucu 1'e döndürür.
    public let cycleDay: Int
    /// Bugünün ödülü alındı mı — "Ödülü Al" butonunun durumu (server-otoriter).
    public let todayClaimed: Bool
    /// Bugünün coin ödülü (10-50 aralığı; kesin değer server/remote config).
    public let todayReward: Int
    /// 7 elemanlı takvim (OdulMerkezi şeridi). Boş gelirse istemci varsayılan tabloya düşer.
    public let schedule: [DayReward]
    /// Kesintisiz gün sayısı (streak). Döngü 7'de biter ama streak artmaya devam eder.
    public let streakDays: Int
    /// Bir sonraki streak bonusunun eşik günü ("3 gün daha → +100 coin" teşviki); yoksa nil.
    public let streakBonusAt: Int?
    /// Streak bonusunun coin miktarı; yoksa nil.
    public let streakBonusCoins: Int?

    public init(
        cycleDay: Int,
        todayClaimed: Bool,
        todayReward: Int,
        schedule: [DayReward],
        streakDays: Int,
        streakBonusAt: Int?,
        streakBonusCoins: Int?
    ) {
        self.cycleDay = cycleDay
        self.todayClaimed = todayClaimed
        self.todayReward = todayReward
        self.schedule = schedule
        self.streakDays = streakDays
        self.streakBonusAt = streakBonusAt
        self.streakBonusCoins = streakBonusCoins
    }

    /// Takvimdeki tek gün (05 §2.10 `CheckInState.DayReward`).
    public struct DayReward: Sendable, Equatable, Identifiable {
        public let day: Int
        public let coins: Int
        public let claimed: Bool

        public var id: Int {
            day
        }

        public init(day: Int, coins: Int, claimed: Bool) {
            self.day = day
            self.coins = coins
            self.claimed = claimed
        }
    }
}
