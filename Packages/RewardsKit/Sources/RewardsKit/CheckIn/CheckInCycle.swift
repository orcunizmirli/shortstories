/// Check-in takvimindeki tek gün hücresi (SS-111) — SAF görüntüleme değeri; `OdulMerkeziView`
/// şeridi doğrudan render eder. `CheckInCycle.calendar(for:)` üretir; izole test edilir.
public struct CheckInDayCell: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        /// Geçmiş gün (tik) veya bugün alınmış.
        case claimed
        /// Bugün, henüz alınmadı (vurgulu + "Ödülü Al").
        case today
        /// Gelecek gün (soluk/kilitli).
        case upcoming
    }

    public let day: Int
    public let coins: Int
    public let status: Status
    /// 7. gün streak bonusu (rozet/animasyon, 07 §3.1).
    public let isBonus: Bool

    public var id: Int {
        day
    }

    public init(day: Int, coins: Int, status: Status, isBonus: Bool) {
        self.day = day
        self.coins = coins
        self.status = status
        self.isBonus = isBonus
    }
}

/// İstemcinin ilk kez gördüğü streak kırılması (checkin_streak_break analitiği, 08 §3.5).
public struct StreakBreak: Sendable, Equatable {
    public let previousStreakLength: Int
    /// Kırılmanın gerçekleştiği önceki döngü günü.
    public let brokenAtDay: Int

    public init(previousStreakLength: Int, brokenAtDay: Int) {
        self.previousStreakLength = previousStreakLength
        self.brokenAtDay = brokenAtDay
    }
}

/// Check-in döngüsünün SAF mantığı (SS-111, 07 §3.1–§3.2): ödül tablosu, döngü günü türetimi,
/// takvim hücreleri, streak sıfırlanma kuralı ve bonus günü. Yan etkisiz, izole test edilir.
///
/// İSTEMCİ SAATİ OKUNMAZ: sıfırlanma kuralı gün deltasını (`daysSinceLastClaim`) server-otoriter
/// girdi olarak alır; `Date()`/takvim burada YOKTUR (saat oynamasına dayanıklılık, KANON §5).
/// Üretimde ödül tablosu remote config'ten gelir; `defaultRewards` lansman varsayılanıdır.
public struct CheckInCycle: Sendable, Equatable {
    /// Döngü uzunluğu (7 gün).
    public static let length = 7
    /// Lansman varsayılan ödül tablosu (07 §3.1). Toplam 190 coin.
    public static let defaultRewards: [Int] = [10, 15, 20, 25, 30, 40, 50]

    /// 7 elemanlı ödül tablosu (init'te normalize edilir).
    public let rewards: [Int]

    public init(rewards: [Int] = CheckInCycle.defaultRewards) {
        self.rewards = Self.normalize(rewards)
    }

    /// Tabloyu tam `length` elemana normalize eder: fazlaysa kırpar, eksikse varsayılanla tamamlar.
    private static func normalize(_ rewards: [Int]) -> [Int] {
        if rewards.count == length {
            return rewards
        }
        if rewards.count > length {
            return Array(rewards.prefix(length))
        }
        return rewards + defaultRewards[rewards.count ..< length]
    }

    /// Streak gün sayısından (>= 0) 1...7 döngü gününü türetir. 7'den sonra döngü 1'e döner;
    /// streak 0 (henüz claim yok / kırılma sonrası) → gün 1.
    public func cycleDay(forStreakDays streakDays: Int) -> Int {
        guard streakDays > 0 else { return 1 }
        return ((streakDays - 1) % Self.length) + 1
    }

    /// Döngü günü (1...7) → coin ödülü. Aralık dışı gün en yakın uca kırpılır.
    public func reward(forCycleDay day: Int) -> Int {
        let index = min(max(day, 1), Self.length) - 1
        return rewards[index]
    }

    /// 7. gün streak bonusu mu (rozet/animasyon, 07 §3.1).
    public func isStreakBonusDay(cycleDay: Int) -> Bool {
        cycleDay == Self.length
    }

    /// Bir check-in claim'inin streak bonusu içerip içermediğini SERVER-otoriter check-in state'inden
    /// türetir (SS-141). Sözleşmede `reward.bucket` HER ZAMAN 'earned'dır (05 §2.10; Bucket enum yalnız
    /// purchased/earned/unknown) — o coin-TÜRÜdür, 7. gün sinyali DEĞİL — bu yüzden bucket'a GÜVENİLMEZ.
    /// Streak bonusu sinyali claim-sonrası `state.cycleDay`'dir: bonus günü (7) claim edildiyse `true`.
    /// Döngü sarmasında (streak 7, 14, 21…) sunucu `cycleDay`'i 7'ye sarar, dolayısıyla doğru kalır.
    public func isStreakBonus(forClaimedState state: CheckInState) -> Bool {
        isStreakBonusDay(cycleDay: state.cycleDay)
    }

