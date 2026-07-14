import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// Kilit açma akışı (SS-095): optimistic düşüm + server-otoritatif mutabakat + rollback +
/// çakışma durumları.
struct WalletStoreUnlockTests {
    private func makeStore(
        remote: FakeWalletRemote,
        seed: WalletSnapshot? = .fixture(purchased: 100, version: 1)
    ) async -> WalletStore {
        let store = WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
        if let seed {
            await store.apply(walletSnapshot: seed)
        }
        return store
    }

    @Test func basariliUnlockKanonikUnlockCoinAnalitigiAtar() async {
        // 08 §3.4/§5.2: backend onay noktasında kanonik `unlock_coin` (non-canonical `unlock_success`
        // DEĞİL) — series_id/episode_id/unlock_price/earned_spent/purchased_spent/balance_after.
        let remote = FakeWalletRemote()
        let analytics = MockAnalytics()
        let transactions = [
            CoinTransaction(
                id: "txn_e", type: .episodeUnlock, amount: -20, bucket: .earned,
                balanceAfter: 80, refId: "ep_9", note: nil, createdAt: Date(timeIntervalSince1970: 1)
            ),
            CoinTransaction(
                id: "txn_p", type: .episodeUnlock, amount: -40, bucket: .purchased,
                balanceAfter: 40, refId: "ep_9", note: nil, createdAt: Date(timeIntervalSince1970: 2)
            )
        ]
        remote.unlockResults = [.success(.unlocked(
            record: UnlockRecord(
                id: "ulk_9",
                episodeID: EpisodeID("ep_9"),
                seriesID: SeriesID("srs_7"),
                method: .coins,
                coinsSpent: 60,
                unlockedAt: Date(timeIntervalSince1970: 3)
            ),
            wallet: .fixture(purchased: 40, version: 2),
            transactions: transactions
        ))]
        let store = WalletStore(remote: remote, analytics: analytics, log: MockLogger())
        await store.apply(walletSnapshot: .fixture(purchased: 100, version: 1))

        _ = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        let event = analytics.events.first { $0.name == "unlock_coin" }
        #expect(event?.parameters["series_id"] == .string("srs_7"))
        #expect(event?.parameters["episode_id"] == .string("ep_9"))
        #expect(event?.parameters["unlock_price"] == .int(60))
        #expect(event?.parameters["earned_spent"] == .int(20))
        #expect(event?.parameters["purchased_spent"] == .int(40))
        #expect(event?.parameters["balance_after"] == .int(40))
        #expect(!analytics.eventNames.contains("unlock_success"))
    }

