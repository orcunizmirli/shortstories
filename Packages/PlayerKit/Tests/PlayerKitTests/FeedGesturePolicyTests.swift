import Foundation
import Testing
@testable import PlayerKit

// MARK: - Bölge haritası (01 PLR-02: sol %40 / orta %20 / sağ %40)

@Suite("FeedGestureZone — bölge oranları")
struct FeedGestureZoneTests {
    @Test("Sol %40: x < 0.4 sol bölgedir")
    func leftZone() {
        #expect(FeedGestureZone.zone(forNormalizedX: 0.0) == .left)
        #expect(FeedGestureZone.zone(forNormalizedX: 0.39) == .left)
    }

    @Test("Orta %20: 0.4 ≤ x < 0.6 orta bölgedir")
    func centerZone() {
        #expect(FeedGestureZone.zone(forNormalizedX: 0.4) == .center)
        #expect(FeedGestureZone.zone(forNormalizedX: 0.5) == .center)
        #expect(FeedGestureZone.zone(forNormalizedX: 0.59) == .center)
    }

    @Test("Sağ %40: x ≥ 0.6 sağ bölgedir")
    func rightZone() {
        #expect(FeedGestureZone.zone(forNormalizedX: 0.6) == .right)
        #expect(FeedGestureZone.zone(forNormalizedX: 1.0) == .right)
    }

    @Test("Aralık dışı girdi kırpılır")
    func clampedInput() {
        #expect(FeedGestureZone.zone(forNormalizedX: -0.5) == .left)
        #expect(FeedGestureZone.zone(forNormalizedX: 1.5) == .right)
    }
}

// MARK: - Tap yorumlayıcı (04 §8: 250 ms bekleme YAPILMAZ; tek tap anında uygulanır)

@Suite("FeedTapInterpreter — tek/çift tap stratejisi")
struct FeedTapInterpreterTests {
    private let t0 = Date(timeIntervalSince1970: 1000)

    @Test("İlk tap ANINDA play/pause uygular (bekleme yok)")
    func singleTapAppliesImmediately() {
        var interpreter = FeedTapInterpreter()
        let action = interpreter.handleTap(normalizedX: 0.5, at: t0)
        #expect(action == .togglePlayPause)
    }

    @Test("Sağ bölgede 250 ms içinde ikinci tap: toggle geri alınır + +10 sn seek")
    func doubleTapRightRevertsAndSeeksForward() {
        var interpreter = FeedTapInterpreter()
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0)
        let action = interpreter.handleTap(normalizedX: 0.7, at: t0.addingTimeInterval(0.2))
        #expect(action == .revertToggleAndSeek(offsetSeconds: 10))
    }

    @Test("Sol bölgede 250 ms içinde ikinci tap: toggle geri alınır + −10 sn seek")
    func doubleTapLeftRevertsAndSeeksBackward() {
        var interpreter = FeedTapInterpreter()
        _ = interpreter.handleTap(normalizedX: 0.1, at: t0)
        let action = interpreter.handleTap(normalizedX: 0.2, at: t0.addingTimeInterval(0.2))
        #expect(action == .revertToggleAndSeek(offsetSeconds: -10))
    }

    @Test("Orta bölgede ikinci tap çift tap DEĞİLDİR: yeniden play/pause")
    func centerSecondTapTogglesAgain() {
        var interpreter = FeedTapInterpreter()
        _ = interpreter.handleTap(normalizedX: 0.5, at: t0)
        let action = interpreter.handleTap(normalizedX: 0.5, at: t0.addingTimeInterval(0.1))
        #expect(action == .togglePlayPause)
    }

    @Test("Pencere dışı ikinci tap yeni tek tap'tir")
    func secondTapAfterWindowIsSingle() {
        var interpreter = FeedTapInterpreter()
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0)
        let action = interpreter.handleTap(normalizedX: 0.7, at: t0.addingTimeInterval(0.3))
        #expect(action == .togglePlayPause)
    }

    @Test("Art arda çift tap'ler birikir: üçüncü tap toggle'sız ek seek üretir")
    func consecutiveSeekTapsAccumulate() {
        var interpreter = FeedTapInterpreter()
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0)
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0.addingTimeInterval(0.2))
        let third = interpreter.handleTap(normalizedX: 0.7, at: t0.addingTimeInterval(0.4))
        #expect(third == .seek(offsetSeconds: 10))
        let fourth = interpreter.handleTap(normalizedX: 0.1, at: t0.addingTimeInterval(0.6))
        #expect(fourth == .seek(offsetSeconds: -10))
    }

    @Test("Seek zincirinden sonra pencere dolarsa yeni tap tek tap'tir")
    func seekChainExpiresBackToSingle() {
        var interpreter = FeedTapInterpreter()
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0)
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0.addingTimeInterval(0.2))
        let action = interpreter.handleTap(normalizedX: 0.7, at: t0.addingTimeInterval(0.6))
        #expect(action == .togglePlayPause)
    }

    @Test("Seek zincirinde orta bölge tap'i zinciri bitirir ve toggle uygular")
    func centerTapEndsSeekChain() {
        var interpreter = FeedTapInterpreter()
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0)
        _ = interpreter.handleTap(normalizedX: 0.7, at: t0.addingTimeInterval(0.2))
        let action = interpreter.handleTap(normalizedX: 0.5, at: t0.addingTimeInterval(0.4))
        #expect(action == .togglePlayPause)
    }
}

// MARK: - Uzun basma hız politikası (01 PLR-03)

@Suite("FeedHoldSpeedPolicy — uzun basma")
struct FeedHoldSpeedPolicyTests {
    @Test("Uzun basma eşiği 400 ms (UIKit varsayılanı 0.5 s değil)")
    func minimumPressDurationIs400ms() {
        #expect(FeedHoldSpeedPolicy.minimumPressDurationSeconds == 0.4)
    }

    @Test("Basılı tutuş hızı 2x")
    func holdRateIs2x() {
        #expect(FeedHoldSpeedPolicy.holdRate == 2.0)
    }
}

// MARK: - Seek hedef kırpma (04 §8.1 edge case'leri)

@Suite("FeedSeekPolicy — hedef kırpma")
struct FeedSeekPolicyTests {
    @Test("Normal ileri seek: konum + 10")
    func forwardSeek() {
        #expect(FeedSeekPolicy.targetSeconds(current: 30, offsetSeconds: 10, durationSeconds: 90) == 40)
    }

    @Test("Bölüm sonuna < 10 sn kala ileri seek bölüm sonuna kırpılır")
    func forwardSeekClampsToEnd() {
        #expect(FeedSeekPolicy.targetSeconds(current: 85, offsetSeconds: 10, durationSeconds: 90) == 90)
    }

    @Test("Başa < 10 sn kala geri seek 0'a kırpılır")
    func backwardSeekClampsToStart() {
        #expect(FeedSeekPolicy.targetSeconds(current: 4, offsetSeconds: -10, durationSeconds: 90) == 0)
    }
}
