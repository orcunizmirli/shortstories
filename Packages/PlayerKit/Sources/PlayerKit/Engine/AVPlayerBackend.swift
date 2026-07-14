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
    @MainActor private var isLikelyStalled = false
    /// Güncel yüklemenin jenerasyonu: KVO→Task köprüsünde geciken bayat görev,
    /// yakaladığı jenerasyon bununla eşleşmiyorsa sinyal ÜRETMEZ (jenerasyon korkuluğu).
    @MainActor private var currentLoadGeneration: UInt64 = 0
    /// Aktif bitrate tavanı (04 §6.3): item değişse de korunur; 0 = tavansız.
    @MainActor private var peakBitRateCap: Double?

    init() {
        (runtimeEvents, eventContinuation) = AsyncStream.makeStream()
    }

    deinit {
        eventContinuation.finish()
    }

    func load(url: URL, bufferPolicy: BufferPolicy, generation: UInt64) async {
        await MainActor.run {
            let player = ensurePlayer()
            removeItemObservers()
            currentLoadGeneration = generation
            hasSignaledFirstFrame = false
            isLikelyStalled = false

            // T2: senkron property okuması yok; item AVURLAsset'ten yaratılır, anahtar
            // yüklemesi AVFoundation'ın kendi async hattında ilerler.
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = bufferPolicy.preferredForwardBufferSeconds
            // Tavan yeni item'da da korunur (04 §6.3): kurtarma yeniden yüklemesi
            // dahil her yükleme aynı preferredPeakBitRate ile başlar.
            item.preferredPeakBitRate = peakBitRateCap ?? 0
            player.replaceCurrentItem(with: item)
            installItemObservers(player: player, item: item, generation: generation)
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
        }
    }

    func seek(toSeconds seconds: Double) async {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        await MainActor.run {
            guard let player else { return }
            // T9: ardışık seek'lerde öncekiler iptal edilir; seek asenkron ve toleranssızdır.
            player.currentItem?.cancelPendingSeeks()
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
        }
    }

    func setRate(_ rate: Double) async {
        await MainActor.run {
            player?.rate = Float(rate)
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
                if observedItem.isPlaybackLikelyToKeepUp, self.isLikelyStalled {
                    self.isLikelyStalled = false
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
                guard !self.isLikelyStalled else { return }
                self.isLikelyStalled = true
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
