import Foundation

/// Jest bölgeleri (01 PLR-02, 02 §4.3.3): sol %40 geri seek, orta %20 yalnız tek
/// dokunma, sağ %40 ileri seek. SAF harita — UIKit jest katmanı yalnız çevirir.
enum FeedGestureZone: Sendable, Equatable {
    case left
    case center
    case right

    /// Sol bölgenin bittiği oran.
    static let leftFraction = 0.4
    /// Sağ bölgenin başladığı oran.
    static let rightFraction = 0.6

    static func zone(forNormalizedX x: Double) -> FeedGestureZone {
        let clamped = min(max(x, 0), 1)
        if clamped < leftFraction {
            return .left
        }
        if clamped < rightFraction {
            return .center
        }
        return .right
    }

    /// Bölgenin çift-tap seek yönü; orta bölgede seek yoktur.
    var seekOffsetSeconds: Double? {
        switch self {
        case .left:
            -FeedTapInterpreter.seekOffsetSeconds
        case .center:
            nil
        case .right:
            FeedTapInterpreter.seekOffsetSeconds
        }
    }
}

/// Tap yorumlayıcının ürettiği aksiyonlar. `revertToggleAndSeek`, tek tap'in ANINDA
/// uygulanmış play/pause etkisinin geri alınıp seek'e çevrilmesidir (04 §8 kanonik
/// tanıma stratejisi — 250 ms bekleme YAPILMAZ).
enum FeedTapAction: Sendable, Equatable {
    case togglePlayPause
    case revertToggleAndSeek(offsetSeconds: Double)
    case seek(offsetSeconds: Double)
}

/// Tek/çift tap tanıma stratejisinin SAF durum makinesi (04 §8, 02 §4.3.3):
/// - İlk tap play/pause'u ANINDA uygular (bekleme yok).
/// - 250 ms içinde sol/sağ bölgede ikinci tap gelirse toggle geri alınır, ±10 sn
///   seek uygulanır (algılanan gecikme sıfır — TikTok kalıbı).
/// - Seek zincirinde kalan ardışık tap'ler toggle'sız ek seek üretir (birikme).
/// - Orta %20 bölge çift tap tanımaz: her tap tek tap davranışıdır.
struct FeedTapInterpreter: Sendable {
    static let doubleTapWindowSeconds: Double = 0.25
    static let seekOffsetSeconds: Double = 10

    private enum Phase {
        case idle
        /// Tek tap etkisi uygulandı; pencere içinde seek bölgesi tap'i geri alabilir.
        case singleApplied(Date)
        /// Çift tap seek'i uygulandı; pencere içindeki tap'ler seek biriktirir.
        case seeking(Date)
    }

    private var phase: Phase = .idle

    mutating func handleTap(normalizedX: Double, at now: Date) -> FeedTapAction {
        let zone = FeedGestureZone.zone(forNormalizedX: normalizedX)
        switch phase {
        case .idle:
            phase = .singleApplied(now)
            return .togglePlayPause
        case let .singleApplied(lastTap):
            guard isWithinWindow(since: lastTap, now: now), let offset = zone.seekOffsetSeconds else {
                phase = .singleApplied(now)
                return .togglePlayPause
            }
            phase = .seeking(now)
            return .revertToggleAndSeek(offsetSeconds: offset)
        case let .seeking(lastTap):
            guard isWithinWindow(since: lastTap, now: now), let offset = zone.seekOffsetSeconds else {
                phase = .singleApplied(now)
                return .togglePlayPause
            }
            phase = .seeking(now)
            return .seek(offsetSeconds: offset)
        }
    }

    private func isWithinWindow(since lastTap: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastTap) <= Self.doubleTapWindowSeconds
    }
}

/// Seek hedefi kırpma (04 §8.1 edge case'leri): bölüm sonuna < 10 sn kala sona,
/// başa < 10 sn kala 0'a. Sona kırpılan seek auto-advance TETİKLEMEZ — bastırma
/// kararı `FeedPlaybackDirector`'dadır.
enum FeedSeekPolicy {
    static func targetSeconds(current: Double, offsetSeconds: Double, durationSeconds: Double) -> Double {
        min(max(current + offsetSeconds, 0), max(durationSeconds, 0))
    }
}

/// Uzun basma hızı (04 §8.1, 01 PLR-03): basılı tutulduğu sürece 2x; bırakınca
/// önceki hıza dönülür. Eşik 400 ms (öncesinde bırakılırsa tek tap); 2x sırasında
/// ton korunur (`.timeDomain`) ve dikey kaydırma başlarsa 2x iptal edilir.
enum FeedHoldSpeedPolicy {
    static let holdRate: Double = 2.0
    /// Uzun basma eşiği (01 PLR-03 kabul kriteri): UIKit varsayılanı 0.5 s DEĞİL.
    static let minimumPressDurationSeconds: Double = 0.4
}
