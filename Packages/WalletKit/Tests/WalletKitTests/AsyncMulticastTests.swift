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

    @Test func seedEsZamanliSendIleAboneyiBayatBirakmaz() async {
        // MEDIUM (WalletKit adversarial hunt): seed KİLİT DIŞINDA yield edilirse, kayıt→seed-yield penceresinde
        // araya giren send() aboneyi [V_new, V_old] sırasıyla besler → abone bayat V_old'da kalır (versiyonsuz
        // display yüzeyleri: profil özeti, CoinShop/UnlockSheet bakiye, VIP bayrağı). BehaviorSubject monotonluğu:
        // bir abone gördüğü değerden ESKİsini ASLA görmemeli. Yarışı zorla (çok abone × burst send); her abonenin
        // dizisi non-decreasing olmalı — seed sıra-bozması olsaydı düşüş görünürdü. Sentinel: geç abone askıda
        // kalmaz (son değer sentinel'se hemen çıkar).
        let end = Int.max
        for _ in 0 ..< 20 {
            let multicast = AsyncMulticast<Int>()
            multicast.send(0)

            let sequences = await withTaskGroup(of: [Int].self, returning: [[Int]].self) { group in
                group.addTask {
                    for value in 1 ... 200 {
                        multicast.send(value)
                    }
                    multicast.send(end)
                    return []
                }
                for _ in 0 ..< 100 {
                    group.addTask {
                        var values: [Int] = []
                        for await value in multicast.subscribe() {
                            if value == end {
                                break
                            }
                            values.append(value)
                        }
                        return values
                    }
                }
                var all: [[Int]] = []
                for await sequence in group where !sequence.isEmpty {
                    all.append(sequence)
                }
                return all
            }

            for sequence in sequences {
                for (earlier, later) in zip(sequence, sequence.dropFirst()) {
                    #expect(earlier <= later, "abone eskiyen değer gördü (seed sıra-bozması): \(sequence)")
                }
            }
        }
    }
}
