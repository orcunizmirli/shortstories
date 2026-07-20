import AppFoundation
import Foundation

/// RewardsKit analitik event registry sabitleri — 08-analitik-deney.md §3.5 TEK DOĞRULUK KAYNAĞI.
/// Event adları, parametre anahtarları ve `mission_type` değer taksonomisi BURADA tek noktada yaşar;
/// çağrı noktaları (aşağıdaki `AnalyticsTracking` emit yardımcıları) string/sözlük tekrarı yerine bu
/// sabitleri kullanır (§2.1 adlandırma). Registry'de olmayan bir event gönderilemez (§2.3) — bu enum
/// yalnız §3.5'te tanımlı RewardsKit event'lerini taşır.
enum RewardsAnalytics {
    /// §3.5 event adları (`snake_case`, `alan_eylem`).
    enum Event {
        static let checkinView = "checkin_view"
        static let checkinClaim = "checkin_claim"
        static let checkinStreakBreak = "checkin_streak_break"
        static let missionView = "mission_view"
        static let missionProgress = "mission_progress"
        static let missionComplete = "mission_complete"
        static let missionClaim = "mission_claim"
        // SS-113 rewarded ads (§3.5): start/complete/fail — RewardsKit sahipli. `complete` 2° zorunlu.
        static let rewardedAdStart = "rewarded_ad_start"
        static let rewardedAdComplete = "rewarded_ad_complete"
        static let rewardedAdFail = "rewarded_ad_fail"
    }

    /// §3.5 parametre anahtarları (ortak parametreler §2.2 `track()` tarafından otomatik eklenir).
    enum Param {
        static let currentStreakDay = "current_streak_day"
        static let canClaimToday = "can_claim_today"
        static let streakDay = "streak_day"
        static let coinReward = "coin_reward"
        static let isStreakBonus = "is_streak_bonus"
        static let brokenAtDay = "broken_at_day"
        static let previousStreakLength = "previous_streak_length"
        static let missionIDs = "mission_ids"
        static let missionCount = "mission_count"
        static let missionID = "mission_id"
        static let progressPct = "progress_pct"
        static let missionType = "mission_type"
        static let expiresAt = "expires_at"
        // SS-113 rewarded ads (§3.5): yüzey + server-otoriter cap raporlaması.
        static let placement = "placement"
        static let adsUsedToday = "ads_used_today"
        static let dailyCap = "daily_cap"
    }

    /// §3.5 `mission_type` değer taksonomisi — registry YALNIZ bu 4 tipi tanır. İstemci `RewardTask.Kind`
    /// eşlemesi `RewardTask.Kind.analyticsMissionType` üzerinden tek noktada yapılır.
    enum MissionType {
        static let watchTime = "watch_time"
        static let favorite = "favorite"
        static let share = "share"
        static let pushOptin = "push_optin"
    }

    /// mission_progress hacim kontrolü: yalnız %50 checkpoint'i raporlanır (§3.5).
    static let halfwayCheckpointPct = 50

    /// `Date` → Unix epoch ms (§2.2 `event_ts` konvansiyonu) — `mission_claim.expires_at` kodlaması.
    static func epochMilliseconds(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1000).rounded())
    }
}

/// §3.5 RewardsKit event'lerinin İNŞA + emit yardımcıları — registry sabitleriyle (yukarıda) aynı
/// dosyada; çağrı noktaları terse kalır ve parametre sözlükleri tek yerde inşa edilir. Ortak
/// parametreler (§2.2) `AnalyticsClient.track` içinde otomatik eklenir.
extension AnalyticsTracking {
    /// checkin_view — check-in takvimi görünür olduğunda.
    func trackCheckinView(currentStreakDay: Int, canClaimToday: Bool) {
        track(RewardsAnalytics.Event.checkinView, parameters: [
            RewardsAnalytics.Param.currentStreakDay: .int(currentStreakDay),
            RewardsAnalytics.Param.canClaimToday: .bool(canClaimToday)
        ])
    }

    /// checkin_claim (2°) — günlük ödül talebi server'da onaylandığında.
    func trackCheckinClaim(streakDay: Int, coinReward: Int, isStreakBonus: Bool) {
        track(RewardsAnalytics.Event.checkinClaim, parameters: [
            RewardsAnalytics.Param.streakDay: .int(streakDay),
            RewardsAnalytics.Param.coinReward: .int(coinReward),
            RewardsAnalytics.Param.isStreakBonus: .bool(isStreakBonus)
        ])
    }

