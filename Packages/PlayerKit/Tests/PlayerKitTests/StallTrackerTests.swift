import Testing
@testable import PlayerKit

/// Buffer-stall durum makinesi (04 §6.x): playbackStalled bildirimi ilk kez stall'ı işaretler
/// (çift stallBegan olmaz), isPlaybackLikelyToKeepUp true'ya dönünce temizlenir, load/pause sıfırlar.
/// AVPlayerBackend bu saf mantığı taşır (KVO/NotificationCenter tarafı gerçek player'da; mantık burada
/// deterministik test edilir). Audit LOW (bug 70): pause reset etmediğinden bayrak takılı kalıp
/// duraklat-devam et sonrası sonraki GERÇEK stall'ın stallBegan'ını yutuyordu.
struct StallTrackerTests {
    @Test func ilkStallBildirimiStallBeganEmitEder() {
        var tracker = StallTracker()
        #expect(tracker.markStalled() == true)
        #expect(tracker.isStalled)
    }

    @Test func zatenStalldaykenTekrarBildirimStallBeganEmitETMEZ() {
        var tracker = StallTracker()
        _ = tracker.markStalled()
        #expect(tracker.markStalled() == false) // çift stallBegan yok
        #expect(tracker.isStalled)
    }

    @Test func keepUpTrueStallEndedEmitEderVeTemizler() {
        var tracker = StallTracker()
        _ = tracker.markStalled()
        #expect(tracker.markKeepUp(true) == true)
        #expect(!tracker.isStalled)
    }

    @Test func stallYokkenKeepUpTrueStallEndedEmitETMEZ() {
        var tracker = StallTracker()
        #expect(tracker.markKeepUp(true) == false) // stall yoktu → sahte stallEnded yok
        #expect(!tracker.isStalled)
    }

    @Test func keepUpFalseStallEndedEmitETMEZ() {
        var tracker = StallTracker()
        _ = tracker.markStalled()
        #expect(tracker.markKeepUp(false) == false) // hâlâ keep-up değil
        #expect(tracker.isStalled)
    }

    @Test func pauseSonrasiSonrakiGercekStallYineSinyallenir() {
        // Bug 70 çekirdeği: stall → pause(reset) → yeni stall BASTIRILMAZ. reset olmadan bayrak
        // takılı kalıp ikinci markStalled false döner (stallBegan yutulur → buffering gösterilmez).
        var tracker = StallTracker()
        #expect(tracker.markStalled() == true) // stall#1
        tracker.reset() // pause veya yeni load
        #expect(tracker.markStalled() == true) // stall#2 YİNE sinyallenir
    }

    @Test func resetStallDurumunuTemizler() {
        var tracker = StallTracker()
        _ = tracker.markStalled()
        tracker.reset()
        #expect(!tracker.isStalled)
    }
}
