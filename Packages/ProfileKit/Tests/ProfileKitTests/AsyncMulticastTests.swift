import Testing
@testable import ProfileKit

@Suite("AsyncMulticast — current-value replay atomikliği")
struct AsyncMulticastTests {
    /// Regresyon (review #6): seed replay kilit DIŞINDA, kayıttan SONRA yield edilince eşzamanlı
    /// `send()` daha yeni değeri ÖNCE, bayat seed'i SONRA teslim eder → abone bayatta kalır.
    /// Kayıt anında araya bir `send(1)` sokup (enjekte edilmiş askı) abonenin SON gördüğü değerin
    /// en-yeni (1) olduğunu doğruluyoruz; kilit-içi atomik seed olmadan bu değer bayat 0 kalır.
    @Test func concurrentSendNeverLeavesStaleSeedLast() async {
        let multicast = AsyncMulticast<Int>()
        multicast.send(0) // latest = 0
        // Kayıt tamamlanır tamamlanmaz araya daha yeni bir değer sok.
        multicast.onRegisteredForTesting = { multicast.send(1) }

        var iterator = multicast.subscribe().makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()

        // Abonenin SON gördüğü değer en-yeni yayın (1) olmalı; bayat seed (0) araya sıkışmamalı.
        #expect([first, second].last == 1)
        #expect(second != 0)
    }

    /// Kontrol: hook olmadan basit replay hâlâ en-yeni değeri verir.
    @Test func lateSubscriberReplaysLatest() async {
        let multicast = AsyncMulticast<Int>()
        multicast.send(7)
        var iterator = multicast.subscribe().makeAsyncIterator()
        #expect(await iterator.next() == 7)
    }
}
