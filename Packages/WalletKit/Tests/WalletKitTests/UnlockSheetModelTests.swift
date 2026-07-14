import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import WalletKit

/// UnlockSheet ekran modeli (SS-093): birincil aksiyon dallanması, coin-yetersiz → mağaza,
/// fiyat değişimi, otomatik-unlock (binge), VIP upsell, kapatma + analitik.
@MainActor
struct UnlockSheetModelTests {
    private func context(
        price: Int? = 70,
        source: UnlockPromptSource = .autoAdvance,
        autoUnlock: Bool = false
    ) -> UnlockContext {
        UnlockContext(
            seriesID: SeriesID("srs_1"),
            episodeID: EpisodeID("ep_12"),
            seriesTitle: "Gizli Miras",
            episodeNumber: 12,
            unlockPrice: price,
            teaserText: "Her şey değişecek…",
            source: source,
            autoUnlockEnabled: autoUnlock
        )
    }

    private func makeModel(
        gateway: FakeWalletGateway,
        analytics: MockAnalytics = MockAnalytics(),
        delegate: SpyUnlockSheetDelegate,
        context ctx: UnlockContext? = nil,
        config: UnlockOptionsConfig = .phase1,
        vipIntroEligible: Bool = false
    ) -> UnlockSheetModel {
        UnlockSheetModel(
            context: ctx ?? context(),
            wallet: gateway,
            analytics: analytics,
            delegate: delegate,
            config: config,
            vipIntroEligible: vipIntroEligible
        )
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() {
            await Task.yield()
        }
    }

