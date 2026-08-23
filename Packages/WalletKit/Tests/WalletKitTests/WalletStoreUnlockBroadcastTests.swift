import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// Audit HIGH (UnlockSheet red-işleme ölü-kod): `lastUnlockedEpisode` yayını "ONAYLANMIŞ unlock"
/// sinyalidir — UnlockSheet gözlemcisi bununla `completeUnlock` edip kapanır. İyimser (server ONAYI
/// ÖNCESİ) `markUnlocked` bunu YAYARSA, sheet server reddinden (insufficientCoins/priceChanged) ÖNCE
/// kapanır ve red-işleme (mağazaya yönlendirme / fiyat-değişti) ölü-kod olur. Bu yüzden iyimser yayın
/// lastUnlocked TAŞIMAZ; yalnız server-onaylı başarı taşır.
struct WalletStoreUnlockBroadcastTests {
    private func makeStore(_ remote: FakeWalletRemote) -> WalletStore {
        WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
    }

    @Test func iyimserUnlockLastUnlockedYaymaz_onaydaTasir() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_9"),
            wallet: .fixture(purchased: 40, version: 2),
            transactions: []
        ))]
        let store = makeStore(remote)
        await store.apply(walletSnapshot: .fixture(purchased: 100, version: 1))
        var iterator = store.entitlementUpdates().makeAsyncIterator()

        _ = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60)

        // İlk yayın İYİMSER (server yanıtından önce) → lastUnlocked TAŞIMAZ (sheet erken kapanmasın).
        let optimistic = await iterator.next()
        #expect(optimistic?.lastUnlockedEpisode == nil)
        // İkinci yayın server-ONAYLI başarı → lastUnlocked taşır (sheet burada kapanır).
        let confirmed = await iterator.next()
        #expect(confirmed?.lastUnlockedEpisode == EpisodeID("ep_9"))
    }

    @Test func redUnlockHicLastUnlockedYaymaz() async {
        let remote = FakeWalletRemote()
        // İstemci bakiyesi yeterli görünürken (stale) server insufficientCoins döner.
        remote.unlockResults = [.success(.insufficientCoins(shortfall: 50, wallet: .fixture(purchased: 5, version: 2)))]
        let store = makeStore(remote)
        await store.apply(walletSnapshot: .fixture(purchased: 100, version: 1))
        var iterator = store.entitlementUpdates().makeAsyncIterator()

        _ = await store.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 70)

        // Ne iyimser ne rollback yayını lastUnlocked=ep_9 taşımalı (aksi halde sheet reddi görmeden kapanır).
        let optimistic = await iterator.next()
        #expect(optimistic?.lastUnlockedEpisode == nil)
        let rollback = await iterator.next()
        #expect(rollback?.lastUnlockedEpisode == nil)
    }
}

/// GERÇEK `WalletStore` + `UnlockSheetModel` entegrasyonu (kullanıcı-yüzlü kanıt): istemci bakiyesi
/// yeterli görünürken server insufficientCoins döndüğünde sheet, iyimser yayınla ERKEN kapanmamalı;
/// mağazaya yönlendirmeli. Mevcut UnlockSheetModel testleri FAKE gateway kullandığından (iyimser yayını
/// üretmez) bu bug'ı KAÇIRIR → gerçek store ile doğrulanır.
@MainActor
struct UnlockSheetRealStoreIntegrationTests {
    @Test func serverInsufficientCoinsGercekStoreMagazayaYonlendirir() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.insufficientCoins(shortfall: 50, wallet: .fixture(purchased: 5, version: 2)))]
        let store = WalletStore(remote: remote, analytics: MockAnalytics(), log: MockLogger())
        await store.apply(walletSnapshot: .fixture(purchased: 100, version: 1)) // istemci: yeterli görünür

        let delegate = SpyUnlockSheetDelegate()
        let model = UnlockSheetModel(
            context: UnlockContext(
                seriesID: SeriesID("srs_1"),
                episodeID: EpisodeID("ep_9"),
                seriesTitle: "Test",
                episodeNumber: 1,
                unlockPrice: 70,
                source: .diziDetay
            ),
            wallet: store,
            analytics: MockAnalytics(),
            delegate: delegate
        )
        await model.begin()

        await model.primaryAction()

        // Fix: iyimser yayın lastUnlocked taşımaz → gözlemci ERKEN completeUnlock etmez; performUnlock
        // server reddini işler → mağazaya yönlendirir, ERKEN/yanlış unlock olmaz.
        #expect(delegate.unlocked.isEmpty)
        #expect(delegate.coinStoreRequests == 1)
    }
}
