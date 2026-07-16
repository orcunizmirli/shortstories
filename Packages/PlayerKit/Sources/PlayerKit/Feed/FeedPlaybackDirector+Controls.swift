import ContentKit
import Foundation

/// Jest → oynatma kontrolü (04 §8.1/§8.2): tek/çift tap, ±10 sn seek, uzun basma 2x,
/// hız menüsü. `FeedPlaybackDirector` actor'ünün parçası — çağrılar aynı izolasyonda
/// serileşir; kararlar saf politikalardan (`FeedSeekPolicy`/`FeedHoldSpeedPolicy`) çıkar.
extension FeedPlaybackDirector {
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
}
