import AppFoundation
import ContentKit
import Foundation

/// Feed'in oynatma yönetmeni (PlayerKit-internal): havuz/prefetch/metrik koreografisinin
/// TEK kapısıdır (SS-044). Tüm havuz çağrıları bu actor kuyruğunda SERİLEŞİR — eşzamanlı
/// settle'ların activate/recycle blokları iç içe geçemez (acquire reentrancy; tek kapı).
actor FeedPlaybackDirector {
    /// Settle sonucu: UIKit katmanı yalnız bu değeri yorumlar (delegate köprüsü).
    enum SettleOutcome: Sendable {
        case activated(PlaybackHandle, Episode)
        /// Kilitli bölüme gelindi (04 §9.1): oynatma başlamaz, UnlockSheet intent'i
        /// Coordinator'a delegate ile akar.
        case locked(Episode)
        case failed(AppError, Episode)
        /// Bölüm taşımayan kartta (ör. seriesPromo) yerleşildi: oynatma durur ama
        /// aktif indeks ilerledi — VC `didChangeActiveIndex(episode: nil)` bildirir
        /// (04 §2.4 / PlayerFeedDelegate public sözleşmesi, 04 §8.6 ara kart).
        case settledWithoutEpisode
        /// Geçersiz indeks ya da idempotent tekrar.
        case none
    }

    private let pool: any FeedPlaybackPooling
    private let prefetch: any FeedPrefetching
    private let metrics: PlayerMetricsCollector
    private let poolSizeProvider: @Sendable () async -> Int

    private var items: [FeedItem] = []
    private var activeIndex: Int?
    private var activeHandle: PlaybackHandle?
    /// İdempotent kilit tetiği (04 §9 kabul kriteri: çift sheet açılmaz).
    private var notifiedLockedIndex: Int?
    /// Hız menüsü tercihi (04 §8.2); uzun basma 2x bunun üzerine geçici biner.
    private var preferredRate: Double = 1.0
    private var isAutoAdvanceEnabled = true
    /// Bölüm sonuna KIRPILAN kullanıcı seek'i auto-next tetiklemez (04 §8.1).
    private var suppressNextAutoAdvance = false
    /// Serileştirme kuyruğu: her operasyon bir öncekinin bitişini bekler.
    private var tail: Task<Void, Never>?
    private var playedToEndWatchTask: Task<Void, Never>?

    /// Auto-advance kararları (04 §8.6): feed VC tüketir, programatik kaydırmayı uygular.
    nonisolated let autoAdvanceDecisions: AsyncStream<AutoAdvancePolicy.Decision>
    private let autoAdvanceContinuation: AsyncStream<AutoAdvancePolicy.Decision>.Continuation

    init(
        pool: any FeedPlaybackPooling,
        prefetch: any FeedPrefetching,
        metrics: PlayerMetricsCollector,
        poolSizeProvider: @escaping @Sendable () async -> Int
    ) {
        self.pool = pool
        self.prefetch = prefetch
        self.metrics = metrics
        self.poolSizeProvider = poolSizeProvider
        (autoAdvanceDecisions, autoAdvanceContinuation) = AsyncStream.makeStream()
    }

    deinit {
        playedToEndWatchTask?.cancel()
        autoAdvanceContinuation.finish()
    }

    // MARK: - Feed durumu

    func updateItems(_ newItems: [FeedItem]) {
        items = newItems
    }

    func setAutoAdvanceEnabled(_ enabled: Bool) {
        isAutoAdvanceEnabled = enabled
    }

    var currentActiveIndex: Int? {
        activeIndex
    }

    // MARK: - Settle (kaydırma yerleşti / ilk açılış / programatik geçiş)

    func settle(at index: Int, startType: PlaybackStartType, now: Date) async -> SettleOutcome {
        await serialized { await self.performSettle(at: index, startType: startType, now: now) }
    }

    /// İlk kare görünür oldu (AVPlayerLayer.isReadyForDisplay — 04 §13). Bayat
    /// ilk-kare korkuluğu (04 §14 T5, denetim (c)): YALNIZ güncel aktif bölümün ilk
    /// karesi ölçüme katılır — ekran dışına çıkıp geç ateşlenen eski hücrenin
    /// callback'i (eski episodeID) sahte video_start/ttff/swipe_next üretemez.
    func firstFrameBecameVisible(episodeID: EpisodeID, at now: Date) async {
        guard let index = activeIndex, items.indices.contains(index),
              let episode = items[index].episode, episode.id == episodeID
        else { return }
        await metrics.recordFirstFrame(for: episode, at: now)
    }

    // MARK: - Jest → oynatma kontrolü

    /// Tek tap (04 §8.1): anında play/pause.
    func togglePlayPause() async {
        guard let handle = activeHandle else { return }
        switch await handle.currentState() {
        case .playing, .stalled:
            await handle.pause()
        case .paused, .readyAtFirstFrame:
            await handle.play()
        case .idle, .loading, .failed:
            break
        }
    }

    /// Çift tap (04 §8): tek tap'in anında uygulanmış etkisi geri alınır, ±10 sn
    /// seek uygulanır (250 ms bekleme YAPILMAZ stratejisinin ikinci yarısı).
    func revertToggleAndSeek(offsetSeconds: Double) async {
        await togglePlayPause()
        await seekByOffset(offsetSeconds)
    }

    /// ±10 sn seek; hedef bölüm sınırlarına kırpılır. Sona kırpılan seek'te
    /// auto-next bastırılır (04 §8.1 — kullanıcı bekletilir).
    func seekByOffset(_ offsetSeconds: Double) async {
        guard let handle = activeHandle,
              let index = activeIndex,
              items.indices.contains(index),
              let episode = items[index].episode
        else { return }
        let duration = Double(episode.durationSec)
        let current = await handle.engine.currentPositionSeconds()
        let target = FeedSeekPolicy.targetSeconds(
            current: current,
            offsetSeconds: offsetSeconds,
            durationSeconds: duration
        )
        if offsetSeconds > 0, target >= duration {
            suppressNextAutoAdvance = true
        }
        // Çift-tap ±10 sn: hızlı TOLERANT seek (04 §8.1 / 01 PLR-02); keskin `.zero` yalnız scrubber.
        await handle.seekTolerant(toSeconds: target)
    }

    /// Uzun basma (04 §8.1): basılıyken 2x, bırakınca tercih hızına dönüş. Hıza
    /// geçmeden ÖNCE ton koruması uygulanır (01 PLR-03: `.timeDomain`).
    func setHoldSpeed(_ active: Bool) async {
        guard let handle = activeHandle else { return }
        let rate = active ? FeedHoldSpeedPolicy.holdRate : preferredRate
        await handle.engine.setPitchPreservation(rate != 1.0)
        await handle.setRate(rate)
    }

    /// Hız menüsü tercihi (04 §8.2; kalıcılaştırma SS-131). Ton koruması uygulanır (01 PLR-03).
    func setPreferredRate(_ rate: Double) async {
        preferredRate = rate
        await activeHandle?.engine.setPitchPreservation(rate != 1.0)
        await activeHandle?.setRate(rate)
    }

    // MARK: - Swipe niyeti (t0 = scrollViewWillEndDragging — 04 §13.1)

    /// Swipe gecikmesi t0'ı: hedef indeks belli olduğunda (VC willEndDragging) kaydedilir —
    /// deceleration ölçüme dahil; `watch_pct_at_swipe` gerçek pozisyondan (02 §4.3.7). Serileşir.
    func recordSwipeIntent(toIndex: Int, at now: Date) async {
        await serialized { await self.performRecordSwipeIntent(toIndex: toIndex, at: now) }
    }

    // MARK: - Unlock sonrası akıcı devam (04 §9.2)

    /// Unlock tamamlandı: kullanıcı hâlâ o hücredeyse AYNI kartta oynatma başlar (p90 < 700 ms).
    /// Kilit korkuluğu + idempotans guard temizlenir (aksi halde re-settle yutulurdu — 04 §9.2).
    func reactivateAfterUnlock(at index: Int, now: Date) async -> SettleOutcome {
        await serialized { await self.performReactivateAfterUnlock(at: index, now: now) }
    }

    // MARK: - Yaşam döngüsü

    func pauseActive() async {
        // Tek kapı sözleşmesi (SS-044): havuz/oynatma çağrıları actor kuyruğunda serileşir.
        await serialized { await self.performPauseActive() }
    }

    /// Feed'den çıkış (04 §3.3): prefetch iptal + item'lar bırakılır, player'lar korunur.
    /// Serialized kuyrukta koşar — settle ortasında drain/prefetch yarışı olmaz (denetim (d)).
    func teardown() async {
        await serialized { await self.performTeardown() }
    }
}

