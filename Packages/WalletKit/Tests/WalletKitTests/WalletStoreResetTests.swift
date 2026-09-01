import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// SS-132/§575: hesap-değişiminde `WalletStore.reset()` önceki hesabın cüzdan state'ini SIFIRLAR —
/// bakiye/VIP/açılmış-bölüm yeni hesaba SIZMAZ; monoton version-guard da sıfırlanır (yeni hesabın
/// düşük-version snapshot'ı reset sonrası TAZE uygulanır, bayat sanılıp düşürülmez).
struct WalletStoreResetTests {
    private func makeStore(_ remote: FakeWalletRemote = FakeWalletRemote()) -> WalletStore {
        WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
    }

    @Test func resetBakiyeVIPveAcilmisBolumuTemizler() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_A", coinsSpent: 60),
            wallet: .fixture(purchased: 200, version: 10),
            transactions: []
        ))]
        let store = makeStore(remote)
        await store.apply(walletSnapshot: .fixture(purchased: 500, version: 10))
        await store.apply(subscription: .vip())
        _ = await store.unlock(episodeID: EpisodeID("ep_A"), expectedPrice: 60, idempotencyKey: "k1")

        // Ön koşul: önceki hesabın state'i dolu.
        #expect(await store.currentBalance() != .zero)
        #expect(await store.subscriptionStatus().grantsFullAccess)
        #expect(await store.hasAccess(to: EpisodeID("ep_A")))

        await store.reset()

        // Reset sonrası: hiçbir eski-hesap izi kalmamalı.
        #expect(await store.currentBalance() == .zero)
        #expect(await store.subscriptionStatus().grantsFullAccess == false)
        #expect(await store.hasAccess(to: EpisodeID("ep_A")) == false)
    }

    @Test func resetSonrasiDusukVersionSnapshotTazeUygulanir() async {
        let store = makeStore()
        // Eski hesap yüksek-version snapshot uygular (hasServerSnapshot=true, version=10).
        await store.apply(walletSnapshot: .fixture(purchased: 500, version: 10))
        await store.reset()
        // Yeni hesabın DÜŞÜK-version snapshot'ı reset sonrası uygulanmalı (guard sıfırlandı) —
        // aksi halde monoton guard onu bayat sanıp düşürür, eski bakiye yapışkan kalırdı.
        await store.apply(walletSnapshot: .fixture(purchased: 30, version: 3))
        #expect(await store.currentBalance() == CoinBalance(purchasedCoins: 30, earnedCoins: 0))
    }
}
