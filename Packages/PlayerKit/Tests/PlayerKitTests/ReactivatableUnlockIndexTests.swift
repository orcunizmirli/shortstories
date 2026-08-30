import Testing
import UIKit
@testable import PlayerKit

/// PlayerFeedViewController reaktivasyon karar katmanı (SAF+static, test hedefi):
///  - reactivatableUnlockIndex: kilitli aktif kart oynatılabilir olduysa indeksini döner.
///  - reactivateDispatchIndex (self-review4 uçuş-guard'ı): aday reaktivasyon UÇUŞTAYSA (aynı index) nil →
///    VIP çift-apply çift-video_start önlenir; uçuş bitince (handleSettleOutcome temizler) başarısız
///    (transient .failed) durumda sonraki apply retry EDER. (transition-heuristiği DEĞİL — o, başarısız
///    reaktivasyonun retry'ını yanlışça bastırıyordu, self-review4.)
@Suite("reactivatableUnlockIndex + uçuş-guard")
struct ReactivatableUnlockIndexTests {
    @Test func aktifKartOynatilabilirseIndeksDoner() {
        let items = Fixture.feedItems(count: 5, lockedIndexes: []) // 3 oynatılabilir
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(newItems: items, lockedIndex: 3) == 3)
    }

    @Test func lockedIndexNilIseNil() {
        let items = Fixture.feedItems(count: 5, lockedIndexes: [])
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(newItems: items, lockedIndex: nil) == nil)
    }

    @Test func aktifKartHalaKilitliyseNil() {
        let items = Fixture.feedItems(count: 5, lockedIndexes: [3]) // 3 hâlâ kilitli
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(newItems: items, lockedIndex: 3) == nil)
    }

    // MARK: - Uçuş-guard'ı (self-review4)

    @Test func uctaGuardAdayUctaDegilseDispatchEder() {
        // İlk reaktivasyon (uçuşta hiçbir şey yok) → dispatch.
        #expect(PlayerFeedViewController.reactivateDispatchIndex(candidate: 3, reactivatingIndex: nil) == 3)
        // Farklı kart uçuşta → yine dispatch.
        #expect(PlayerFeedViewController.reactivateDispatchIndex(candidate: 3, reactivatingIndex: 5) == 3)
    }

    @Test func uctaGuardAyniKartUctaysaBastirir() {
        // VIP çift-apply: N zaten uçuşta → ikinci dispatch bastırılır (çift video_start yok).
        #expect(PlayerFeedViewController.reactivateDispatchIndex(candidate: 3, reactivatingIndex: 3) == nil)
    }

    @Test func uctaGuardAdayNilIseNil() {
        #expect(PlayerFeedViewController.reactivateDispatchIndex(candidate: nil, reactivatingIndex: 3) == nil)
    }
}