// MARK: - Settle içi akış

private extension FeedPlaybackDirector {
    /// Unlock sonrası aynı hücre aktivasyonu (04 §9.2) — kuyrukta serileşir.
    func performReactivateAfterUnlock(at index: Int, now: Date) async -> SettleOutcome {
        notifiedLockedIndex = nil
        if activeIndex == index {
            activeIndex = nil
        }
        return await performSettle(at: index, startType: .tap, now: now)
    }

    func performPauseActive() async {
        await activeHandle?.pause()
    }

    func performTeardown() async {
        playedToEndWatchTask?.cancel()
        playedToEndWatchTask = nil
        activeHandle = nil
        activeIndex = nil
        await prefetch.cancelAll()
        await pool.drain(keepPlayers: true)
    }

    func performSettle(at index: Int, startType: PlaybackStartType, now: Date) async -> SettleOutcome {
        guard items.indices.contains(index) else { return .none }
        if index == activeIndex, activeHandle != nil || notifiedLockedIndex == index {
            return .none // idempotent: aynı kartta tekrar settle / çift kilit tetiği yok
        }
        guard let episode = items[index].episode else {
            // Bölüm taşımayan kart (seriesPromo): oynatma durur, indeks ilerler. Aktif indeks
            // GERÇEKTEN değiştiyse VC delegate'e nil bölüm bildirir (04 §2.4); re-settle idempotent.
            let alreadySettledHere = (index == activeIndex)
            await pauseAndDetachActive()
            activeIndex = index
            notifiedLockedIndex = nil
            return alreadySettledHere ? .none : .settledWithoutEpisode
        }

        let context = SettleContext(
            index: index,
            direction: (activeIndex ?? (index - 1)) <= index ? .forward : .backward,
            startType: startType,
            resumePosition: FeedResumePolicy.resumePosition(for: items[index]),
            now: now
        )
        let direction = context.direction
        let resumePosition = context.resumePosition
        await recordSettleIntent(for: episode, context: context)

        do {
            let handle = try await pool.activate(episode, atFeedIndex: index, resumePosition: resumePosition)
            activeHandle = handle
            activeIndex = index
            notifiedLockedIndex = nil
            suppressNextAutoAdvance = false
            // Kilitli karttan mute'lanmış olabilecek slot bu bölümde açılır (02 §4.3.7).
            await handle.engine.setMuted(false)
            watchPlayedToEnd(of: handle)
            await refreshWindow(direction: direction, now: now)
            return .activated(handle, episode)
        } catch let error as AppError {
            await metrics.recordPlaybackFailure(for: episode.id)
            await pauseAndDetachActive()
            activeIndex = index
            if case .content(.episodeLocked) = error {
                notifiedLockedIndex = index
                return .locked(episode)
            }
            return .failed(error, episode)
        } catch {
            // İptal (drain/recycle araya girdi — 03 §7.3): gürültüsüz çıkış.
            await metrics.recordPlaybackFailure(for: episode.id)
            return .none
        }
    }

