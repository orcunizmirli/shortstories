import Testing
@testable import RewardsKit

/// SS-111 saf mantık (07 §3.1–§3.2): 7 günlük artan döngü, ödül tablosu, döngü günü türetimi,
/// takvim hücreleri, streak sıfırlanması ve bonus günü. İSTEMCİ SAATİ OKUNMAZ — gün deltaları
/// server-otoriter girdi olarak verilir (saat oynamasına dayanıklılık, KANON §5 / 07 §3.2).
@Suite("SS-111 CheckInCycle saf mantık")
struct CheckInCycleTests {
    // MARK: - Ödül tablosu (07 §3.1: 10-15-20-25-30-40-50)

    @Test func defaultRewardTableMatchesDoc() {
        #expect(CheckInCycle.defaultRewards == [10, 15, 20, 25, 30, 40, 50])
        #expect(CheckInCycle.defaultRewards.reduce(0, +) == 190) // döngü toplamı 190 coin (07 §3.1)
    }

    @Test func rewardForEachCycleDay() {
        let cycle = CheckInCycle()
        #expect(cycle.reward(forCycleDay: 1) == 10)
        #expect(cycle.reward(forCycleDay: 6) == 40)
        #expect(cycle.reward(forCycleDay: 7) == 50)
    }

    @Test func rewardClampsOutOfRangeDay() {
        let cycle = CheckInCycle()
        #expect(cycle.reward(forCycleDay: 0) == 10) // alt uca kırp
        #expect(cycle.reward(forCycleDay: 99) == 50) // üst uca kırp
    }

    @Test func remoteConfigRewardsOverrideDefaults() {
        // Üretimde tablo remote config'ten gelir; eksik/fazla eleman 7'ye normalize edilir.
        let short = CheckInCycle(rewards: [5, 10, 15])
        #expect(short.rewards.count == 7)
        #expect(short.reward(forCycleDay: 1) == 5)
        #expect(short.reward(forCycleDay: 4) == 25) // 4. günden itibaren varsayılanla tamamlandı

        let long = CheckInCycle(rewards: [1, 2, 3, 4, 5, 6, 7, 8, 9])
        #expect(long.rewards.count == 7)
        #expect(long.reward(forCycleDay: 7) == 7)
    }

    // MARK: - Döngü günü türetimi (7'den sonra 1'e döner; streak sayacı artar)

    @Test func cycleDayFromStreakDays() {
        let cycle = CheckInCycle()
        #expect(cycle.cycleDay(forStreakDays: 0) == 1) // henüz claim yok / kırılma sonrası
        #expect(cycle.cycleDay(forStreakDays: 1) == 1)
        #expect(cycle.cycleDay(forStreakDays: 7) == 7)
        #expect(cycle.cycleDay(forStreakDays: 8) == 1) // döngü 1'e döner (07 §3.1)
        #expect(cycle.cycleDay(forStreakDays: 15) == 1)
        #expect(cycle.cycleDay(forStreakDays: 13) == 6)
    }

    @Test func day7IsStreakBonus() {
        let cycle = CheckInCycle()
        #expect(cycle.isStreakBonusDay(cycleDay: 7))
        #expect(!cycle.isStreakBonusDay(cycleDay: 6))
        #expect(!cycle.isStreakBonusDay(cycleDay: 1))
    }

    // MARK: - Streak sıfırlanma kuralı (07 §3.2, saf; gün deltası server-otoriter)

    @Test func streakContinuesOnConsecutiveDay() {
        let cycle = CheckInCycle()
        #expect(cycle.streakAfterClaim(previousStreak: 3, daysSinceLastClaim: 1) == 4)
    }

    @Test func streakResetsWhenDayMissed() {
        let cycle = CheckInCycle()
        // >=2 gün geçtiyse en az bir gün atlandı → yeni seri (bu claim 1. gün).
        #expect(cycle.streakAfterClaim(previousStreak: 6, daysSinceLastClaim: 2) == 1)
        #expect(cycle.streakAfterClaim(previousStreak: 10, daysSinceLastClaim: 5) == 1)
    }

