import AppFoundation
import Foundation

/// Tek bir player slot'unun motoru (PlayerKit-internal): sahip olduğu `VideoPlaying`
/// backend'ini durum makinesiyle sürer, durum akışını yayınlar ve imzalı URL
/// kurtarma politikasını (04 §6.4) uygular.
///
/// Actor'dür: play/pause/seek ve runtime olayları farklı bağlamlardan gelir; tüm
/// mutasyonlar serileşir (03 §7 concurrency kanonu).
actor PlaybackEngine {
    /// PlayerKit-internal görünürlük: feed hücresi görüntü yüzeyini (AVPlayerLayer)
    /// backend'in surface kaynağından bağlar (04 §3.3 kural 4); AVFoundation public
    /// API'ye sızmaz — erişim modül içinde kalır.
    let backend: any VideoPlaying
    /// Taze imzalı URL kancası (SS-051 çekirdeği): kurtarma anında çağrılır.
    private let freshURLProvider: (@Sendable (EpisodeID) async throws -> URL)?

    private var machine = PlayerStateMachine()
    private let broadcast = StateBroadcast<PlayerEngineState>(initial: .idle)

    private(set) var episodeID: EpisodeID?
    private var currentURL: URL?
    private var playbackRate: Double = 1.0
    /// Loading sırasında gelen play niyeti; ilk karede uygulanır (04 §4.2 playImmediately).
    private var pendingPlay = false
    /// Son uygulanan buffer politikası — slot rolünün engine'deki izi (04 §4.1):
    /// `.active` = aktif slot, `.idle` = warm/idle. Kurtarma bu role göre davranır.
    private var currentBufferPolicy: BufferPolicy = .idle
    /// Devam Et pozisyonu; ilk kareden hemen sonra seek edilir (04 §12.2).
    private var pendingResumePosition: Double?
    private var recoveryAttempts = 0
    private var eventPumpTask: Task<Void, Never>?
    /// Jenerasyon korkuluğu: her prepare/reset +1. Backend olayları yüklemenin
    /// jenerasyonunu taşır; eşleşmeyen olay sessizce düşer.
    private var generation: UInt64 = 0
    /// Bölüm sonu olay aboneleri (04 §8.6): auto-next kararı feed katmanınındır;
    /// motor yalnız playedToEnd'i duyurur. State akışından ayrıdır — playedToEnd
    /// durum olarak `paused` görünür (actionAtItemEnd = .pause).
    private var playedToEndContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(
        backend: any VideoPlaying,
        freshURLProvider: (@Sendable (EpisodeID) async throws -> URL)? = nil
    ) {
        self.backend = backend
        self.freshURLProvider = freshURLProvider
    }

    deinit {
        eventPumpTask?.cancel()
        broadcast.finish()
        for continuation in playedToEndContinuations.values {
            continuation.finish()
        }
    }

    // MARK: - Yaşam döngüsü

    /// Yeni bölüm hazırla: önce reset, sonra yükleme. Kurtarma hakkı sıfırlanır.
    func prepare(
        episodeID: EpisodeID,
        url: URL,
        bufferPolicy: BufferPolicy,
        resumePosition: Double? = nil
    ) async {
        startEventPumpIfNeeded()
        generation &+= 1
        let loadGeneration = generation
        if machine.state != .idle {
            await backend.clearItem()
            apply(.resetRequested)
        }
        self.episodeID = episodeID
        currentURL = url
        currentBufferPolicy = bufferPolicy
        pendingPlay = false
        pendingResumePosition = resumePosition
        recoveryAttempts = 0
        apply(.loadRequested)
        await backend.load(url: url, bufferPolicy: bufferPolicy, generation: loadGeneration)
    }

    /// Item'ı bırakır, player'ı korur (04 §3.3 drain kuralı).
    func reset() async {
        generation &+= 1
        pendingPlay = false
        pendingResumePosition = nil
        episodeID = nil
        currentURL = nil
        await backend.clearItem()
        apply(.resetRequested)
    }

    // MARK: - Kontrol yüzeyi

    func play() async {
        switch machine.state {
        case .readyAtFirstFrame, .paused:
            await backend.playImmediately(atRate: playbackRate)
            apply(.playRequested)
        case .loading:
            pendingPlay = true // ilk karede uygulanır
        case .idle, .playing, .stalled, .failed:
            break
        }
    }

    func pause() async {
        // Backend'e her zaman iletilir: loading sırasında demote edilen player'ın
        // bekleyen play niyeti de düşer (havuz demote yolu — 04 §4.1).
        pendingPlay = false
        await backend.pause()
        apply(.pauseRequested)
    }

    func seek(toSeconds seconds: Double) async {
        await backend.seek(toSeconds: seconds)
    }

    /// Toleranslı seek (04 §8.1 çift-tap): keskin `.zero` yalnız `seek(toSeconds:)`
    /// (scrubber bırakışı/resume). Feed jest katmanı ±10 sn için bunu çağırır.
    func seekTolerant(toSeconds seconds: Double) async {
        await backend.seek(toSeconds: seconds, tolerant: true)
    }

    /// Kilitli bölüme geçişte önceki player'ın mute'u (02 §4.3.7).
    func setMuted(_ muted: Bool) async {
        await backend.setMuted(muted)
    }

    /// 2x/hız menüsünde ton koruması (04 §8.1, 01 PLR-03).
    func setPitchPreservation(_ enabled: Bool) async {
        await backend.setPitchPreservation(enabled)
    }

    func setRate(_ rate: Double) async {
        playbackRate = rate
        if machine.state == .playing {
            await backend.setRate(rate)
        }
    }

    func applyBufferPolicy(_ policy: BufferPolicy) async {
        currentBufferPolicy = policy
        await backend.applyBufferPolicy(policy)
    }

    /// Bitrate tavanı (04 §6.3): havuz, hazırlık/aktivasyon anında ağ durumuna göre
    /// hesaplanan tavanı buradan uygular; backend değeri item değişimlerinde korur.
    func setPeakBitRateCap(_ bitsPerSecond: Double?) async {
        await backend.setPeakBitRateCap(bitsPerSecond)
    }

    // MARK: - Durum akışı

    func currentState() -> PlayerEngineState {
        machine.state
    }

    func statusUpdates() -> AsyncStream<PlayerEngineState> {
        broadcast.stream()
    }

    /// Bölüm sonu olay akışı (04 §8.6): her playedToEnd için bir eleman. Feed
    /// katmanı auto-advance kararını buradan tetikler; durum akışında bu an
    /// yalnız `paused` göründüğünden ayrı bir kanaldır.
    func playedToEndEvents() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            playedToEndContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removePlayedToEndContinuation(id) }
            }
        }
    }

    /// Anlık oynatma konumu (feed jest katmanı ±10 sn hedef kırpması için — 04 §8.1).
    func currentPositionSeconds() async -> Double {
        await backend.currentPositionSeconds()
    }

    private func removePlayedToEndContinuation(_ id: UUID) {
        playedToEndContinuations[id] = nil
    }

    // MARK: - Runtime olayları

    private func startEventPumpIfNeeded() {
        guard eventPumpTask == nil else { return }
        eventPumpTask = Task { [weak self, backend] in
            for await tagged in backend.runtimeEvents {
                guard let self else { return }
                await handleRuntimeEvent(tagged)
            }
        }
    }

    private func handleRuntimeEvent(_ tagged: TaggedRuntimeEvent) async {
        // Jenerasyon korkuluğu: olay, işlendiği anda güncel yüklemeye ait değilse
        // (araya prepare/reset girdi — AsyncStream buffer'ı ya da KVO köprüsü
        // gecikmesi) SESSİZCE düşer. Bayat didFail yeni bölümde kurtarma tetikleyemez,
        // bayat firstFrame yeni item'ın durumunu/pending niyetlerini tüketemez.
        guard tagged.generation == generation else { return }
        switch tagged.event {
        case .firstFrameReady:
            apply(.firstFrameReady)
            if let position = pendingResumePosition {
                pendingResumePosition = nil
                await backend.seek(toSeconds: position)
            }
            if pendingPlay {
                pendingPlay = false
                await backend.playImmediately(atRate: playbackRate)
                apply(.playRequested)
            }
        case .stallBegan:
            apply(.stallBegan)
        case .stallEnded:
            apply(.stallEnded)
        case .playedToEnd:
            // actionAtItemEnd = .pause: auto-next feed katmanının kararıdır (04 §8.6).
            apply(.pauseRequested)
            for continuation in playedToEndContinuations.values {
                continuation.yield()
            }
        case let .didFail(error):
            await handleFailure(error)
        }
    }

    /// 04 §6.4 kurtarma akışı: konum kaydet → taze imzalı URL → yeni yükleme →
    /// seek → (rol aktifse) playImmediately. Kullanıcı yalnız spinner (loading)
    /// görür; ikinci ardışık hata yüzeye çıkar (SignedURLRecoveryPolicy).
    ///
    /// İki korkuluk:
    /// - Jenerasyon: await'lerden dönüşte jenerasyon değiştiyse (araya reset/recycle
    ///   ya da yeni prepare girdi) kurtarma İPTAL edilir — boşaltılmış slot diriltilmez.
    /// - Rol: aktif slot pendingPlay=true + `.active` ile kaldığı yerden oynar; warm
    ///   slot pendingPlay=false + `.idle` ile ısınmış bekler — gizli otomatik oynatma yok.
    private func handleFailure(_ error: AppError) async {
        let action = SignedURLRecoveryPolicy.action(for: error, attempt: recoveryAttempts)
        guard action == .refreshAndResume,
              let freshURLProvider,
              let episodeID
        else {
            apply(.didFail(error))
            return
        }
        recoveryAttempts += 1
        apply(.recoveryStarted)
        let recoveryGeneration = generation
        let savedPosition = await backend.currentPositionSeconds()
        guard generation == recoveryGeneration else { return }
        do {
            let freshURL = try await freshURLProvider(episodeID)
            guard generation == recoveryGeneration else { return }
            currentURL = freshURL
            pendingResumePosition = savedPosition > 0 ? savedPosition : nil
            pendingPlay = currentBufferPolicy == .active
            generation &+= 1
            await backend.load(url: freshURL, bufferPolicy: currentBufferPolicy, generation: generation)
        } catch {
            guard generation == recoveryGeneration else { return }
            apply(.didFail(error as? AppError ?? .playback(.signedURLExpired)))
        }
    }

    private func apply(_ event: PlayerEngineEvent) {
        guard machine.handle(event) else { return }
        broadcast.send(machine.state)
    }
}
