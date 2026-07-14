import AppFoundation
import ContentKit
import Foundation

/// Havuza ısındırma köprüsü (PlayerKit-internal): PrefetchController havuzu bu dar
/// arayüzden görür; testler kayıt tutan sahteyle koşar.
protocol EpisodeWarming: Sendable {
    func warm(_ episode: Episode, atFeedIndex feedIndex: Int) async
}

/// Sonraki bölüm ön-yükleme denetleyicisi (04 §5, SS-042). Public yüzeyi yalnız
/// `init`'tir (04 §2.4); pencere yönetimi internal'dır ve feed VC diliminden
/// (SS-044) sürülür. Hedef seçimi saf `PrefetchPolicy`'dedir; burası yalnız task
/// yaşam döngüsü yönetir: hedef dışı kalan prefetch İPTAL edilir, bant genişliği
/// yeni pencereye verilir (04 §5.1).
public actor PrefetchController {
    private let warmer: any EpisodeWarming
    private let network: any NetworkConditionProviding
    private let preferences: any PlaybackPreferencesProviding
    private let poolSizeProvider: @Sendable () async -> Int
    /// Bayt/süre ölçüm kancası (SS-047 devri): tamamlanan ısındırma, bütçe
    /// yaklaşığıyla kaydedilir; gerçek ağ sayacı SS-041'dedir.
    private let measurer: any PrefetchMeasuring

    /// İzlenen ısındırma görevi: tamamlanma işleyicisi anahtar VARLIĞINA değil görev
    /// KİMLİĞİNE (token) bakar — iptal edilip yenilenen eski görevin geç tamamlanması
    /// aynı bölümün YENİ görevini defterden düşüremez (görev kimliği korkuluğu).
    private struct TrackedWarmup {
        let token: UUID
        let task: Task<Void, Never>
    }

    private var tasks: [EpisodeID: TrackedWarmup] = [:]
    /// Pencere içinde kalırken tamamlanan ısındırmalar: aynı hedef yeniden ısındırılmaz;
    /// hedef pencereden çıkınca kayıt düşer (slot geri alınmış olabilir).
    private var completedWarmups: Set<EpisodeID> = []
    private var lastWindowChangeAt: Date?

    /// Kompozisyon kökü init'i (04 §2.4): havuz + ağ portu + oynatma tercihleri.
    public init(
        pool: PlayerPool,
        network: any NetworkConditionProviding,
        preferences: any PlaybackPreferencesProviding
    ) {
        warmer = pool
        self.network = network
        self.preferences = preferences
        poolSizeProvider = { await pool.slotCount }
        measurer = PrefetchMeasurementLog()
    }

    /// Test dikişi: sahte warmer + sabit havuz boyutu (+ isteğe bağlı ölçüm kaydedicisi).
    init(
        warmer: any EpisodeWarming,
        network: any NetworkConditionProviding,
        preferences: any PlaybackPreferencesProviding,
        poolSize: Int,
        measurer: (any PrefetchMeasuring)? = nil
    ) {
        self.warmer = warmer
        self.network = network
        self.preferences = preferences
        poolSizeProvider = { poolSize }
        self.measurer = measurer ?? PrefetchMeasurementLog()
    }

    /// Aktif indeks değişti (swipe yerleşti / feed kuruldu): politika planı çıkarılır,
    /// hedef dışı task'lar iptal edilir, yeni hedefler ısındırılır.
    func windowChanged(
        activeIndex: Int,
        episodes: [Episode],
        direction: ScrollDirection,
        at now: Date = Date()
    ) async {
        let secondsSinceLastSwipe = lastWindowChangeAt.map { now.timeIntervalSince($0) }
        lastWindowChangeAt = now

        let context = await PrefetchPolicy.Context(
            activeIndex: activeIndex,
            direction: direction,
            poolSize: poolSizeProvider(),
            episodeCount: episodes.count,
            lockedIndexes: Set(episodes.indices.filter { !episodes[$0].access.isPlayableWithoutUnlock }),
            network: network.currentCondition(),
            isDataSaverEnabled: preferences.isDataSaverEnabled(),
            secondsSinceLastSwipe: secondsSinceLastSwipe
        )
        let plan = PrefetchPolicy.plan(context)

        let targetIDs = Set(plan.targetIndexes.map { episodes[$0].id })
        cancelTasks(notIn: targetIDs)

        for feedIndex in plan.targetIndexes {
            let episode = episodes[feedIndex]
            guard tasks[episode.id] == nil, !completedWarmups.contains(episode.id) else { continue } // idempotent
            let token = UUID()
            let budget = plan.budget
            let task = Task(priority: .utility) { [warmer, measurer] in
                await warmer.warm(episode, atFeedIndex: feedIndex)
                let wasCancelled = Task.isCancelled
                // Task {} actor bağlamını devralır; taskCompleted izole (senkron) çağrıdır.
                self.taskCompleted(episode.id, token: token, wasCancelled: wasCancelled)
                if !wasCancelled {
                    // Yaklaşık ölçüm = bütçe tanımı (~500 KB / ilk 2 sn — 04 §5.1);
                    // gerçek ağ sayacı SS-041'de bu kancaya bağlanır.
                    await measurer.recordWarmupCompleted(
                        episodeID: episode.id,
                        approximateBytes: budget.maxBytes,
                        approximateSeconds: budget.maxSeconds
                    )
                }
            }
            tasks[episode.id] = TrackedWarmup(token: token, task: task)
        }
    }

    /// Tüm bekleyen prefetch'leri durdurur (veri tasarrufuna geçiş, feed'den çıkış).
    func cancelAll() {
        for tracked in tasks.values {
            tracked.task.cancel()
        }
        tasks.removeAll()
        completedWarmups.removeAll()
    }

    /// Test yardımcısı: mevcut ısındırma task'larının bitmesini bekler.
    func awaitPendingWarmups() async {
        for tracked in tasks.values {
            await tracked.task.value
        }
    }

    /// Test dikişi: bölüm için izlenen aktif ısındırma task'ı (kimlik doğrulaması için).
    func pendingTask(for episodeID: EpisodeID) -> Task<Void, Never>? {
        tasks[episodeID]?.task
    }

    private func cancelTasks(notIn targetIDs: Set<EpisodeID>) {
        for (episodeID, tracked) in tasks where !targetIDs.contains(episodeID) {
            tracked.task.cancel()
            tasks[episodeID] = nil
        }
        completedWarmups = completedWarmups.intersection(targetIDs)
    }

    private func taskCompleted(_ episodeID: EpisodeID, token: UUID, wasCancelled: Bool) {
        // Görev kimliği korkuluğu: yalnız kendi kaydını düşürebilir; anahtar bu
        // arada başka (yeni) göreve geçtiyse dokunmaz.
        guard tasks[episodeID]?.token == token else { return }
        tasks[episodeID] = nil
        if !wasCancelled {
            completedWarmups.insert(episodeID)
        }
    }
}
