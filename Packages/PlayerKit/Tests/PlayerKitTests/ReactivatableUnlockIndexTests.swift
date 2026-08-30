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
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(newItems: items, lockedEpisodeID: items[3].episode?.id) == 3)
    }

    @Test func lockedEpisodeIDNilIseNil() {
        let items = Fixture.feedItems(count: 5, lockedIndexes: [])
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(newItems: items, lockedEpisodeID: nil) == nil)
    }

    @Test func aktifKartHalaKilitliyseNil() {
        let items = Fixture.feedItems(count: 5, lockedIndexes: [3]) // 3 hâlâ kilitli
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(newItems: items, lockedEpisodeID: items[3].episode?.id) == nil)
    }

    @Test func feedYenidenSiralanincaKilitliBolumYeniKonumundanReaktiveEdilir() {
        // Bulgu #3: kilitliyken feed yeniden sıralanırsa (promo insert/For-You refresh) pozisyonel raw index
        // YANLIŞ komşu kartı reaktive ederdi. Kimlik-tabanlı: kilitli bölümün id'si yeni listede bulunur →
        // YENİ konumu döner. e1 başta index 1'de; yeniden sıralamada index 2'ye kayar → 2 dönmeli (1 DEĞİL).
        let items = Fixture.feedItems(count: 3, lockedIndexes: []) // e0/e1/e2 hepsi oynatılabilir
        let reordered = [items[2], items[0], items[1]] // e1 artık index 2'de
        #expect(PlayerFeedViewController
            .reactivatableUnlockIndex(newItems: reordered, lockedEpisodeID: items[1].episode?.id) == 2)
    }

    @Test func kilitliBolumFeeddenKaldirilirsaNil() {
        // Kilitli bölüm yeni listede yoksa (dedup/kaldırma) reaktivasyon dispatch edilmez.
        let items = Fixture.feedItems(count: 3, lockedIndexes: [])
        let without1 = [items[0], items[2]]
        #expect(PlayerFeedViewController
            .reactivatableUnlockIndex(newItems: without1, lockedEpisodeID: items[1].episode?.id) == nil)
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
