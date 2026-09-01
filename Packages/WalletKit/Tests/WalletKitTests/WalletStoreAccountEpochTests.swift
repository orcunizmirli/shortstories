import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// SS-132/§575 (audit HIGH): hesap-değişimi `reset()`'i UÇUŞTAKİ server yanıtlarını FENCE etmeli.
/// reset() yalnız version-guard'ı sıfırlar; bir account-epoch olmadan, X hesabının in-flight
/// unlock/refresh/credit yanıtı reset SONRASI çözülünce Y hesabının freshly-reset store'una
/// X'in bakiyesini + açılmış bölümlerini SIZDIRIYORDU (cross-account leak). Epoch guard bunu keser:
/// await ÖNCESİ yakalanan epoch, apply ÖNCESİ eşleşmezse yanıt DÜŞÜRÜLÜR.
struct WalletStoreAccountEpochTests {
    private func makeStore(_ remote: FakeWalletRemote = FakeWalletRemote()) -> WalletStore {
        WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
    }

    /// Gated çağrının kapıya ulaşmasını (spy sayacı artana dek) bekler — deterministik.
    private func waitUntil(_ condition: @Sendable () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            await Task.yield()
        }
    }

    @Test func inFlightUnlockDroppedAfterAccountSwitch() async {
        let remote = FakeWalletRemote()
        let gate = AsyncGate()
        remote.unlockGate = { await gate.wait() }
        // X hesabının unlock yanıtı: yüksek-version, 200 coin, ep_A açık.
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_A", coinsSpent: 60),
            wallet: .fixture(purchased: 200, version: 87),
            transactions: []
        ))]
        let store = makeStore(remote)

        let unlockTask = Task { await store.unlock(episodeID: EpisodeID("ep_A"), expectedPrice: 60, idempotencyKey: "k1") }
        await waitUntil { remote.unlockCallCount == 1 } // unlock kapıda asılı (epoch yakalandı)

        // Hesap değişimi: reset (epoch bump) + Y hesabının snapshot'ı.
        await store.reset()
        await store.apply(walletSnapshot: .fixture(purchased: 50, version: 3))

        await gate.open() // X'in unlock yanıtı şimdi çözülür
        _ = await unlockTask.value

        // X'in 200 coin'i + ep_A kilidi Y'ye SIZMAMALI.
        #expect(await store.currentBalance() == CoinBalance(purchasedCoins: 50, earnedCoins: 0))
        #expect(await store.isEpisodeUnlocked(EpisodeID("ep_A")) == false)
    }

    @Test func inFlightRefreshDroppedAfterAccountSwitch() async {
        let remote = FakeWalletRemote()
        let gate = AsyncGate()
        remote.fetchWalletGate = { await gate.wait() }
        remote.walletResult = .success(.fixture(purchased: 500, version: 30)) // X hesabı

        let store = makeStore(remote)
        let refreshTask = Task { await store.refresh() }
        await waitUntil { remote.fetchWalletCount == 1 } // fetchWallet kapıda (epoch yakalandı)

        await store.reset()
        await store.apply(walletSnapshot: .fixture(purchased: 20, version: 1)) // Y hesabı

        await gate.open()
        await refreshTask.value

        // X'in 500 coin refresh yanıtı Y'ye SIZMAMALI.
        #expect(await store.currentBalance() == CoinBalance(purchasedCoins: 20, earnedCoins: 0))
    }

    @Test func applyIfCurrentEpochDropsStaleCredit() async {
        let store = makeStore()
        let staleEpoch = await store.currentEpoch()
        await store.apply(walletSnapshot: .fixture(purchased: 50, version: 3))
        await store.reset() // epoch değişir
        await store.apply(walletSnapshot: .fixture(purchased: 20, version: 1)) // Y güncel

        // X hesabında (staleEpoch) yakalanan geç gelen kredi:
        await store.applyIfCurrentEpoch(walletSnapshot: .fixture(purchased: 999, version: 87), epoch: staleEpoch)
        #expect(await store.currentBalance() == CoinBalance(purchasedCoins: 20, earnedCoins: 0))
    }

    @Test func applyIfCurrentEpochAppliesWhenEpochMatches() async {
        let store = makeStore()
        let epoch = await store.currentEpoch()
        await store.applyIfCurrentEpoch(walletSnapshot: .fixture(purchased: 120, version: 5), epoch: epoch)
        #expect(await store.currentBalance() == CoinBalance(purchasedCoins: 120, earnedCoins: 0))
    }

    @Test func applyIfCurrentEpochDropsStaleSubscription() async {
        let store = makeStore()
        let staleEpoch = await store.currentEpoch()
        await store.reset()
        // X hesabının geç gelen VIP'i Y'ye entitlement sızdırmamalı.
        await store.applyIfCurrentEpoch(subscription: .vip(), epoch: staleEpoch)
        #expect(await store.subscriptionStatus().grantsFullAccess == false)
    }

    /// Reklam-unlock cross-actor server await'ini (UnlockSheetModel ad-watch, ≈30 sn + SSV) AŞAR:
    /// reklam izlerken hesap değişirse (session-death → reset) geç gelen ad-unlock ONAYI ÖNCEKİ
    /// hesabın bölümünü yeni hesabın `unlockedEpisodes`'ine sızdırmamalı (§575; unlock() ile simetrik).
    @Test func adUnlockConfirmDroppedAfterAccountSwitch() async {
        let store = makeStore()
        let staleEpoch = await store.currentEpoch()
        await store.reset() // hesap değişimi: epoch bump + unlockedEpisodes temizlenir
        let applied = await store.confirmAdUnlock(episodeID: EpisodeID("ep_A"), ifCurrentEpoch: staleEpoch)
        #expect(applied == false) // bayat epoch → onay düşürüldü
        #expect(await store.isEpisodeUnlocked(EpisodeID("ep_A")) == false) // Y'ye sızmadı
    }

    @Test func adUnlockConfirmAppliesWhenEpochMatches() async {
        let store = makeStore()
        let epoch = await store.currentEpoch()
        let applied = await store.confirmAdUnlock(episodeID: EpisodeID("ep_A"), ifCurrentEpoch: epoch)
        #expect(applied == true) // güncel epoch → uygulandı
        #expect(await store.isEpisodeUnlocked(EpisodeID("ep_A")) == true)
    }
}