    /// Settle bağlamı: performSettle → ölçüm yardımcısına taşınan değerler.
    struct SettleContext: Sendable {
        let index: Int
        let direction: ScrollDirection
        let startType: PlaybackStartType
        let resumePosition: Double?
        let now: Date
    }

    /// TTFF niyeti işareti (04 §13, 08 §4). Devam kaydı varsa start_type `resume`a çevrilir.
    /// Swipe gecikmesi t0'ı burada DEĞİL, `recordSwipeIntent`'te (willEndDragging) kaydedilir.
    func recordSettleIntent(for episode: Episode, context: SettleContext) async {
        let effectiveStartType: PlaybackStartType =
            context.resumePosition != nil && context.startType != .autoAdvance
                ? .resume
                : context.startType
        await metrics.recordPlaybackIntent(
            for: episode,
            startType: effectiveStartType,
            resumePosition: context.resumePosition,
            at: context.now
        )
    }

    /// Swipe niyeti kaydı (t0 = willEndDragging): kaynak = aktif bölüm, hedef = paging
    /// indeksi. `watch_pct_at_swipe` yalnız ileri yönde, gerçek pozisyondan (02 §4.3.7).
    func performRecordSwipeIntent(toIndex: Int, at now: Date) async {
        guard let fromIndex = activeIndex, fromIndex != toIndex,
              items.indices.contains(fromIndex), items.indices.contains(toIndex),
              let fromEpisode = items[fromIndex].episode,
              let toEpisode = items[toIndex].episode
        else { return }
        let direction: ScrollDirection = toIndex > fromIndex ? .forward : .backward
        let watchPercentage = direction == .forward ? await watchPercentageOfActive(episode: fromEpisode) : nil
        await metrics.recordSwipeSettled(
            from: fromEpisode.id,
            to: toEpisode.id,
            direction: direction,
            watchPercentageAtSwipe: watchPercentage,
            at: now
        )
    }