    @Test func beginSeedsBalanceVePromptAnalitigi() async {
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 120, earnedCoins: 30))
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, analytics: analytics, delegate: delegate)

        await model.begin()

        #expect(model.balance == CoinBalance(purchasedCoins: 120, earnedCoins: 30))
        let prompt = analytics.events.first { $0.name == "episode_unlock_prompt" }
        #expect(prompt != nil)
        #expect(prompt?.parameters["coin_balance"] == .int(150))
        #expect(prompt?.parameters["unlock_price"] == .int(70))
        #expect(prompt?.parameters["options_shown"] == .string("coin,vip"))
        #expect(prompt?.parameters["source"] == .string("auto_advance"))
        model.onDisappear()
    }

    @Test func bakiyeYeterliBirincilUnlockYapar() async {
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0))
        gateway.unlockResults = [.success(.fixture(episode: "ep_12", coinsSpent: 70))]
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        await model.primaryAction()

        #expect(gateway.unlockCallCount == 1)
        #expect(gateway.unlockCalls.first?.price == 70)
        #expect(delegate.unlocked == [EpisodeID("ep_12")])
        #expect(!model.isUnlocking)
        model.onDisappear()
    }

    @Test func bakiyeYetersizMagazayaYonlendirirUnlockYok() async {
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 30, earnedCoins: 0))
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        await model.primaryAction()

        #expect(gateway.unlockCallCount == 0) // unlock çağrılmaz — doğrudan mağaza
        #expect(delegate.coinStoreRequests == 1)
        model.onDisappear()
    }

    @Test func serverInsufficientSonucuMagazayaYonlendirir() async {
        // Bakiye yeterli görünürken server yine de INSUFFICIENT dönerse (drift) → mağaza.
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0))
        gateway.unlockResults = [.insufficientCoins(shortfall: 20)]
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        await model.primaryAction()

        #expect(gateway.unlockCallCount == 1)
        #expect(delegate.coinStoreRequests == 1)
        #expect(delegate.unlocked.isEmpty)
        model.onDisappear()
    }

    @Test func fiyatDegistiFiyatiGuncelleyipUyariGosterir() async {
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0))
        gateway.unlockResults = [.priceChanged(currentPrice: 85)]
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        await model.primaryAction()

        #expect(model.unlockPrice == 85)
        #expect(model.errorReason == .priceChanged)
        #expect(delegate.unlocked.isEmpty)
        // Fiyat güncellendi → yeni fiyata göre view-state.
        #expect(model.viewState.coinState == .sufficient(price: 85))
        model.onDisappear()
    }

    @Test func agHatasiInlineHataVeUnlockFailedAnalitigi() async {
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0))
        gateway.unlockResults = [.failed(.network(.offline))]
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, analytics: analytics, delegate: delegate)
        await model.begin()

        await model.primaryAction()

        #expect(model.errorReason == .network)
        #expect(!model.isUnlocking)
        let failed = analytics.events.first { $0.name == "unlock_failed" }
        #expect(failed?.parameters["reason"] == .string("offline"))
        model.onDisappear()
    }

    @Test func basariliUnlockSonrasiTekrarUnlockEngellenir() async {
        // resolved guard: kilit açıldıktan sonra ikinci primaryAction ikinci istek atmaz.
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0))
        gateway.unlockResults = [
            .success(.fixture(episode: "ep_12", coinsSpent: 70)),
            .success(.fixture(episode: "ep_12", coinsSpent: 70))
        ]
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        await model.primaryAction()
        await model.primaryAction()

        #expect(gateway.unlockCallCount == 1)
        #expect(delegate.unlocked.count == 1)
        model.onDisappear()
    }

    @Test func vipUpsellAnalitikVeDelegate() async {
        let gateway = FakeWalletGateway()
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, analytics: analytics, delegate: delegate)
        await model.begin()

        model.vipUpsellTapped()

        #expect(delegate.vipRequests == 1)
        let event = analytics.events.first { $0.name == "unlock_vip_upsell" }
        #expect(event?.parameters["episode_id"] == .string("ep_12"))
        model.onDisappear()
    }

    @Test func otomatikUnlockToggleAnalitikVeYazma() async {
        let gateway = FakeWalletGateway()
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, analytics: analytics, delegate: delegate)
        await model.begin()

        model.setAutoUnlock(true)
        model.setAutoUnlock(true) // aynı değer → no-op (tekrar yazma/analitik yok)

        #expect(model.autoUnlockEnabled)
        #expect(delegate.autoUnlockWrites.count == 1)
        #expect(delegate.autoUnlockWrites.first?.enabled == true)
        #expect(delegate.autoUnlockWrites.first?.seriesID == SeriesID("srs_1"))
        #expect(analytics.events.filter { $0.name == "auto_unlock_toggled" }.count == 1)
        model.onDisappear()
    }

    @Test func otomatikUnlockAcikMagazaDonusundeSormadanAcar() async {
        // 06 §6.4/§6.3: binge açık + dönüşte bakiye yeterli → sormadan unlock.
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 30, earnedCoins: 0))
        gateway.unlockResults = [.success(.fixture(episode: "ep_12", coinsSpent: 70))]
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate, context: context(autoUnlock: true))
        await model.begin()
        #expect(model.autoUnlockEnabled)

        gateway.pushBalance(CoinBalance(purchasedCoins: 130, earnedCoins: 0)) // satın alma sonrası
        await model.returnedFromCoinStore()

        #expect(gateway.unlockCallCount == 1)
        #expect(delegate.unlocked == [EpisodeID("ep_12")])
        model.onDisappear()
    }

    @Test func otomatikUnlockKapaliMagazaDonusundeSormaz() async {
        // Binge kapalı → dönüşte otomatik unlock YAPILMAZ (kullanıcı son dokunuşu kendisi yapar).
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 30, earnedCoins: 0))
        gateway.unlockResults = [.success(.fixture(episode: "ep_12", coinsSpent: 70))]
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate, context: context(autoUnlock: false))
        await model.begin()

        gateway.pushBalance(CoinBalance(purchasedCoins: 130, earnedCoins: 0))
        await model.returnedFromCoinStore()

        #expect(gateway.unlockCallCount == 0)
        #expect(delegate.unlocked.isEmpty)
        // Ama bakiye güncellendi → CTA artık yeterli.
        #expect(model.viewState.coinState == .sufficient(price: 70))
        model.onDisappear()
    }

    @Test func unlockAwaitSirasindaCozulurseSonucYokSayilir() async {
        // Finding #9 / TOCTOU: unlock await'teyken başka cihazdan VIP aktifleşir → completeUnlock +
        // unlockSheetDidUnlock. Sonra server .insufficientCoins dönse bile CoinMağazası'na
        // YÖNLENDİRİLMEZ (kapanan/kilidi açılmış sheet üzerine çift/tutarsız yönlendirme olmasın).
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 100, earnedCoins: 0))
        let gate = AsyncGate()
        gateway.unlockGate = { await gate.wait() }
        gateway.unlockResults = [.insufficientCoins(shortfall: 20)]
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        async let action: Void = model.primaryAction()
        await waitUntil { gateway.unlockCallCount == 1 } // unlock isteği gate'te askıda

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
        #expect(delegate.coinStoreRequests == 0) // resolved guard: mağazaya yönlendirme YOK
        #expect(model.errorReason == nil)
        model.onDisappear()
    }

    @Test func kapatmaAnalitikVeDelegate() async {
        let gateway = FakeWalletGateway()
        let analytics = MockAnalytics()
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, analytics: analytics, delegate: delegate)
        await model.begin()

        model.dismiss()

        #expect(delegate.dismissals == 1)
        #expect(analytics.eventNames.contains("unlock_sheet_dismissed"))
        model.onDisappear()
    }

    @Test func baskaCihazdanVIPAktiflesirseSheetKapanirBolumAcilir() async {
        // 06 §6.6: entitlement yayınında VIP aktifleşirse sheet kendini kapatır ve bölüm açılır.
        let gateway = FakeWalletGateway(balance: CoinBalance(purchasedCoins: 0, earnedCoins: 0))
        let delegate = SpyUnlockSheetDelegate()
        let model = makeModel(gateway: gateway, delegate: delegate)
        await model.begin()

        gateway.pushEntitlement(EntitlementSnapshot(
            isVIP: true,
            vipExpiresAt: nil,
            isInGracePeriod: false,
            lastUnlockedEpisode: nil
        ))

        await waitUntil { !delegate.unlocked.isEmpty }
        #expect(delegate.unlocked == [EpisodeID("ep_12")])
        model.onDisappear()
    }
}
