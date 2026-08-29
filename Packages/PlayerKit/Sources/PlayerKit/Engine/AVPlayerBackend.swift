import AppFoundation
@preconcurrency import AVFoundation
import Foundation

/// `VideoPlaying`'in AVFoundation canlısı — AVFoundation'a dokunan TEK oynatma
/// sınıfı (04 §2.4 modül sınırı). Tüm AVPlayer erişimi MainActor'a hop eder
/// (04 §14 T12); gözlemciler blok tabanlı KVO'dur ve item değişiminde yenilenir
/// (T3/T4/T5 tuzakları).
///
/// Bu sınıf birim testlerinde KOŞMAZ (testler sahte backend kullanır); davranış
/// doğrulaması cihaz/simülatör perf koşusundadır (SS-041/SS-052).
final class AVPlayerBackend: VideoPlaying, @unchecked Sendable {
    nonisolated let runtimeEvents: AsyncStream<TaggedRuntimeEvent>
    private let eventContinuation: AsyncStream<TaggedRuntimeEvent>.Continuation

    @MainActor private var player: AVPlayer?
    @MainActor private var statusObservation: NSKeyValueObservation?
    @MainActor private var keepUpObservation: NSKeyValueObservation?
    @MainActor private var notificationTokens: [NSObjectProtocol] = []
    @MainActor private var hasSignaledFirstFrame = false
    /// Stall karar mantığı (04 §6.x; audit LOW bug 70) — saf/test-edilebilir. load/pause reset eder.
    @MainActor private var stallTracker = StallTracker()
    /// Güncel yüklemenin jenerasyonu: KVO→Task köprüsünde geciken bayat görev,
    /// yakaladığı jenerasyon bununla eşleşmiyorsa sinyal ÜRETMEZ (jenerasyon korkuluğu).
    @MainActor private var currentLoadGeneration: UInt64 = 0
    /// Aktif bitrate tavanı (04 §6.3): item değişse de korunur; 0 = tavansız.
    @MainActor private var peakBitRateCap: Double?
    /// Altyazı tercihi portu (SS-046) — nil ise altyazı seçimi hiç yapılmaz (feature kapalı/test).
    private let subtitleProvider: (any SubtitlePreferenceProviding)?
    /// Aktif item'ın legible (altyazı) seçim grubu + saf temsili — PER-ITEM (load'da temizlenir).
    @MainActor private var legibleGroup: AVMediaSelectionGroup?
    @MainActor private var legibleOptions: [SubtitleTrackSelector.Option] = []
    /// Provider aboneliği (uzun ömürlü, per-item DEĞİL) — canlı tercih değişiminde yeniden-seçer.
    @MainActor private var subtitleObserverTask: Task<Void, Never>?

    init(subtitleProvider: (any SubtitlePreferenceProviding)? = nil) {
        self.subtitleProvider = subtitleProvider
        (runtimeEvents, eventContinuation) = AsyncStream.makeStream()
    }

    deinit {
        eventContinuation.finish()
        subtitleObserverTask?.cancel()
    }

    func load(url: URL, bufferPolicy: BufferPolicy, generation: UInt64) async {
        await MainActor.run {
            let player = ensurePlayer()
            removeItemObservers()
            currentLoadGeneration = generation
            hasSignaledFirstFrame = false
            stallTracker.reset()

            // T2: senkron property okuması yok; item AVURLAsset'ten yaratılır, anahtar
            // yüklemesi AVFoundation'ın kendi async hattında ilerler.
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = bufferPolicy.preferredForwardBufferSeconds
            // Ton koruması dayanıklı varsayılan (04 §8.1, 01 PLR-03): warm item'lar dahil
            // her yükleme timeDomain başlar; 2x/hız menüsünde "sincap sesi" olmaz.
            item.audioTimePitchAlgorithm = .timeDomain
            // Tavan yeni item'da da korunur (04 §6.3): kurtarma yeniden yüklemesi
            // dahil her yükleme aynı preferredPeakBitRate ile başlar.
            item.preferredPeakBitRate = peakBitRateCap ?? 0
            player.replaceCurrentItem(with: item)
            installItemObservers(player: player, item: item, generation: generation)
            // SS-046: tercih aboneliğini tembel başlat (ilk load'da; provider yoksa no-op). Grup yükleme
            // + track seçimi item `.readyToPlay` olunca (async) yapılır — burada senkron okuma YOK (T2).
            startSubtitleObserverIfNeeded()
        }
    }

    func playImmediately(atRate rate: Double) async {
        await MainActor.run {
            player?.playImmediately(atRate: Float(rate))
        }
    }

    func pause() async {
        await MainActor.run {
            player?.pause()
            // Duraklatılan item "stall" sayılmaz: bayrağı temizle → devam edildiğinde sonraki GERÇEK
            // buffer-stall'ın `playbackStalled`'ı bastırılmaz (audit LOW bug 70). Stall sırasında pause
            // edildiyse engine zaten `.stalled → .paused` geçer; backend bayrağı da tutarlı sıfırlanır.
            stallTracker.reset()
        }
    }