    /// Aktif bölümün izlenme oranı [0,1] (swipe anı): handle pozisyonu / süre.
    func watchPercentageOfActive(episode: Episode) async -> Double? {
        guard let handle = activeHandle, episode.durationSec > 0 else { return nil }
        let position = await handle.engine.currentPositionSeconds()
        return min(max(position / Double(episode.durationSec), 0), 1)
    }

    /// Pencere kayması (04 §3.2, §6.4 kural 4): aktif ± komşular korunur, pencere dışı
    /// slot'lar boşaltılır, prefetch hedefleri yön farkındalığıyla yenilenir.
    func refreshWindow(direction: ScrollDirection, now: Date) async {
        guard let activeIndex else { return }
        let poolSize = await poolSizeProvider()
        let desired = PoolWindowPlanner.desiredIndexes(
            activeIndex: activeIndex,
            direction: direction,
            poolSize: poolSize,
            episodeCount: items.count
        )
        if let lower = desired.min(), let upper = desired.max() {
            await pool.recycle(keeping: lower ... upper)
        }
        await prefetch.windowChanged(
            activeIndex: activeIndex,
            episodes: alignedEpisodes(),
            direction: direction,
            at: now
        )
    }

    /// FeedItem → Episode hizalaması: bölüm taşımayan kartlar (seriesPromo) kilitli
    /// sayılan yer tutucuyla temsil edilir — ısındırılamaz, indeks kayması olmaz.
    func alignedEpisodes() -> [Episode] {
        items.map { item in
            item.episode ?? Episode(
                id: EpisodeID("feed-item-\(item.id)"),
                seriesId: item.series.id,
                index: 0,
                title: nil,
                durationSec: 0,
                thumbnailURL: item.series.coverURL,
                access: EpisodeAccess(kind: .locked, unlockPrice: nil, adUnlockEligible: false),
                publishedAt: nil
            )
        }
    }

    func pauseAndDetachActive() async {
        playedToEndWatchTask?.cancel()
        playedToEndWatchTask = nil
        // Kilitli/bölümsüz karta geçişte ses sızıntısı yok (02 §4.3.7): mute+pause garanti.
        await activeHandle?.engine.setMuted(true)
        await activeHandle?.pause()
        activeHandle = nil
    }

    /// Aktif bölümün sonu (04 §8.6): motorun playedToEnd akışı dinlenir; karar SAF
    /// politikadan çıkar. İzleme görevi her aktivasyonda yenilenir — bayat item'ın
    /// bitişi yanlış auto-next tetikleyemez (04 §14 T4'ün feed karşılığı).
    func watchPlayedToEnd(of handle: PlaybackHandle) {
        playedToEndWatchTask?.cancel()
        let engine = handle.engine
        playedToEndWatchTask = Task { [weak self] in
            for await _ in await engine.playedToEndEvents() {
                guard let self, !Task.isCancelled else { return }
                await handlePlaybackEnded()
            }
        }
    }

    func handlePlaybackEnded() {
        if suppressNextAutoAdvance {
            suppressNextAutoAdvance = false
            return
        }
        let decision = AutoAdvancePolicy.decision(
            activeIndex: activeIndex,
            itemCount: items.count,
            isAutoAdvanceEnabled: isAutoAdvanceEnabled
        )
        autoAdvanceContinuation.yield(decision)
    }

    /// Operasyon serileştirme: yeni iş kuyruktaki son işin bitişini bekler — havuz çağrı
    /// blokları (activate → recycle → prefetch) atomik sırayla koşar.
    func serialized<T: Sendable>(_ operation: @escaping @Sendable () async -> T) async -> T {
        let previous = tail
        let task = Task { () -> T in
            await previous?.value
            return await operation()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }
}
