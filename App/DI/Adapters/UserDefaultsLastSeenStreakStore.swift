import Foundation
import RewardsKit

/// RewardsKit `LastSeenStreakStoring` → `UserDefaults` (SS-111, 08 §3.5 cold-launch win-back KPI).
/// Son görülen streak'i OTURUMLAR ARASI kalıcı kılar → model soğuk açılışta server ile karşılaştırıp
/// `checkin_streak_break`'i "istemci ilk gördüğünde 1 kez" atabilir. Bellek-içi `InMemoryLastSeenStreakStore`
/// yerine üretimde bu enjekte edilir.
///
/// `lastSeenStreak()` yazılmadıysa `nil` döner (ilk açılış → kırılma yok): `PreferencesStoring` her
/// zaman varsayılan döndüğünden burada `UserDefaults.object(forKey:)` ile YOKLUK ayırt edilir.
/// `UserDefaults` thread-safe olduğundan `@unchecked Sendable` güvenlidir.
final class UserDefaultsLastSeenStreakStore: LastSeenStreakStoring, @unchecked Sendable {
    /// 03 §9 UserDefaults ad uzayı — RewardsKit tercih anahtarı.
    static let key = "rewards.last_seen_streak"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func lastSeenStreak() -> Int? {
        defaults.object(forKey: Self.key) as? Int
    }

    func setLastSeenStreak(_ value: Int) {
        defaults.set(value, forKey: Self.key)
    }
}
