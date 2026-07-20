import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// SS-100: `WalletStore` earned-kese ARTIŞLARINI kazanç-hızı monitörüne raporlar (danışma). Yalnız
/// gözlem — bakiye/versiyon/entitlement akışı DEĞİŞMEZ. İlk server snapshot baseline'dır (kaydedilmez);
/// yalnız iki SERVER snapshot arası earned ARTIŞI bir kazanç olayıdır (harcama/purchased/bayat DEĞİL).
struct WalletStoreEarnVelocityTests {
    /// Kayıtları toplayan casus recorder (senkron `recordEarn`; kilitli, @Sendable-güvenli).
    private final class SpyRecorder: EarnVelocityRecording, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [Int] = []
        func recordEarn(coins: Int) {
            lock.withLock { recorded.append(coins) }
        }

        var coins: [Int] {
            lock.withLock { recorded }
        }
    }

    private func makeStore(_ recorder: SpyRecorder) -> WalletStore {
        WalletStore(
            remote: FakeWalletRemote(),
            analytics: MockAnalytics(),
            log: MockLogger(),
            earnVelocityRecorder: recorder
        )
    }

    @Test func ilkServerSnapshotBaselineKaydetmez() async {
        let recorder = SpyRecorder()
        let store = makeStore(recorder)
        // İlk server snapshot: baseline yok → earned 200 olsa bile kaydedilmez.
        await store.apply(walletSnapshot: .fixture(earned: 200, version: 1))
        #expect(recorder.coins.isEmpty)
    }

    @Test func earnedKeseArtisiKazancOlarakKaydedilir() async {
        let recorder = SpyRecorder()
        let store = makeStore(recorder)
        await store.apply(walletSnapshot: .fixture(earned: 100, version: 1)) // baseline
        await store.apply(walletSnapshot: .fixture(earned: 340, version: 2)) // +240 kazanç
        #expect(recorder.coins == [240])
    }

    @Test func ardisikArtislarAyriKazancOlaylariUretir() async {
        let recorder = SpyRecorder()
        let store = makeStore(recorder)
        await store.apply(walletSnapshot: .fixture(earned: 0, version: 1)) // baseline
        await store.apply(walletSnapshot: .fixture(earned: 50, version: 2)) // +50
        await store.apply(walletSnapshot: .fixture(earned: 130, version: 3)) // +80
        #expect(recorder.coins == [50, 80])
    }

    @Test func purchasedKeseDegisimiKazancDegildir() async {
        let recorder = SpyRecorder()
        let store = makeStore(recorder)
        await store.apply(walletSnapshot: .fixture(purchased: 100, earned: 0, version: 1)) // baseline
        // Coin satın alımı: purchased artar, earned sabit → kazanç-hızı DEĞİL.
        await store.apply(walletSnapshot: .fixture(purchased: 600, earned: 0, version: 2))
        #expect(recorder.coins.isEmpty)
    }

    @Test func earnedDususuHarcamaKaydedilmez() async {
        let recorder = SpyRecorder()
        let store = makeStore(recorder)
        await store.apply(walletSnapshot: .fixture(earned: 200, version: 1)) // baseline
        // Unlock harcaması: earned düşer → kazanç değil.
        await store.apply(walletSnapshot: .fixture(earned: 140, version: 2))
        #expect(recorder.coins.isEmpty)
    }

    @Test func bayatSnapshotKazancUretmez() async {
        let recorder = SpyRecorder()
        let store = makeStore(recorder)
        await store.apply(walletSnapshot: .fixture(earned: 300, version: 5)) // baseline
        // Uçuşta kalmış eski (düşük versiyon) snapshot düşer — earned "artışı" olsa bile kaydedilmez.
        await store.apply(walletSnapshot: .fixture(earned: 900, version: 3))
        #expect(recorder.coins.isEmpty)
    }

    @Test func recorderYokkenAkisBozulmaz() async {
        // earnVelocityRecorder nil (F1/varsayılan): kazanç yolu no-op, bakiye normal uygulanır.
        let store = WalletStore(remote: FakeWalletRemote(), analytics: MockAnalytics(), log: MockLogger())
        await store.apply(walletSnapshot: .fixture(earned: 10, version: 1))
        await store.apply(walletSnapshot: .fixture(earned: 999, version: 2))
        let balance = await store.currentBalance()
        #expect(balance.earnedCoins == 999)
    }
}