    @Test func basariliUnlockServerSnapshotUygular() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_9", coinsSpent: 60),
            wallet: .fixture(purchased: 40, version: 2),
            transactions: []
        ))]
        let store = await makeStore(remote: remote)

        let result = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        #expect(result == .success(.fixture(episode: "ep_9", coinsSpent: 60)))
        let balance = await store.currentBalance()
        #expect(balance == CoinBalance(purchasedCoins: 40, earnedCoins: 0))
        let unlocked = await store.isEpisodeUnlocked(EpisodeID("ep_9"))
        #expect(unlocked)
    }

    @Test func unlockSirasindaBalanceBroadcastYalnizServerSnapshotiYayinlar() async {
        // Kanon §5 / 05 §5.2 / 06 §2.4 kural 3: istemci bakiyeyi ASLA lokal aritmetikle
        // güncellemez. unlock() lokal-düşülmüş ARA DEĞER yayınlamamalı; balanceBroadcast'e
        // yalnız SUNUCU snapshot'ı düşmeli. Server bakiyesi (55) lokal düşümden (100−60=40) FARKLI
        // seçildi: hatalı yol 40'ı yayınlardı; doğru yol yalnız (replay 100 →) 55 yayınlar, 40 ASLA.
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_9", coinsSpent: 60),
            wallet: .fixture(purchased: 55, version: 2),
            transactions: []
        ))]
        let store = await makeStore(remote: remote) // seed 100/v1
        var iterator = store.balanceUpdates().makeAsyncIterator()

        // Current-value semantiği: geç abone mevcut (seed) bakiyeyi replay alır → 100.
        let seeded = await iterator.next()
        #expect(seeded == CoinBalance(purchasedCoins: 100, earnedCoins: 0))

        _ = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        // Sonraki (ve tek yeni) bakiye yayını SERVER snapshot'ı olmalı; lokal-düşülmüş 40 ASLA yayınlanmaz.
        let afterUnlock = await iterator.next()
        #expect(afterUnlock == CoinBalance(purchasedCoins: 55, earnedCoins: 0))
    }

    @Test func gecAboneMevcutBakiyeyiReplayAlir() async {
        // SS-097 current-value: send-then-subscribe. Bakiye subscribe'dan ÖNCE güncellenir; geç abone
        // KAYIT ANINDA mevcut bakiyeyi replay almalı (aksi halde UI kalıcı bayat kalırdı).
        let store = await makeStore(remote: FakeWalletRemote(), seed: nil)
        await store.apply(walletSnapshot: .fixture(purchased: 250, version: 3)) // abone YOKKEN send

        var iterator = store.balanceUpdates().makeAsyncIterator() // geç abone
        let replayed = await iterator.next()

        #expect(replayed == CoinBalance(purchasedCoins: 250, earnedCoins: 0))
    }

    @Test func agHatasindaOptimistikDusumGeriAlinir() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.failure(.network(.offline))]
        let store = await makeStore(remote: remote)

        let result = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        #expect(result == .failed(.network(.offline)))
        // Rollback: optimistic 40 → geri 100.
        let balance = await store.currentBalance()
        #expect(balance == CoinBalance(purchasedCoins: 100, earnedCoins: 0))
        let unlocked = await store.isEpisodeUnlocked(EpisodeID("ep_9"))
        #expect(!unlocked)
    }

    @Test func bakiyeYetersizServerReddiTipliDoner() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.insufficientCoins(shortfall: 30, wallet: nil))]
        // Bakiye 30 < 60 → optimistic düşüm YAPILMAZ (covered değil).
        let store = await makeStore(remote: remote, seed: .fixture(purchased: 30, version: 1))

        let result = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        #expect(result == .insufficientCoins(shortfall: 30))
        let balance = await store.currentBalance()
        #expect(balance == CoinBalance(purchasedCoins: 30, earnedCoins: 0))
    }

    @Test func fiyatDegistiRollbackVeTipliSonuc() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.priceChanged(currentPrice: 75))]
        let store = await makeStore(remote: remote)

        let result = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        #expect(result == .priceChanged(currentPrice: 75))
        let balance = await store.currentBalance()
        #expect(balance == CoinBalance(purchasedCoins: 100, earnedCoins: 0)) // optimistic geri alındı
    }

    @Test func idempotentUnlockCiftIstekTekUcret() async {
        // Server idempotent: aynı bölüm iki kez → aynı 200 snapshot (çift düşüm YOK, 05 §4.5).
        let remote = FakeWalletRemote()
        let serverWallet = WalletSnapshot.fixture(purchased: 40, version: 2)
        remote.unlockResults = [
            .success(.unlocked(record: .fixture(episode: "ep_9"), wallet: serverWallet, transactions: [])),
            .success(.unlocked(record: .fixture(episode: "ep_9"), wallet: serverWallet, transactions: []))
        ]
        let store = await makeStore(remote: remote)

        _ = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)
        _ = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        // SET semantiği: iki kez 40 uygulandı → hâlâ 40 (2x düşüm ile −20 DEĞİL).
        let balance = await store.currentBalance()
        #expect(balance == CoinBalance(purchasedCoins: 40, earnedCoins: 0))
    }

    @Test func ayniAndaIkinciUnlockCakismaDoner() async {
        // 06 §6.4: aynı anda en fazla 1 bekleyen unlock.
        let remote = FakeWalletRemote()
        let gate = AsyncGate()
        remote.unlockGate = { await gate.wait() }
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_9"),
            wallet: .fixture(purchased: 40, version: 2),
            transactions: []
        ))]
        let store = await makeStore(remote: remote)

        async let first = store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)
        // İkincisi ilk askıdayken çalışır → çakışma.
        var secondResult: UnlockResult = .failed(.unexpected(underlying: "unset"))
        // İlk isteğin remote'a ulaşıp askıya alınmasını bekle.
        while remote.unlockCallCount < 1 {
            await Task.yield()
        }
        secondResult = await store.unlock(episodeID: EpisodeID("ep_10"), expectedPrice: 60)
        await gate.open()
        let firstResult = await first

        #expect(secondResult == .failed(.wallet(.transactionConflict)))
        #expect(firstResult == .success(.fixture(episode: "ep_9")))
        #expect(remote.unlockCallCount == 1) // ikinci istek remote'a hiç gitmedi
    }
}
