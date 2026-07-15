import Foundation

/// İstemcinin son gördüğü streak uzunluğunu KALICI kılan port (SS-111, 08 §3.5 win-back KPI).
/// RewardsKit tanımlar (tüketici), App `UserDefaults`'a bağlar (üretici). `checkin_streak_break`
/// yalnız bellek-içi `previous` ile çalışsaydı cold-launch'ta (`previous == nil`) kırılma —ki
/// çoğu kırılma OTURUMLAR ARASI olur— neredeyse hiç emit edilmezdi. Bu port, son görülen streak'i
/// oturumlar arası taşıyarak model'in soğuk açılışta server ile karşılaştırıp kırılmayı "istemci ilk
/// gördüğünde 1 kez" atmasını sağlar (08 §3.5).
///
/// Saf tespit mantığı `CheckInCycle.detectStreakBreak(lastSeenStreak:current:)`'tedir (izole test edilir);
/// bu port yalnız kalıcılık transport'udur. Kalıp: RewardsKit port + App adaptörü (R8).
public protocol LastSeenStreakStoring: Sendable {
    /// En son görülen (kalıcı) streak uzunluğu; hiç yazılmadıysa `nil` (ilk açılış → kırılma yok).
    func lastSeenStreak() -> Int?

    /// Güncel server streak'ini kalıcı kılar (bir sonraki açılışın karşılaştırma tabanı).
    func setLastSeenStreak(_ value: Int)
}

/// Kalıcı olmayan varsayılan (App bir `UserDefaults` adaptörü bağlayana kadar; init varsayılanı —
/// additive/non-breaking). Bellek-içi olduğundan cold-launch kalıcılığı SAĞLAMAZ; üretimde App
/// `UserDefaults` destekli bir uygulama enjekte eder.
public final class InMemoryLastSeenStreakStore: LastSeenStreakStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int?

    public init(_ value: Int? = nil) {
        self.value = value
    }

    public func lastSeenStreak() -> Int? {
        lock.withLock { value }
    }

    public func setLastSeenStreak(_ value: Int) {
        lock.withLock { self.value = value }
    }
}
