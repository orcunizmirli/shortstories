import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// UnlockSheet reklam-ile-aç entegrasyonu (SS-114 / 06 §6.2 #4, §9.2/§9.3/§9.5). Satır görünürlük/durum
/// (bayrak × fill × cap) server+config-otoriter port'tan; reklam→unlock akışı (KESİNTİSİZ oynatma devamı),
/// cap-reached devre dışı, erken-kapatma ödül-yok. WalletKit RewardsKit'i İMPORT ETMEZ — port enjekte.
@MainActor
struct UnlockSheetAdRowTests {
    private func context(price: Int? = 70) -> UnlockContext {
        UnlockContext(
            seriesID: SeriesID("srs_1"),
            episodeID: EpisodeID("ep_12"),
            seriesTitle: "Gizli Miras",
            episodeNumber: 12,
            unlockPrice: price,
            teaserText: nil,
            source: .autoAdvance
        )
    }

    private func makeModel(
        gateway: FakeWalletGateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 0, earnedCoins: 0)),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: SpyUnlockSheetDelegate,
        rewardedAdUnlock: FakeRewardedAdUnlocking?
    ) -> UnlockSheetModel {
        UnlockSheetModel(
            context: context(),
            wallet: gateway,
            analytics: analytics,
            delegate: delegate,
            rewardedAdUnlock: rewardedAdUnlock
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() {
            await Task.yield()
        }
    }

    // MARK: - Görünürlük (bayrak × fill × cap)

    @Test func portYokReklamSatiriGizli() async {
        // Faz 1 / bayrak kapalı: port enjekte edilmez → satır hiç görünmez, options_shown "ad" içermez.
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(analytics: analytics, delegate: delegate, rewardedAdUnlock: nil)

        await model.begin()

        #expect(model.adAvailability == .hidden)
        #expect(!model.viewState.orderedOptions.contains(.ad))
        let prompt = analytics.events.first { $0.name == "episode_unlock_prompt" }
        #expect(prompt?.parameters["options_shown"] == .string("coin,vip"))
        model.onDisappear()
    }

    @Test func fillYokAyniPortHiddenIleSatirGizli() async {
        // App adaptörü fill-yok/VIP/A-B/bayrak-kapalı durumlarını `.hidden`'a çözer → satır render edilmez.
        let ad = FakeRewardedAdUnlocking(availability: .hidden)
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(delegate: delegate, rewardedAdUnlock: ad)

        await model.begin()

        #expect(ad.preloadCount == 1) // ön-yükleme denendi (adaptör VIP'e no-op'lar)
        #expect(model.adAvailability == .hidden)
        #expect(!model.viewState.orderedOptions.contains(.ad))
        model.onDisappear()
    }

    @Test func availableSatirGorunurEtkinVeSiralamaCoinAdVip() async {
        let ad = FakeRewardedAdUnlocking(availability: .available(remaining: 3, dailyCap: 5))
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(analytics: analytics, delegate: delegate, rewardedAdUnlock: ad)

        await model.begin()

        #expect(model.adAvailability == .available(remaining: 3, dailyCap: 5))
        #expect(model.adAvailability.isActionable)
        #expect(model.adAvailability.remainingIndicator?.remaining == 3)
        #expect(model.adAvailability.remainingIndicator?.dailyCap == 5)
        // Sabit sıralama coin → reklam → VIP (yalnız görünür satırlar).
        #expect(model.viewState.orderedOptions == [.coin, .ad, .vip])
        let prompt = analytics.events.first { $0.name == "episode_unlock_prompt" }
        #expect(prompt?.parameters["options_shown"] == .string("coin,ad,vip"))
        model.onDisappear()
    }

    @Test func capDoluSatirGorunurAmaDevreDisi() async {
        let resets = Date(timeIntervalSince1970: 2_000_000)
        let ad = FakeRewardedAdUnlocking(availability: .capReached(resetsAt: resets, dailyCap: 5))
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(delegate: delegate, rewardedAdUnlock: ad)

        await model.begin()

        #expect(model.adAvailability == .capReached(resetsAt: resets, dailyCap: 5))
        #expect(model.adAvailability.isVisible)
        #expect(!model.adAvailability.isActionable) // görünür ama devre dışı (ödemeye baskı)
        #expect(model.viewState.orderedOptions.contains(.ad))
        model.onDisappear()
    }

    // MARK: - Reklam → unlock (server-otoriter, KESİNTİSİZ oynatma devamı)

    @Test func reklamIzlenirseUnlockUygulanirVePlayerDevamEder() async {
        let ad = FakeRewardedAdUnlocking(
            availability: .available(remaining: 3, dailyCap: 5),
            watchResult: .unlocked(remainingToday: 2)
        )
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(analytics: analytics, delegate: delegate, rewardedAdUnlock: ad)
        await model.begin()

        await model.watchAd()

        #expect(ad.watchedEpisodes == [EpisodeID("ep_12")])
        // Kilit açıldı → delegate.unlockSheetDidUnlock (coin unlock ile AYNI akış → kesintisiz oynatma).
        #expect(delegate.unlocked == [EpisodeID("ep_12")])
        #expect(!model.isWatchingAd)
        #expect(model.adWatchError == nil)
        // unlock_ad funnel event'i: ad_unlocks_used_today = cap(5) − server kalan(2) = 3.
        let unlockAd = analytics.events.first { $0.name == "unlock_ad" }
        #expect(unlockAd?.parameters["episode_id"] == .string("ep_12"))
        #expect(unlockAd?.parameters["ad_unlocks_used_today"] == .int(3))
        #expect(unlockAd?.parameters["daily_cap"] == .int(5))
        model.onDisappear()
    }

    @Test func reklamSonrasiCoinUnlockCagrilmaz() async {
        // Reklam yolu coin DÜŞMEZ (server-otoriter, method: rewardedAd). Cüzdan unlock'u tetiklenmez.
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 0, earnedCoins: 0))
        let ad = FakeRewardedAdUnlocking(
            availability: .available(remaining: 3, dailyCap: 5),
            watchResult: .unlocked(remainingToday: 2)
        )
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate, rewardedAdUnlock: ad)
        await model.begin()

        await model.watchAd()

        #expect(gateway.unlockCallCount == 0) // coin unlock YOK — reklam yolu server-otoriter
        #expect(delegate.unlocked == [EpisodeID("ep_12")])
        model.onDisappear()
    }

    // MARK: - Cap-reached / erken-kapatma / fill-yok / red

    @Test func watchCapReachedSatiriDevreDisiYaparUnlockYok() async {
        let resets = Date(timeIntervalSince1970: 3_000_000)
        let ad = FakeRewardedAdUnlocking(
            availability: .available(remaining: 1, dailyCap: 5),
            watchResult: .capReached(resetsAt: resets)
        )
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(delegate: delegate, rewardedAdUnlock: ad)
        await model.begin()

        await model.watchAd()

        #expect(model.adAvailability == .capReached(resetsAt: resets, dailyCap: 5)) // dailyCap korunur
        #expect(!model.adAvailability.isActionable)
        #expect(delegate.unlocked.isEmpty)
        #expect(model.adWatchError == nil)
        model.onDisappear()
    }

    @Test func erkenKapatmaOdulYokSatirEtkinKalir() async {
        let ad = FakeRewardedAdUnlocking(
            availability: .available(remaining: 3, dailyCap: 5),
            watchResult: .dismissedEarly
        )
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(delegate: delegate, rewardedAdUnlock: ad)
        await model.begin()

        await model.watchAd()

        #expect(delegate.unlocked.isEmpty) // ödül YOK, hak düşmez
        #expect(model.adWatchError == nil) // sessiz (kullanıcı seçimi)
        #expect(model.adAvailability.isActionable) // satır olduğu gibi etkin
        model.onDisappear()
    }

    @Test func fillYokVeHataInlineUyariGosterirUnlockYok() async {
        for outcome in [RewardedAdUnlockResult.noFill, .failed] {
            let ad = FakeRewardedAdUnlocking(
                availability: .available(remaining: 3, dailyCap: 5),
                watchResult: outcome
            )
            let delegate = SpyUnlockSheetDelegate()
            let model = makeModel(delegate: delegate, rewardedAdUnlock: ad)
            await model.begin()

            await model.watchAd()

            #expect(model.adWatchError == .temporarilyUnavailable)
            #expect(delegate.unlocked.isEmpty)
            #expect(model.adAvailability.isActionable) // retry için etkin kalır
            model.onDisappear()
        }
    }

    @Test func serverKanitReddiRewardRejectedUnlockYok() async {
        let ad = FakeRewardedAdUnlocking(
            availability: .available(remaining: 3, dailyCap: 5),
            watchResult: .rewardRejected
        )
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(delegate: delegate, rewardedAdUnlock: ad)
        await model.begin()

        await model.watchAd()

        #expect(model.adWatchError == .rewardRejected)
        #expect(delegate.unlocked.isEmpty) // kilit AÇILMAZ (06 §9.4)
        model.onDisappear()
    }

    @Test func capReachedIkenWatchNoOp() async {
        // Devre dışı satır: watchAd tetiklense bile reklam gösterilMEZ (isActionable guard).
        let ad = FakeRewardedAdUnlocking(availability: .capReached(resetsAt: nil, dailyCap: 5))
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(delegate: delegate, rewardedAdUnlock: ad)
        await model.begin()

        await model.watchAd()

        #expect(ad.watchCount == 0)
        #expect(delegate.unlocked.isEmpty)
        model.onDisappear()
    }

    @Test func watchAwaitSirasindaVIPCozulurseSonucYokSayilir() async {
        // TOCTOU: watchAd askıdayken başka cihazdan VIP aktifleşir → entitlement gözlemi completeUnlock.
        // Sonra reklam .failed dönse bile adWatchError yazılMAZ (kilidi açılmış sheet üzerine mutasyon yok;
        // coin TOCTOU akışıyla simetrik `resolved` guard'ı).
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 0, earnedCoins: 0))
        let ad = FakeRewardedAdUnlocking(
            availability: .available(remaining: 3, dailyCap: 5),
            watchResult: .failed
        )
        let gate = AsyncGate()
        ad.watchGate = { await gate.wait() }
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate, rewardedAdUnlock: ad)
        await model.begin()

        async let action: Void = model.watchAd()
        await waitUntil { ad.watchCount == 1 } // reklam gösterimi gate'te askıda

        gateway.pushEntitlement(EntitlementSnapshot(
            isVIP: true,
            vipExpiresAt: nil,
            isInGracePeriod: false,
            lastUnlockedEpisode: nil
        ))
        await waitUntil { !delegate.unlocked.isEmpty } // gözlem completeUnlock → didUnlock

        await gate.open()
        await action

        #expect(delegate.unlocked == [EpisodeID("ep_12")])
        #expect(model.adWatchError == nil) // resolved guard: kapanan sheet'e hata yazılmaz
        model.onDisappear()
    }
}
