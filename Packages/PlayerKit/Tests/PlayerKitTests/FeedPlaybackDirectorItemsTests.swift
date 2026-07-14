import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

/// `FeedPlaybackDirector.updateItems` aktif indeks yeniden türetimi (bulgu 2): item
/// listesi değiştiğinde aktif indeks bölüm-id'sinden yeniden türetilir — dedup/removal/
/// refresh aktif bölümün konumunu kaydırsa bile auto-advance/metrikler doğru bölüme bağlanır.
@Suite("FeedPlaybackDirector — item güncelleme / aktif indeks")
struct DirectorItemsTests {
    @Test("updateItems aktif indeksi bölüm-id'sinden yeniden türetir (kayma sonrası)")
    func updateItemsRemapsActiveIndexByEpisodeID() async {
        // Aktif bölüm e2, indeks 2'de oynarken listeden önceki bir item düşer (dedup/
        // removal) → e2 indeks 1'e kayar. activeIndex bölüm-id'sinden yeniden türetilmeli;
        // aksi halde auto-advance kartı atlar, metrikler yanlış bölüme yazar.
        let items = Fixture.feedItems(count: 4) // e0..e3
        let harness = await makeDirector(items: items)
        _ = await harness.director.settle(at: 2, startType: .tap, now: harness.clock.now)
        #expect(await harness.director.currentActiveIndex == 2)

        let shifted = [items[0], items[2], items[3]] // e0, e2, e3 → e2 artık indeks 1'de
        await harness.director.updateItems(shifted)

        #expect(await harness.director.currentActiveIndex == 1)
    }

    @Test("updateItems: aktif bölüm listede kalıyorsa indeks korunur (append-only)")
    func updateItemsKeepsActiveIndexWhenPrefixStable() async {
        // Append-only sayfalama (sunucu sıralaması otoritatif): deduped prefix indeks-
        // kararlı; sona eklenen sayfa aktif indeksi kaydırmaz.
        let full = Fixture.feedItems(count: 5) // e0..e4
        let harness = await makeDirector(items: Array(full.prefix(3))) // e0..e2
        _ = await harness.director.settle(at: 1, startType: .tap, now: harness.clock.now)

        await harness.director.updateItems(full) // sona e3, e4 eklendi

        #expect(await harness.director.currentActiveIndex == 1)
    }
}
