import Testing
@testable import PlayerKit

/// `StateBroadcast` stale-seed-last sertleştirmesi (AppFoundation primitif hunt'ı): seed kilit ALTINDA yield
/// edilmeli — WalletKit/ProfileKit `AsyncMulticast` ve `SessionStateBroadcaster` ile aynı seam invariantı.
@Suite("StateBroadcast — stale-seed-last korumasi")
struct StateBroadcastTests {
    @Test func concurrentSendNeverLeavesStaleSeedLast() async {
        // Deterministik regresyon (sibling AsyncMulticast ile aynı): seed kilit DIŞINDA yield edilirse, kayıt-sonrası
        // pencerede araya giren send(1) aboneyi [1, 0] sırasıyla besler → abonenin SON gördüğü değer bayat 0 kalır.
        // Kilit-içi atomik seed ile SON değer en-yeni (1) olmalı.
        let broadcast = StateBroadcast<Int>(initial: 0) // latest = 0
        broadcast.onRegisteredForTesting = { broadcast.send(1) } // kayıt biter bitmez araya daha yeni değer sok

        var iterator = broadcast.stream().makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        #expect([first, second].last == 1) // SON gördüğü en-yeni yayın (1); bayat seed (0) araya sıkışmamalı
        #expect(second != 0)
    }

    @Test func newSubscriberGetsCurrentValueAsSeed() async {
        let broadcast = StateBroadcast<Int>(initial: 7)
        broadcast.send(42) // latest = 42

        var iterator = broadcast.stream().makeAsyncIterator()
        #expect(await iterator.next() == 42) // seed = en güncel değer (initial değil)
    }
}
