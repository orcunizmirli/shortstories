import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// Snapshot version-guard ve idempotent kredi (SS-092): out-of-order koruması + çift kredi önleme.
struct WalletStoreVersionTests {
    private func makeStore() -> (WalletStore, FakeWalletRemote) {
        let remote = FakeWalletRemote()
        return (WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger()), remote)
    }

    @Test func eskiVersionSnapshotAtilir() async {
        let (store, _) = makeStore()
        await store.apply(walletSnapshot: .fixture(purchased: 200, version: 10))

        // Daha eski (out-of-order) yanıt gelirse yok sayılır.
        await store.apply(walletSnapshot: .fixture(purchased: 50, version: 9))

        let balance = await store.currentBalance()
        #expect(balance.purchasedCoins == 200)
    }

    @Test func yeniVersionSnapshotUygulanir() async {
        let (store, _) = makeStore()
        await store.apply(walletSnapshot: .fixture(purchased: 200, version: 10))
        await store.apply(walletSnapshot: .fixture(purchased: 260, version: 11))

        let balance = await store.currentBalance()
        #expect(balance.purchasedCoins == 260)
    }

    @Test func ayniVersionCiftKrediYazmaz() async {
        // IAP idempotency: aynı transaction iki kez doğrulandı → server aynı snapshot'ı döner.
        // SET semantiği + version-guard: çift kredi imkânsız.
        let (store, _) = makeStore()
        let credited = WalletSnapshot.fixture(purchased: 1205, version: 124)

        await store.apply(walletSnapshot: credited)
        await store.apply(walletSnapshot: credited)

        let balance = await store.currentBalance()
        #expect(balance.purchasedCoins == 1205) // 2410 DEĞİL
    }

    @Test func ilkServerSnapshotVersionMinIzerineUygulanir() async {
        // Başlangıç sentinel'i (Int.min) ilk gerçek snapshot'ı bloklamamalı.
        let (store, _) = makeStore()
        await store.apply(walletSnapshot: .fixture(purchased: 10, version: 1))

        let balance = await store.currentBalance()
        #expect(balance.purchasedCoins == 10)
    }
}