    @Test func sameDayClaimIsNoOp() {
        let cycle = CheckInCycle()
        #expect(cycle.streakAfterClaim(previousStreak: 3, daysSinceLastClaim: 0) == 3)
    }

    // MARK: - Takvim hücreleri (past / today / upcoming + bonus) — View bunu render eder

    @Test func calendarIsEmptyWithoutState() {
        #expect(CheckInCycle().calendar(for: nil).isEmpty)
    }

    @Test func calendarMarksPastTodayUpcoming() {
        let cycle = CheckInCycle()
        let state = CheckInState(
            cycleDay: 3,
            todayClaimed: false,
            todayReward: 20,
            schedule: (1 ... 7).map { CheckInState.DayReward(day: $0, coins: cycle.reward(forCycleDay: $0), claimed: $0 < 3) },
            streakDays: 3,
            streakBonusAt: nil,
            streakBonusCoins: nil
        )
        let cells = cycle.calendar(for: state)
        #expect(cells.count == 7)
        #expect(cells[0].status == .claimed) // gün 1
        #expect(cells[1].status == .claimed) // gün 2
        #expect(cells[2].status == .today) // gün 3, bugün, henüz alınmadı
        #expect(cells[3].status == .upcoming) // gün 4
        #expect(cells[6].isBonus) // gün 7 bonus rozeti
        #expect(cells[2].coins == 20)
    }

    @Test func calendarTodayClaimedMarksTodayAsClaimed() {
        let cycle = CheckInCycle()
        let state = CheckInState(
            cycleDay: 2,
            todayClaimed: true,
            todayReward: 15,
            schedule: (1 ... 7).map { CheckInState.DayReward(day: $0, coins: cycle.reward(forCycleDay: $0), claimed: $0 <= 2) },
            streakDays: 2,
            streakBonusAt: nil,
            streakBonusCoins: nil
        )
        let cells = cycle.calendar(for: state)
        #expect(cells[1].status == .claimed) // bugün alındı → claimed (today değil)
        #expect(cells.filter { $0.status == .today }.isEmpty)
    }

    @Test func calendarTodayCellIsServerAuthoritativeOverStaleSchedule() {
        // Fix 5: bugün hücresi server-otoriter (state.todayReward + state.todayClaimed). Schedule girdisi
        // BAYAT (day 3: claimed:true, coins:20) ama server bugünü henüz-alınmadı + 30 coin diyor →
        // takvim server'ı izler (buton state'i ile TEK kaynak), lokal schedule yalnız fallback.
        let cycle = CheckInCycle()
        let schedule = (1 ... 7).map { day in
            CheckInState.DayReward(day: day, coins: day == 3 ? 20 : cycle.reward(forCycleDay: day), claimed: day <= 3)
        }
        let state = CheckInState(
            cycleDay: 3,
            todayClaimed: false, // server: bugün HENÜZ alınmadı (schedule bayat "claimed:true" diyor)
            todayReward: 30, // server: 30 coin (schedule bayat "20" diyor)
            schedule: schedule,
            streakDays: 3,
            streakBonusAt: nil,
            streakBonusCoins: nil
        )
        let cells = cycle.calendar(for: state)
        #expect(cells[2].status == .today) // server todayClaimed:false → today (schedule.claimed:true değil)
        #expect(cells[2].coins == 30) // server todayReward 30 (schedule 20 değil)
    }

    @Test func calendarTodayFallsBackToScheduleWhenServerRewardMissing() {
        // todayReward <= 0 (server vermedi) ise bugün coin'i schedule/tablodan (fallback) gelir.
        let cycle = CheckInCycle()
        let schedule = (1 ... 7).map { day in
            CheckInState.DayReward(day: day, coins: day == 2 ? 77 : cycle.reward(forCycleDay: day), claimed: day < 2)
        }
        let state = CheckInState(
            cycleDay: 2,
            todayClaimed: false,
            todayReward: 0, // server vermedi → fallback
            schedule: schedule,
            streakDays: 2,
            streakBonusAt: nil,
            streakBonusCoins: nil
        )
        let cells = cycle.calendar(for: state)
        #expect(cells[1].status == .today)
        #expect(cells[1].coins == 77) // schedule fallback
    }

