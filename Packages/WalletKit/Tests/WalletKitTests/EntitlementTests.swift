import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// Entitlement senkronu + yayını (SS-097) ve `EntitlementChecking` implementasyonu (R8).
struct EntitlementTests {
    private func makeStore(remote: FakeWalletRemote = FakeWalletRemote()) -> (WalletStore, MockAnalytics) {
        let analytics = MockAnalytics()
        return (WalletStore(remote: remote, analytics: analytics, log: MockLogger()), analytics)
    }

    @Test func vipTumBolumlereErisimVerir() async {
        let (store, _) = makeStore()
        await store.apply(subscription: .vip())

        let access = await store.hasAccess(to: EpisodeID("herhangi_ep"))
        #expect(access)
    }

    @Test func vipDegilkenYalnizAcilmisBolumErisilir() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_5"),
            wallet: .fixture(purchased: 40, version: 2),
            transactions: []
        ))]
        let (store, _) = makeStore(remote: remote)
        await store.apply(walletSnapshot: .fixture(purchased: 100, version: 1))

        let before = await store.hasAccess(to: EpisodeID("ep_5"))
        #expect(!before)

        _ = await store.unlock(episodeID: EpisodeID("ep_5"), expectedPrice: 60)

        let after = await store.hasAccess(to: EpisodeID("ep_5"))
        let other = await store.hasAccess(to: EpisodeID("ep_6"))
        #expect(after)
        #expect(!other)
    }

    @Test func gracePeriodBoyuncaErisimSurer() async {
        let (store, _) = makeStore()
        await store.apply(subscription: .vip(grace: true, willAutoRenew: false))

        let access = await store.hasAccess(to: EpisodeID("ep_1"))
        #expect(access)
    }

    @Test func vipBittigindeErisimDuser() async {
        let (store, _) = makeStore()
        await store.apply(subscription: .vip())
        #expect(await store.hasAccess(to: EpisodeID("ep_1")))

        await store.apply(subscription: .none) // EXPIRED
        #expect(await !(store.hasAccess(to: EpisodeID("ep_1"))))
    }

    @Test func storeKitOptimistikVipSunucuReddindeDuserVeUyusmazlikLoglanir() async {
        // 06 §4.5: lokal (StoreKit) VIP diyor, sunucu hayır → sunucu kazanır + mismatch log.
        let (store, analytics) = makeStore()
        await store.seedEntitlementFromStoreKit(hasActiveSubscription: true)
        #expect(await store.hasAccess(to: EpisodeID("ep_1"))) // iyimser VIP

        await store.apply(subscription: .none) // sunucu VIP değil

        #expect(await !(store.hasAccess(to: EpisodeID("ep_1"))))
        #expect(analytics.eventNames.contains("entitlement_mismatch"))
    }

    @Test func sunucuAboneligiGelmisseStoreKitTohumuYokSayilir() async {
        let (store, _) = makeStore()
        await store.apply(subscription: .none) // sunucu otoritesi kuruldu

        await store.seedEntitlementFromStoreKit(hasActiveSubscription: true) // geç tohum

        #expect(await !(store.hasAccess(to: EpisodeID("ep_1")))) // tohum yok sayıldı
    }

    @Test func eskiSubscriptionSnapshotTazeVipiEzmez() async {
        // Out-of-order koruması (applyWallet ile simetri): satın alma taze VIP uygular; uçuşta kalmış
        // BAYAT (daha eski updatedAt'lı) non-VIP fetch sonradan gelirse taze VIP'i EZMEMELİ.
        let (store, _) = makeStore()
        let fresh = SubscriptionStatus.vip(updatedAt: Date(timeIntervalSince1970: 2000))
        await store.apply(subscription: fresh)
        #expect(await store.hasAccess(to: EpisodeID("ep_1")))

        // Bayat non-VIP (daha ESKİ updatedAt) — out-of-order refresh — yok sayılmalı.
        let stale = SubscriptionStatus(
            isVIP: false, plan: nil, expiresAt: nil, willAutoRenew: false,
            isInGracePeriod: false, isInIntroOffer: false, dailyBonusCoins: 0,
            dailyBonusClaimedToday: false, updatedAt: Date(timeIntervalSince1970: 1000)
        )
        await store.apply(subscription: stale)

        #expect(await store.hasAccess(to: EpisodeID("ep_1"))) // hâlâ VIP
    }

    @Test func yeniSubscriptionSnapshotEskiyiUygular() async {
        // Regresyon: daha YENİ updatedAt'lı non-VIP (gerçek downgrade / expiry) UYGULANIR.
        let (store, _) = makeStore()
        await store.apply(subscription: .vip(updatedAt: Date(timeIntervalSince1970: 1000)))
        #expect(await store.hasAccess(to: EpisodeID("ep_1")))

        let fresherNonVIP = SubscriptionStatus(
            isVIP: false, plan: nil, expiresAt: nil, willAutoRenew: false,
            isInGracePeriod: false, isInIntroOffer: false, dailyBonusCoins: 0,
            dailyBonusClaimedToday: false, updatedAt: Date(timeIntervalSince1970: 2000)
        )
        await store.apply(subscription: fresherNonVIP)

        #expect(await !(store.hasAccess(to: EpisodeID("ep_1")))) // downgrade uygulandı
    }

    @Test func entitlementDegisimiYayinlanir() async {
        // ≤5 sn hedefi: push tabanlı, anında. Abone VIP geçişini alır.
        let (store, _) = makeStore()
        var iterator = store.entitlementUpdates().makeAsyncIterator()

        await store.apply(subscription: .vip(plan: .yearly))

        let snapshot = await iterator.next()
        #expect(snapshot?.isVIP == true)
    }

    @Test func bolumAcilincaEntitlementYayiniTetiklenir() async {
        let remote = FakeWalletRemote()
        remote.unlockResults = [.success(.unlocked(
            record: .fixture(episode: "ep_42"),
            wallet: .fixture(purchased: 40, version: 2),
            transactions: []
        ))]
        let (store, _) = makeStore(remote: remote)
        await store.apply(walletSnapshot: .fixture(purchased: 100, version: 1))
        var iterator = store.entitlementUpdates().makeAsyncIterator()

        _ = await store.unlock(episodeID: EpisodeID("ep_42"), expectedPrice: 60)

        let snapshot = await iterator.next()
        #expect(snapshot?.lastUnlockedEpisode == EpisodeID("ep_42"))
    }
}
