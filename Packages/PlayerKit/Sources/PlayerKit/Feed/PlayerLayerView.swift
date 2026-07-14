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

    /// Bağlama jenerasyonu (bulgu 8): her bind/unbind +1. `isReadyForDisplay` KVO→Task
    /// köprüsündeki sinyal, PLANLANDIĞI jenerasyonu taşır — unbind→rebind sonrası bayat
    /// Task, yeni episode'un `onFirstFrameReady`'sini ERKEN ateşleyemez (poster erken
    /// gizlenmez, sahte hızlı TTFF yok). AVPlayerBackend'in `currentLoadGeneration`
    /// korkuluğunun hücre-layer düzeyindeki birebir karşılığı.
    private(set) var bindGeneration: UInt64 = 0

    private var playerLayer: AVPlayerLayer? {
        layer as? AVPlayerLayer
    }

    /// Test gözlemi / reconfigure kararı (PlayerKit-internal): layer bir player'a bağlı mı.
    var isBoundToPlayer: Bool {
        playerLayer?.player != nil
    }

    func bind(player: AVPlayer) {
        guard let playerLayer else { return }
        detachObservation()
        bindGeneration &+= 1
        let generation = bindGeneration
        hasSignaledFirstFrame = false
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.player = player
        // T5: blok tabanlı KVO, token görünüm yaşam döngüsüne bağlı; unbind invalidate eder.
        // Sinyal, planlandığı bind jenerasyonunu taşır (bulgu 8): KVO callback'i ile
        // Task'in MainActor'a varması arasında unbind→rebind olursa bayat Task düşürülür.
        readyObservation = playerLayer.observe(
            \.isReadyForDisplay,
            options: [.initial, .new]
        ) { [weak self] observedLayer, _ in
            guard observedLayer.isReadyForDisplay else { return }
            Task { @MainActor in
                self?.signalFirstFrameIfNeeded(generation: generation)
            }
        }
    }

    func unbind() {
        detachObservation()
        playerLayer?.player = nil // T8: yalnız bağlantı çözülür; player havuzda yaşar
        hasSignaledFirstFrame = false
        bindGeneration &+= 1 // uçuştaki bayat first-frame Task'ini geçersizle (bulgu 8)
    }

    private func detachObservation() {
        readyObservation?.invalidate()
        readyObservation = nil
    }

    /// İlk-kare sinyali (bulgu 8): jenerasyon korkuluğu — planlandığı bind hâlâ geçerli
    /// değilse (araya unbind/rebind girdiyse) sinyal düşürülür. PlayerKit-internal
    /// (test bayat sinyali deterministik basar).
    func signalFirstFrameIfNeeded(generation: UInt64) {
        guard generation == bindGeneration else { return }
        guard !hasSignaledFirstFrame else { return }
        hasSignaledFirstFrame = true
        onFirstFrameReady?()
    }
}