    @Test func calendarFallsBackToDefaultRewardsWhenScheduleEmpty() {
        let cycle = CheckInCycle()
        let state = CheckInState(
            cycleDay: 1,
            todayClaimed: false,
            todayReward: 10,
            schedule: [], // server schedule vermedi → varsayılan tablo
            streakDays: 0,
            streakBonusAt: nil,
            streakBonusCoins: nil
        )
        let cells = cycle.calendar(for: state)
        #expect(cells.count == 7)
        #expect(cells[6].coins == 50)
        #expect(cells[0].status == .today)
    }

    // MARK: - Streak kırılma tespiti (checkin_streak_break, 08 §3.5)

    @Test func noBreakOnFirstLoad() {
        let cycle = CheckInCycle()
        let current = makeState(cycleDay: 1, streakDays: 1)
        #expect(cycle.detectStreakBreak(previous: nil, current: current) == nil)
    }

    @Test func noBreakWhenStreakGrows() {
        let cycle = CheckInCycle()
        let previous = makeState(cycleDay: 2, streakDays: 2)
        let current = makeState(cycleDay: 3, streakDays: 3)
        #expect(cycle.detectStreakBreak(previous: previous, current: current) == nil)
    }

    @Test func detectsBreakWhenStreakDrops() {
        let cycle = CheckInCycle()
        let previous = makeState(cycleDay: 5, streakDays: 5)
        let current = makeState(cycleDay: 1, streakDays: 0) // server sıfırladı
        let brk = cycle.detectStreakBreak(previous: previous, current: current)
        #expect(brk == StreakBreak(previousStreakLength: 5, brokenAtDay: 5))
    }

    // MARK: - Cold-launch kırılma tespiti (Fix 6: kalıcı son-görülen streak; 08 §3.5)

    @Test func detectStreakBreakFromPersistedLastSeen() {
        let cycle = CheckInCycle()
        // İlk açılış (kalıcı değer yok) → kırılma yok.
        #expect(cycle.detectStreakBreak(lastSeenStreak: nil, current: makeState(cycleDay: 1, streakDays: 0)) == nil)
        // Önceki de 0 → kırılma yok.
        #expect(cycle.detectStreakBreak(lastSeenStreak: 0, current: makeState(cycleDay: 1, streakDays: 0)) == nil)
        // Streak korundu → kırılma yok.
        #expect(cycle.detectStreakBreak(lastSeenStreak: 5, current: makeState(cycleDay: 5, streakDays: 5)) == nil)
        // Streak arttı → kırılma yok.
        #expect(cycle.detectStreakBreak(lastSeenStreak: 3, current: makeState(cycleDay: 5, streakDays: 5)) == nil)
        // Kalıcı 5 → server 0 düştü: kırılma (brokenAtDay kalıcı streak'ten türetilir: cycleDay(5)=5).
        #expect(
            cycle.detectStreakBreak(lastSeenStreak: 5, current: makeState(cycleDay: 1, streakDays: 0))
                == StreakBreak(previousStreakLength: 5, brokenAtDay: 5)
        )
        // Kalıcı 9 (>7) → cycleDay(9)=2 türetilir.
        #expect(
            cycle.detectStreakBreak(lastSeenStreak: 9, current: makeState(cycleDay: 1, streakDays: 2))
                == StreakBreak(previousStreakLength: 9, brokenAtDay: 2)
        )
    }

    private func makeState(cycleDay: Int, streakDays: Int) -> CheckInState {
        CheckInState(
            cycleDay: cycleDay,
            todayClaimed: false,
            todayReward: 10,
            schedule: [],
            streakDays: streakDays,
            streakBonusAt: nil,
            streakBonusCoins: nil
        )
    }
}
