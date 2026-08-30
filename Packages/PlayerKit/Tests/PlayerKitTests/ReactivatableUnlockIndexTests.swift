import Testing
import UIKit
@testable import PlayerKit

/// self-review3: PlayerFeedViewController.reactivatableUnlockIndex TRANSITION-bazlı olmalı (kilit→açık
/// GEÇİŞİNDE reactivate; her playable-apply'da değil). Aksi halde aktif kart ZATEN açıkken gelen İKİNCİ
/// feedState yazımı (ör. VIP: applyVIPUnlock diğer kartları açarken applyUnlock zaten aktif kartı açtı)
/// aktif kartı TEKRAR reactivate eder → çift video_start + playhead sıçraması (handleSettleOutcome
/// lockedIndex'i async temizlediğinden ikinci apply araya girebilir). Saf+static → doğrudan test edilir.
@Suite("reactivatableUnlockIndex transition korkuluğu")
struct ReactivatableUnlockIndexTests {
    @Test func kilitAcikGecisindeAktifIndeksDoner() {
        let previous = Fixture.feedItems(count: 5, lockedIndexes: [3]) // aktif kart (3) kilitliydi
        let updated = Fixture.feedItems(count: 5, lockedIndexes: []) // 3 artık oynatılabilir
        let index = PlayerFeedViewController.reactivatableUnlockIndex(
            newItems: updated, previousItems: previous, lockedIndex: 3
        )
        #expect(index == 3) // kilit→açık geçişi → yerinde reactivate
    }

    @Test func gecisYoksaNilDonerCiftApplyKorumasi() {
        // Aktif kart ZATEN açık (önceki apply açtı) → ikinci feedState yazımı reactivate ETMEMELİ.
        let already = Fixture.feedItems(count: 5, lockedIndexes: [])
        let index = PlayerFeedViewController.reactivatableUnlockIndex(
            newItems: already, previousItems: already, lockedIndex: 3
        )
        #expect(index == nil) // geçiş yok → çift-reactivate önlenir (fix'siz: 3 dönerdi)
    }

    @Test func lockedIndexNilIseNil() {
        let items = Fixture.feedItems(count: 5, lockedIndexes: [])
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(
            newItems: items, previousItems: items, lockedIndex: nil
        ) == nil)
    }

    @Test func aktifKartHalaKilitliyseNil() {
        let previous = Fixture.feedItems(count: 5, lockedIndexes: [3])
        let updated = Fixture.feedItems(count: 5, lockedIndexes: [3]) // 3 hâlâ kilitli
        #expect(PlayerFeedViewController.reactivatableUnlockIndex(
            newItems: updated, previousItems: previous, lockedIndex: 3
        ) == nil)
    }
}