    /// checkin_streak_break — backend streak sıfırlamasını istemci ilk gördüğünde.
    func trackCheckinStreakBreak(brokenAtDay: Int, previousStreakLength: Int) {
        track(RewardsAnalytics.Event.checkinStreakBreak, parameters: [
            RewardsAnalytics.Param.brokenAtDay: .int(brokenAtDay),
            RewardsAnalytics.Param.previousStreakLength: .int(previousStreakLength)
        ])
    }

    /// mission_view — görev listesi görünür olduğunda (`mission_count` id sayısından türetilir).
    func trackMissionView(missionIDs: [String]) {
        track(RewardsAnalytics.Event.missionView, parameters: [
            RewardsAnalytics.Param.missionIDs: .string(missionIDs.joined(separator: ",")),
            RewardsAnalytics.Param.missionCount: .int(missionIDs.count)
        ])
    }

    /// mission_progress — görev ilerlemesi %50'yi İLK geçtiğinde (yalnız 50 checkpoint'i).
    func trackMissionProgress(missionID: String) {
        track(RewardsAnalytics.Event.missionProgress, parameters: [
            RewardsAnalytics.Param.missionID: .string(missionID),
            RewardsAnalytics.Param.progressPct: .int(RewardsAnalytics.halfwayCheckpointPct)
        ])
    }

    /// mission_complete (2°) — görev tamamlandı/claimable durumuna geçtiğinde.
    func trackMissionComplete(missionID: String, missionType: String) {
        track(RewardsAnalytics.Event.missionComplete, parameters: [
            RewardsAnalytics.Param.missionID: .string(missionID),
            RewardsAnalytics.Param.missionType: .string(missionType)
        ])
    }

    /// mission_claim (2°) — ödül cüzdana yazıldığında; `expiresAt` (SS-115) varsa `expires_at` eklenir.
    func trackMissionClaim(missionID: String, coinReward: Int, expiresAt: Date?) {
        var parameters: [String: AnalyticsValue] = [
            RewardsAnalytics.Param.missionID: .string(missionID),
            RewardsAnalytics.Param.coinReward: .int(coinReward)
        ]
        if let expiresAt {
            parameters[RewardsAnalytics.Param.expiresAt] = .int(RewardsAnalytics.epochMilliseconds(expiresAt))
        }
        track(RewardsAnalytics.Event.missionClaim, parameters: parameters)
    }

    // MARK: - SS-113 rewarded ads (§3.5)

    /// rewarded_ad_start — reklam gösterimi başladığında (`RewardedAdService.watchAdToUnlock`).
    func trackRewardedAdStart(placement: String, dailyCap: Int?) {
        track(RewardsAnalytics.Event.rewardedAdStart, parameters: rewardedAdParameters(
            placement: placement, adsUsedToday: nil, dailyCap: dailyCap
        ))
    }

    /// rewarded_ad_complete (2°) — 30 sn tamamlanıp server SSV kilidi açtığında. `adsUsedToday` server'ın
    /// verdiği KALAN HAK'tan türetilir (istemci saymaz).
    func trackRewardedAdComplete(placement: String, adsUsedToday: Int?, dailyCap: Int?) {
        track(RewardsAnalytics.Event.rewardedAdComplete, parameters: rewardedAdParameters(
            placement: placement, adsUsedToday: adsUsedToday, dailyCap: dailyCap
        ))
    }

    /// rewarded_ad_fail — doldurma yok / gösterim hatası / cap / SSV reddi (erken kapatma HARİÇ — kullanıcı seçimi).
    func trackRewardedAdFail(placement: String, dailyCap: Int?) {
        track(RewardsAnalytics.Event.rewardedAdFail, parameters: rewardedAdParameters(
            placement: placement, adsUsedToday: nil, dailyCap: dailyCap
        ))
    }

    /// Ortak rewarded ad parametreleri — opsiyonel alanlar (`ads_used_today`/`daily_cap`) yalnız
    /// bilindiğinde eklenir (server bildirmediyse alan taşınmaz).
    private func rewardedAdParameters(placement: String, adsUsedToday: Int?, dailyCap: Int?) -> [String: AnalyticsValue] {
        var parameters: [String: AnalyticsValue] = [RewardsAnalytics.Param.placement: .string(placement)]
        if let adsUsedToday {
            parameters[RewardsAnalytics.Param.adsUsedToday] = .int(adsUsedToday)
        }
        if let dailyCap {
            parameters[RewardsAnalytics.Param.dailyCap] = .int(dailyCap)
        }
        return parameters
    }
}
