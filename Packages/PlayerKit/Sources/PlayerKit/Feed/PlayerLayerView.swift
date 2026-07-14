import AVFoundation
import UIKit

/// AVPlayer görüntü kaynağı köprüsü (PlayerKit-internal): hücre, aktif lease'in
/// backend'inden player'ı bu protokolle alır. AVFoundation tipi modül İÇİNDE
/// kalır; public API'ye sızmaz (04 §2.4 kural 1).
@MainActor
protocol AVPlayerSurfaceSource: AnyObject {
    var surfacePlayer: AVPlayer? { get }
}

/// AVPlayerLayer host görünümü (PlayerKit-internal). Hücre yeniden kullanımında
/// yalnız layer bağlantısı çözülür; player yaşam döngüsü havuzdadır (04 §14 T8).
@MainActor
final class PlayerLayerView: UIView {
    // UIView.layerClass class var override'ı static olamaz.
    // swiftlint:disable:next static_over_final_class
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    /// Gerçek ilk-kare sinyali (04 §13 normatif tanım): backend'in yaklaşık
    /// `readyToPlay` sinyali görüntü katmanında `isReadyForDisplay` ile doğrulanır;
    /// TTFF ölçümü ve poster→video geçişi bu geri çağrıya bağlanır.
    var onFirstFrameReady: (() -> Void)?

    private var readyObservation: NSKeyValueObservation?
    private var hasSignaledFirstFrame = false

    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    func bind(player: AVPlayer) {
        guard let playerLayer else { return }
        detachObservation()
        hasSignaledFirstFrame = false
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = player
        // T5: blok tabanlı KVO, token görünüm yaşam döngüsüne bağlı; unbind invalidate eder.
        readyObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self] observedLayer, _ in
            guard observedLayer.isReadyForDisplay else { return }
            Task { @MainActor in
                self?.signalFirstFrameIfNeeded()
            }
        }
    }

    func unbind() {
        detachObservation()
        playerLayer?.player = nil // T8: yalnız bağlantı çözülür; player havuzda yaşar
        hasSignaledFirstFrame = false
    }

    private func detachObservation() {
        readyObservation?.invalidate()
        readyObservation = nil
    }

    private func signalFirstFrameIfNeeded() {
        guard !hasSignaledFirstFrame else { return }
        hasSignaledFirstFrame = true
        onFirstFrameReady?()
    }
}
