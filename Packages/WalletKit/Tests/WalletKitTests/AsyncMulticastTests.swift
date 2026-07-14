import Testing
@testable import WalletKit

/// Çok tüketicili yayın altyapısı (SS-097 entitlement yayınının temeli).
struct AsyncMulticastTests {
    @Test func abonelerGonderilenOgeyiAlir() async {
        let multicast = AsyncMulticast<Int>()
        var iterator = multicast.subscribe().makeAsyncIterator()

        multicast.send(42)

        #expect(await iterator.next() == 42)
    }

    @Test func birdenFazlaAboneAyniOgeyiAlir() async {
        let multicast = AsyncMulticast<String>()
        var first = multicast.subscribe().makeAsyncIterator()
        var second = multicast.subscribe().makeAsyncIterator()

        multicast.send("vip")

        #expect(await first.next() == "vip")
        #expect(await second.next() == "vip")
    }

    @Test func finishAllAkislariSonlandirir() async {
        let multicast = AsyncMulticast<Int>()
        var iterator = multicast.subscribe().makeAsyncIterator()

        multicast.finishAll()

        #expect(await iterator.next() == nil)
    }

    @Test func gecAboneSonDegeriReplayAlir() async {
        // Current-value semantiği: abone YOKKEN yapılan send düşmez; sonradan gelen abone KAYIT
        // ANINDA son değeri replay alır (send-then-subscribe telafisi).
        let multicast = AsyncMulticast<Int>()

        multicast.send(7) // abone yok
        var iterator = multicast.subscribe().makeAsyncIterator() // geç abone

        #expect(await iterator.next() == 7)
    }

    @Test func replaySadeceSonDegeriTutar() async {
        // Yalnız EN SON değer replay edilir (ara değerler değil).
        let multicast = AsyncMulticast<Int>()

        multicast.send(1)
        multicast.send(2)
        multicast.send(3)
        var iterator = multicast.subscribe().makeAsyncIterator()

        #expect(await iterator.next() == 3)
    }
}