    func seek(toSeconds seconds: Double, tolerant: Bool) async {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        // Çift-tap (tolerant) hızlı segment-sınırı seek'i ister (04 §8.1); scrubber
        // bırakışı (tolerant == false) keskin `.zero` toleransta kalır (T9).
        let tolerance: CMTime = tolerant ? CMTime(seconds: 1, preferredTimescale: 600) : .zero
        await MainActor.run {
            guard let player else { return }
            // T9: ardışık seek'lerde öncekiler iptal edilir; seek asenkrondur.
            player.currentItem?.cancelPendingSeeks()
            player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { _ in }
        }
    }

    func setRate(_ rate: Double) async {
        await MainActor.run {
            player?.rate = Float(rate)
        }
    }

    func setMuted(_ muted: Bool) async {
        await MainActor.run {
            player?.isMuted = muted
        }
    }

    func setPitchPreservation(_ enabled: Bool) async {
        await MainActor.run {
            // 2x/hız menüsünde ton koruması (04 §8.1, 01 PLR-03).
            player?.currentItem?.audioTimePitchAlgorithm = enabled ? .timeDomain : .varispeed
        }
    }

    func applyBufferPolicy(_ policy: BufferPolicy) async {
        await MainActor.run {
            player?.currentItem?.preferredForwardBufferDuration = policy.preferredForwardBufferSeconds
        }
    }

    func setPeakBitRateCap(_ bitsPerSecond: Double?) async {
        await MainActor.run {
            peakBitRateCap = bitsPerSecond
            // Mevcut item'da YERİNDE uygulanır (yeni item yaratılmaz); 0 = tavansız.
            player?.currentItem?.preferredPeakBitRate = bitsPerSecond ?? 0
        }
    }

    func currentPositionSeconds() async -> Double {
        await MainActor.run {
            guard let time = player?.currentTime(), time.isNumeric else { return 0 }
            return time.seconds
        }
    }

    func clearItem() async {
        await MainActor.run {
            removeItemObservers()
            // T1/T8: item bırakılır, player instance'ı korunur.
            player?.replaceCurrentItem(with: nil)
        }
    }

    // MARK: - Kurulum (MainActor)

    @MainActor
    private func ensurePlayer() -> AVPlayer {
        if let player {
            return player
        }
        let player = AVPlayer()
        // T10: HLS'de bayrak true kalır; anında başlatma playImmediately iledir (04 §4.2).
        player.automaticallyWaitsToMinimizeStalling = true
        // Auto-next'i feed katmanı yönetir (04 §8.6).
        player.actionAtItemEnd = .pause
        self.player = player
        return player
    }

    @MainActor
    private func installItemObservers(player: AVPlayer, item: AVPlayerItem, generation: UInt64) {
        installStatusObserver(item: item, generation: generation)
        installKeepUpObserver(item: item, generation: generation)
        installNotificationObservers(item: item, generation: generation)
    }

