import AppFoundation
import ContentKit
import Foundation

/// `video_start.start_type` değerleri (08 §3.2 kataloğu).
enum PlaybackStartType: String, Sendable {
    case autoAdvance = "auto_advance"
    case swipe
    case tap
    case resume
}

/// Player performans metriklerinin toplayıcısı (PlayerKit-internal; 04 §13.1, 08 §4).
///
/// İki katmanlı tanıma uygun: bu API player-teknolojisi-BAĞIMSIZDIR — girdiler yalnız
/// işaretleyici zaman damgalarıdır (oynatma niyeti, ilk kare, stall başı/sonu, swipe
/// settle). AVFoundation kaynakları (`status`, access log) bu işaretleri feed/backend
/// katmanında üretir; player teknolojisi değişirse yalnız üretici değişir.
///
/// Ayrı performans event'i YOKTUR (08 §4): metrikler taşıyıcı event parametresi olarak
/// akar — `ttff_ms` → `video_start`, `swipe_latency_ms` → `swipe_next`/`swipe_prev`,
/// stall → `video_stall` (≥ 250 ms eşiği, stall bitince gönderilir).
actor PlayerMetricsCollector {
    /// Stall raporlama eşiği (08 §3.2: ≥ 250 ms).
    static let stallReportThresholdSeconds: Double = 0.25

    /// Bekleyen TTFF niyeti tavanı (metrik hijyeni): terk edilen başlangıçlar
    /// uzun oturumda sınırsız birikmez; tavan aşımında en eski niyet düşer.
    static let maxPendingIntents = 16

    /// Niyet tazelik penceresi: bu süreyi aşan niyet TTFF ölçümüne katılmaz —
    /// başarısız/terk edilmiş bir başlangıcın t0'ı sonraki ölçümü zehirlemez.
    static let intentExpirySeconds: Double = 60

    private struct PendingIntent {
        let timestamp: Date
        let startType: PlaybackStartType
        let resumePosition: Double?
        let isUnlockedByEntitlement: Bool
    }

    private struct PendingSwipe {
        let fromEpisodeID: EpisodeID
        let toEpisodeID: EpisodeID
        let direction: ScrollDirection
        let watchPercentageAtSwipe: Double?
        let settledAt: Date
    }

    private struct ActiveStall {
        let episode: Episode
        let positionSeconds: Double
        let networkType: String
        let beganAt: Date
    }

    private let analytics: any AnalyticsTracking
    private var intents: [EpisodeID: PendingIntent] = [:]
    /// Bekleyen swipe ölçümleri HEDEF bölüm-id anahtarlı (bulgu 10): ardışık swipe'ta
    /// (A→B, B→C) önceki B→C ile EZİLMEZ; her hedef ilk kareye ulaşınca kendi
    /// swipe_next'i basılır — yavaş render eden swipe'lar p90'dan sistematik düşmez.
    private var pendingSwipes: [EpisodeID: PendingSwipe] = [:]
    private var activeStall: ActiveStall?

    init(analytics: any AnalyticsTracking) {
        self.analytics = analytics
    }

    // MARK: - TTFF (t0 = oynatma niyeti, t1 = ilk kare; 08 §4 normatif tanım)

    /// Oynatma niyeti işareti: Splash'ta feed yanıtı / swipe-settle / tap.
    /// Niyet zaman damgası feed katmanından gelir (08 §4 implementasyon notu).
    /// `isUnlockedByEntitlement`: kilitli bölüm entitlement'la (VIP / daha önce
    /// açılmış) oynatılıyorsa true — `is_locked_content` hesabına katılır (08 §3.2).
    func recordPlaybackIntent(
        for episode: Episode,
        startType: PlaybackStartType,
        resumePosition: Double? = nil,
        isUnlockedByEntitlement: Bool = false,
        at timestamp: Date
    ) {
        pruneExpiredIntents(asOf: timestamp)
        intents[episode.id] = PendingIntent(
            timestamp: timestamp,
            startType: startType,
            resumePosition: resumePosition,
            isUnlockedByEntitlement: isUnlockedByEntitlement
        )
        enforcePendingIntentCap()
    }

    /// Oynatma başarısızlık işareti: bölümün bekleyen TTFF niyeti VE hedefi bu bölüm
    /// olan bekleyen swipe ölçümü düşürülür (bulgu 9) — ilk kareye ulaşamayan
    /// başlangıcın t0'ı, aynı bölümün sonraki (ör. unlock sonrası) başarılı başlangıcında
    /// saçma ttff_ms / swipe_latency_ms üretemez (metrik hijyeni).
    func recordPlaybackFailure(for episodeID: EpisodeID) {
        intents[episodeID] = nil
        pendingSwipes[episodeID] = nil
    }

    /// İlk kare işareti: `video_start` basılır (ttff_ms ile); bekleyen swipe ölçümü
    /// bu bölüme aitse `swipe_next`/`swipe_prev` de burada tamamlanır.
    /// Tazelik penceresini aşmış niyet ölçüme katılmaz — event basılmaz, niyet düşer.
    func recordFirstFrame(for episode: Episode, at timestamp: Date) {
        if let intent = intents.removeValue(forKey: episode.id), isFresh(intent.timestamp, at: timestamp) {
            let ttffMs = milliseconds(from: intent.timestamp, to: timestamp)
            var parameters: [String: AnalyticsValue] = [
                "series_id": .string(episode.seriesId.rawValue),
                "episode_id": .string(episode.id.rawValue),
                "episode_number": .int(episode.index),
                "is_locked_content": .bool(episode.access.kind == .unlocked || intent.isUnlockedByEntitlement),
                "start_type": .string(intent.startType.rawValue),
                "ttff_ms": .int(ttffMs)
            ]
            if let resumePosition = intent.resumePosition {
                parameters["resume_position_s"] = .int(Int(resumePosition))
            }
            analytics.track("video_start", parameters: parameters)
        }

        // Tazelik penceresini aşmış swipe (ör. kilitli hedef unlock sonrası ~15-30 sn'de
        // ilk kareye ulaşırsa) ölçüme KATILMAZ (bulgu 9): removeValue düşürür, event basılmaz.
        if let swipe = pendingSwipes.removeValue(forKey: episode.id), isFresh(swipe.settledAt, at: timestamp) {
            let latencyMs = milliseconds(from: swipe.settledAt, to: timestamp)
            var parameters: [String: AnalyticsValue] = [
                "from_episode_id": .string(swipe.fromEpisodeID.rawValue),
                "to_episode_id": .string(swipe.toEpisodeID.rawValue),
                "swipe_latency_ms": .int(latencyMs)
            ]
            if swipe.direction == .forward, let watchPct = swipe.watchPercentageAtSwipe {
                parameters["watch_pct_at_swipe"] = .double(watchPct)
            }
            analytics.track(swipe.direction == .forward ? "swipe_next" : "swipe_prev", parameters: parameters)
        }
    }

    // MARK: - Swipe gecikmesi (t0 = paging hedef hücreye kilitlendi; 08 §4)

    func recordSwipeSettled(
        from fromEpisodeID: EpisodeID,
        to toEpisodeID: EpisodeID,
        direction: ScrollDirection,
        watchPercentageAtSwipe: Double? = nil,
        at timestamp: Date
    ) {
        pruneExpiredSwipes(asOf: timestamp)
        pendingSwipes[toEpisodeID] = PendingSwipe(
            fromEpisodeID: fromEpisodeID,
            toEpisodeID: toEpisodeID,
            direction: direction,
            watchPercentageAtSwipe: watchPercentageAtSwipe,
            settledAt: timestamp
        )
        enforcePendingSwipeCap()
    }

    // MARK: - Stall (04 §13.1; event stall BİTİNCE gönderilir)

    func recordStallBegan(
        for episode: Episode,
        positionSeconds: Double,
        networkType: String,
        at timestamp: Date
    ) {
        activeStall = ActiveStall(
            episode: episode,
            positionSeconds: positionSeconds,
            networkType: networkType,
            beganAt: timestamp
        )
    }

    func recordStallEnded(at timestamp: Date) {
        guard let stall = activeStall else { return }
        activeStall = nil
        let duration = timestamp.timeIntervalSince(stall.beganAt)
        guard duration >= Self.stallReportThresholdSeconds else { return }
        analytics.track("video_stall", parameters: [
            "series_id": .string(stall.episode.seriesId.rawValue),
            "episode_id": .string(stall.episode.id.rawValue),
            "stall_duration_ms": .int(Int((duration * 1000).rounded())),
            "position_s": .int(Int(stall.positionSeconds)),
            "network_type": .string(stall.networkType)
        ])
    }

    private func milliseconds(from start: Date, to end: Date) -> Int {
        Int((end.timeIntervalSince(start) * 1000).rounded())
    }

    /// Tazelik penceresini aşan niyetler düşer: uzun oturumda terk edilen
    /// başlangıçlar sözlükte birikmez.
    private func pruneExpiredIntents(asOf now: Date) {
        intents = intents.filter { now.timeIntervalSince($0.value.timestamp) <= Self.intentExpirySeconds }
    }

    /// Tazelik penceresini aşan bekleyen swipe'lar düşer (bulgu 9): hedefi geç/hiç
    /// first-frame'e ulaşan swipe'ın t0'ı sonraki ölçümü zehirlemez, sözlükte birikmez.
    private func pruneExpiredSwipes(asOf now: Date) {
        pendingSwipes = pendingSwipes.filter { now.timeIntervalSince($0.value.settledAt) <= Self.intentExpirySeconds }
    }

    private func isFresh(_ startedAt: Date, at timestamp: Date) -> Bool {
        timestamp.timeIntervalSince(startedAt) <= Self.intentExpirySeconds
    }

    /// Üst sınır: tavan aşıldığında EN ESKİ niyet düşer (bellek + ölçüm hijyeni).
    private func enforcePendingIntentCap() {
        while intents.count > Self.maxPendingIntents {
            guard let oldest = intents.min(by: { $0.value.timestamp < $1.value.timestamp })?.key else { return }
            intents[oldest] = nil
        }
    }

    /// Üst sınır (bulgu 9/10): tavan aşıldığında EN ESKİ bekleyen swipe düşer.
    private func enforcePendingSwipeCap() {
        while pendingSwipes.count > Self.maxPendingIntents {
            guard let oldest = pendingSwipes.min(by: { $0.value.settledAt < $1.value.settledAt })?.key else { return }
            pendingSwipes[oldest] = nil
        }
    }
}
