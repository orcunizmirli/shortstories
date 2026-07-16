import Foundation
import RewardsKit

/// RewardsKit `TaskProgressReading`'in App-tarafı ÜRETİCİSİ (SS-112, R8). RewardsKit görev ilerlemesini
/// yalnız OKUR (canlı overlay, YALNIZ GÖRÜNTÜLEME — claim-edilebilirlik server `state`'idir); gerçek
/// olay kaynaklarını (izleme süresi, favorileme, paylaşım, bildirim izni) App bu store'a besler.
///
/// Kompozisyon kökü tek örnek tutar ve olay kaynaklarını (player heartbeat, LibraryKit favori aksiyonu,
/// paylaşım sheet completion, APNs authorization) `record(_:value:)` ile bu store'a bağlar. `OdulMerkezi`
/// açıkken `progressUpdates()` çubuğu tepkili ilerletir. F1'de store boş başlar; olay bağlamaları
/// Faz 2'de ilgili ekran/servis kurulumunda eklenir — port sözleşmesi (current-value + akış) şimdiden
/// canlıdır.
///
/// Concurrency: durum `NSLock` ile korunur (`@unchecked Sendable`); yayın current-value replay'li
/// `AsyncBroadcaster` üzerinden (geç abone güncel ilerlemeyi kaçırmaz).
final class LiveTaskProgressStore: TaskProgressReading, @unchecked Sendable {
    private let lock = NSLock()
    private var progress: [RewardTask.Kind: Int]
    private let broadcaster: AsyncBroadcaster<[RewardTask.Kind: Int]>

    init(initial: [RewardTask.Kind: Int] = [:]) {
        progress = initial
        broadcaster = AsyncBroadcaster(initial)
    }

    // MARK: - TaskProgressReading (okuma)

    func currentProgress() async -> [RewardTask.Kind: Int] {
        lock.withLock { progress }
    }

    func progressUpdates() -> AsyncStream<[RewardTask.Kind: Int]> {
        broadcaster.subscribe()
    }

    // MARK: - Üretici yüzeyi (App olay kaynaklarını buraya bağlar)

    /// Bir görev tipinin anlık ilerlemesini SET eder ve yayınlar (idempotent snapshot besleme).
    func record(_ kind: RewardTask.Kind, value: Int) {
        let snapshot: [RewardTask.Kind: Int] = lock.withLock {
            progress[kind] = value
            return progress
        }
        broadcaster.send(snapshot)
    }

    /// Bir görev tipinin ilerlemesini `delta` kadar artırır ve yayınlar (ör. izlenen dakika +1).
    func increment(_ kind: RewardTask.Kind, by delta: Int = 1) {
        let snapshot: [RewardTask.Kind: Int] = lock.withLock {
            progress[kind, default: 0] += delta
            return progress
        }
        broadcaster.send(snapshot)
    }
}