    @MainActor
    private func installStatusObserver(item: AVPlayerItem, generation: UInt64) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            guard let self else { return }
            switch observedItem.status {
            case .readyToPlay:
                // Faz 1 yaklaşık ilk-kare sinyali; görüntü katmanı doğrulaması
                // (AVPlayerLayer.isReadyForDisplay) feed hücresinde tamamlanır (08 §4 notu).
                // Sinyal, PLANLANDIĞI yükleme jenerasyonunu taşır: Task MainActor'a
                // varana dek yeni bir load gelirse bayat sinyal üretilmez/etkimez.
                Task { @MainActor in
                    self.signalFirstFrameIfNeeded(generation: generation)
                }
                // SS-046: item hazır → legible seçim grubu artık yüklenebilir; tercih edilen altyazıyı seç.
                loadLegibleGroupAndApply(item: observedItem, generation: generation)
            case .failed:
                eventContinuation.yield(TaggedRuntimeEvent(
                    generation: generation,
                    event: .didFail(Self.mapItemError(observedItem.error))
                ))
            default:
                break
            }
        }
    }

    @MainActor
    private func installKeepUpObserver(item: AVPlayerItem, generation: UInt64) {
        keepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observedItem, _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.currentLoadGeneration == generation else { return } // bayat item sinyali
                if self.stallTracker.markKeepUp(observedItem.isPlaybackLikelyToKeepUp) {
                    self.eventContinuation.yield(TaggedRuntimeEvent(generation: generation, event: .stallEnded))
                }
            }
        }
    }

    @MainActor
    private func installNotificationObservers(item: AVPlayerItem, generation: UInt64) {
        // T4: bildirimler HER ZAMAN object filtreli.
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVPlayerItem.playbackStalledNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.currentLoadGeneration == generation else { return } // bayat item sinyali
                guard self.stallTracker.markStalled() else { return } // zaten stall'da → çift stallBegan yok
                self.eventContinuation.yield(TaggedRuntimeEvent(generation: generation, event: .stallBegan))
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.eventContinuation.yield(TaggedRuntimeEvent(generation: generation, event: .playedToEnd))
        })
    }

    @MainActor
    private func signalFirstFrameIfNeeded(generation: UInt64) {
        // Jenerasyon korkuluğu: KVO callback'i ile bu Task'in koşması arasında yeni
        // bir load geldiyse (hasSignaledFirstFrame sıfırlanmış olsa da) bayat görev
        // yeni item adına ilk-kare sinyali BASAMAZ ve bayrağı kirletemez.
        guard generation == currentLoadGeneration else { return }
        guard !hasSignaledFirstFrame else { return }
        hasSignaledFirstFrame = true
        eventContinuation.yield(TaggedRuntimeEvent(generation: generation, event: .firstFrameReady))
    }

    @MainActor
    private func removeItemObservers() {
        // T5: KVO token'ları invalidate edilir; hayalet callback kalmaz.
        statusObservation?.invalidate()
        statusObservation = nil
        keepUpObservation?.invalidate()
        keepUpObservation = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        // SS-046: legible önbelleği PER-ITEM'dir → yeni item eski grubun `options[index]`'ini kullanmasın
        // (yanlış track / crash). Provider aboneliği uzun ömürlüdür, burada iptal edilmez (yalnız deinit).
        legibleGroup = nil
        legibleOptions = []
    }

    /// Feed hücresinin görüntü yüzeyi bağlaması (04 §3.3 kural 4): AVPlayerLayer,
    /// lease üzerinden bu kaynaktan bağlanır; AVFoundation modül içinde kalır.
    @MainActor var surfacePlayer: AVPlayer? {
        player
    }

    /// AVFoundation hatasını katman sınırı tipine çevirir (03 §10.1): 403/410 imzalı
    /// URL vakaları `signedURLExpired`; diğer medya hataları `assetUnavailable`.
    private static func mapItemError(_ error: Error?) -> AppError {
        guard let nsError = error as NSError? else {
            return .playback(.assetUnavailable)
        }
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return .network(.offline)
            case NSURLErrorTimedOut:
                return .network(.timeout)
            default:
                break
            }
        }
        // CDN 403/410 AVFoundation'dan ayrıştırılamadığında da kurtarma politikası
        // assetUnavailable'ı 1 kez taze URL ile dener (04 §6.4 kural 5).
        return .playback(.assetUnavailable)
    }
}

// MARK: - Görüntü yüzeyi kaynağı (feed hücresi)

extension AVPlayerBackend: AVPlayerSurfaceSource {}

// MARK: - Altyazı track seçimi (SS-046) — aynı dosyada extension (private erişim + class-body bütçesi)

extension AVPlayerBackend {
    /// Provider tercih değişimlerini dinler (uzun ömürlü, tek sefer başlar); her değişimde GÜNCEL item'a
    /// yeniden uygular. Stream replay'lidir → abone anında mevcut değerle başlar (item hazırsa uygulanır).
    @MainActor
    func startSubtitleObserverIfNeeded() {
        guard subtitleObserverTask == nil, let provider = subtitleProvider else { return }
        subtitleObserverTask = Task { @MainActor [weak self] in
            for await _ in provider.subtitleCodeUpdates() {
                guard let self else { return }
                applySubtitleSelection(generation: currentLoadGeneration)
            }
        }
    }

    /// Item `.readyToPlay` olunca legible seçim grubunu ASYNC yükler (T2: senkron değil), saf temsile
    /// indirir ve tercihi uygular. Jenerasyon korkuluğu: await'ten dönünce yeni load geldiyse çıkar.
    @MainActor
    func loadLegibleGroupAndApply(item: AVPlayerItem, generation: UInt64) {
        guard subtitleProvider != nil, let asset = item.asset as? AVURLAsset else { return }
        Task { @MainActor [weak self] in
            let group = try? await asset.loadMediaSelectionGroup(for: .legible)
            guard let self, currentLoadGeneration == generation, let group else { return }
            legibleGroup = group
            legibleOptions = group.options.enumerated().map { index, option in
                SubtitleTrackSelector.Option(
                    index: index,
                    languageTag: option.extendedLanguageTag ?? option.locale?.identifier
                )
            }
            applySubtitleSelection(generation: generation)
        }
    }

    /// Güncel tercihi (senkron getter = otorite) yüklü gruba uygular. Grup/item yoksa veya jenerasyon
    /// eskiyse no-op. Zaten seçili option seçiliyse tekrar seçmez (gereksiz re-buffer önlenir).
    @MainActor
    func applySubtitleSelection(generation: UInt64) {
        guard currentLoadGeneration == generation,
              let group = legibleGroup,
              let item = player?.currentItem
        else { return }
        let decision = SubtitleTrackSelector.decide(
            preferredCode: subtitleProvider.flatMap(\.currentSubtitleCode),
            available: legibleOptions
        )
        let current = item.currentMediaSelection.selectedMediaOption(in: group)
        switch decision {
        case .off:
            guard current != nil, group.allowsEmptySelection else { return }
            item.select(nil, in: group)
        case let .select(index):
            let target = group.options[index]
            guard current != target else { return } // zaten seçili
            item.select(target, in: group)
        }
    }
}