    /// Claim sonrası yeni streak (07 §3.2 sıfırlanma kuralı). Gün deltası SERVER-otoriter girdidir:
    /// - `daysSinceLastClaim <= 0` (bugün zaten claim) → değişmez (no-op).
    /// - `== 1` (ardışık gün) → `previousStreak + 1`.
    /// - `>= 2` (en az bir gün atlandı) → `1` (yeni seri başlar).
    public func streakAfterClaim(previousStreak: Int, daysSinceLastClaim: Int) -> Int {
        let previous = max(previousStreak, 0)
        if daysSinceLastClaim <= 0 {
            return previous
        }
        return daysSinceLastClaim == 1 ? previous + 1 : 1
    }

    /// 7 günlük takvim hücrelerini türetir (past/today/upcoming + bonus). SAF — View doğrudan render eder.
    ///
    /// BUGÜN hücresi SERVER-OTORİTERdir (06 §, R6; 07 §3.2): coin `state.todayReward`, alınmışlık
    /// `state.todayClaimed`'ten okunur — böylece buton state'i (`todayClaimed`) ile takvim hücresi TEK
    /// kaynaktan gelir ve schedule girdisi ile ÇELİŞMEZ. `todayReward <= 0` ise (server vermedi)
    /// schedule/varsayılan tabloya düşülür (lokal yalnız fallback). Geçmiş/gelecek günler schedule'dan
    /// (varsa) yoksa varsayılan ödül tablosundan gelir.
    public func calendar(for state: CheckInState?) -> [CheckInDayCell] {
        guard let state else { return [] }
        let scheduleByDay = Dictionary(state.schedule.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        return (1 ... Self.length).map { day in
            let entry = scheduleByDay[day]
            let isToday = day == state.cycleDay
            let coins: Int
            let claimed: Bool
            if isToday {
                // Server-otoriter bugün hücresi: buton (todayClaimed) ile ortak kaynak; schedule fallback.
                coins = state.todayReward > 0 ? state.todayReward : (entry?.coins ?? reward(forCycleDay: day))
                claimed = state.todayClaimed
            } else {
                coins = entry?.coins ?? reward(forCycleDay: day)
                claimed = entry?.claimed ?? (day < state.cycleDay)
            }
            let status: CheckInDayCell.Status = claimed ? .claimed : (isToday ? .today : .upcoming)
            return CheckInDayCell(day: day, coins: coins, status: status, isBonus: isStreakBonusDay(cycleDay: day))
        }
    }

    /// İstemcinin ilk kez gördüğü streak kırılmasını tespit eder (08 §3.5). Kırılma tespiti
    /// server-otoriterdir: streak önceki bilinen değerden DÜŞTÜYSE kırılma sayılır. İlk yüklemede
    /// (`previous == nil`) veya streak korunduysa/arttıysa `nil`.
    public func detectStreakBreak(previous: CheckInState?, current: CheckInState) -> StreakBreak? {
        guard let previous, previous.streakDays > 0, current.streakDays < previous.streakDays else {
            return nil
        }
        return StreakBreak(previousStreakLength: previous.streakDays, brokenAtDay: previous.cycleDay)
    }

    /// Cold-launch kırılma tespiti (08 §3.5 "istemci ilk gördüğünde 1 kez"): bellek-içi `previous`
    /// yoksa (soğuk açılış) KALICI son-görülen streak ile karşılaştırır. Server streak'i kalıcı
    /// değerin ALTINA düştüyse kırılma; `lastSeenStreak == nil` (ilk açılış) veya korundu/arttıysa `nil`.
    /// `brokenAtDay` kalıcı streak'ten türetilir (`cycleDay(forStreakDays:)`). SAF — izole test edilir.
    public func detectStreakBreak(lastSeenStreak: Int?, current: CheckInState) -> StreakBreak? {
        guard let lastSeen = lastSeenStreak, lastSeen > 0, current.streakDays < lastSeen else {
            return nil
        }
        return StreakBreak(previousStreakLength: lastSeen, brokenAtDay: cycleDay(forStreakDays: lastSeen))
    }
}
