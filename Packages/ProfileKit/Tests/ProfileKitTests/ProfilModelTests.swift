import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ProfileKit

@MainActor
@Suite("SS-130 ProfilModel (durum, niyet, analitik)")
struct ProfilModelTests {
    private func makeModel(
        session: MockSession = MockSession(),
        wallet: FakeWalletSummary = FakeWalletSummary(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: ProfileDelegateSpy,
        notificationCenterEnabled: Bool = false
    ) -> ProfilModel {
        ProfilModel(
            session: session,
            walletSummary: wallet,
            analytics: analytics,
            delegate: delegate,
            notificationCenterEnabled: notificationCenterEnabled
        )
    }

    // MARK: - Yükleme + durum

    @Test func onAppearTracksScreenView() async {
        let analytics = MockAnalytics()
        let model = makeModel(analytics: analytics, delegate: ProfileDelegateSpy())
        model.onAppear()
        await model.pendingWork()
        #expect(analytics.events.contains {
            $0.name == "screen_view" && $0.parameters["screen_name"] == .string("profil")
        })
    }

    @Test func loadsGuestAccountAndWallet() async {
        let wallet = FakeWalletSummary(WalletSummary(coinBalance: 120, isVIP: false, vipRenewalDate: nil))
        let model = makeModel(
            session: MockSession(state: .guest(userID: "g1")),
            wallet: wallet,
            delegate: ProfileDelegateSpy()
        )
        model.onAppear()
        await model.pendingWork()
        #expect(model.account.isGuest)
        #expect(model.wallet.coinBalance == 120)
        #expect(model.loadState == .loaded)
    }

    @Test func loadsLinkedAccount() async {
        let model = makeModel(
            session: MockSession(state: .linked(userID: "u1", provider: .apple)),
            delegate: ProfileDelegateSpy()
        )
        model.onAppear()
        await model.pendingWork()
        #expect(model.account.isLinked)
        #expect(model.account.provider == .apple)
    }

    // MARK: - Navigasyon niyetleri

    @Test func guestLinkCTAInvokesDelegateAndTracks() async {
        let spy = ProfileDelegateSpy()
        let analytics = MockAnalytics()
        let model = makeModel(
            session: MockSession(state: .guest(userID: "g1")),
            analytics: analytics,
            delegate: spy
        )
        model.onAppear()
        await model.pendingWork()
        model.linkOrReauthenticate()
        #expect(spy.accountLinking == 1)
        #expect(spy.reauth.isEmpty)
        #expect(analytics.events.contains {
            $0.name == "profile_row_tapped" && $0.parameters["row"] == .string("link_account")
        })
    }

    @Test func sessionExpiredTriggersReauth() async {
        let spy = ProfileDelegateSpy()
        let model = makeModel(
            session: MockSession(state: .loggedOut(previousUserID: "u1", provider: .google)),
            delegate: spy
        )
        model.onAppear()
        await model.pendingWork()
        model.linkOrReauthenticate()
        #expect(spy.reauth == [.google])
        #expect(spy.accountLinking == 0)
    }

    @Test func rowIntentsInvokeDelegateAndAnalytics() async {
        let spy = ProfileDelegateSpy()
        let analytics = MockAnalytics()
        let wallet = FakeWalletSummary(WalletSummary(coinBalance: 0, isVIP: true, vipRenewalDate: nil))
        let model = makeModel(wallet: wallet, analytics: analytics, delegate: spy)
        model.onAppear()
        await model.pendingWork()

        model.openCoinStore()
        model.openVIP()
        model.openWatchHistory()
        model.openSettings()
        model.openSupport()
        model.openNotificationCenter()

        #expect(spy.coinStore == 1)
        #expect(spy.vip == [true]) // wallet.isVIP yansır
        #expect(spy.watchHistory == 1)
        #expect(spy.settings == 1)
        #expect(spy.support == 1)
        #expect(spy.notificationCenter == 1)

        let rows = analytics.events
            .filter { $0.name == "profile_row_tapped" }
            .compactMap { $0.parameters["row"] }
        #expect(rows.contains(.string("coins")))
        #expect(rows.contains(.string("vip")))
        #expect(rows.contains(.string("settings")))
    }

    // MARK: - Canlı akışlar

    @Test func walletLiveUpdateReflected() async {
        let wallet = FakeWalletSummary(WalletSummary(coinBalance: 10, isVIP: false, vipRenewalDate: nil))
        let model = makeModel(wallet: wallet, delegate: ProfileDelegateSpy())
        model.onAppear()
        await model.pendingWork()
        #expect(model.wallet.coinBalance == 10)

        let observer = Task { await model.observeUpdates() }
        defer { observer.cancel() }
        wallet.set(WalletSummary(coinBalance: 999, isVIP: true, vipRenewalDate: nil))
        let updated = await eventually { model.wallet.coinBalance == 999 && model.wallet.isVIP }
        #expect(updated)
    }

    @Test func sessionLiveUpdateReflected() async {
        let session = MockSession(state: .guest(userID: "g1"))
        let model = makeModel(session: session, delegate: ProfileDelegateSpy())
        model.onAppear()
        await model.pendingWork()
        #expect(model.account.isGuest)

        let observer = Task { await model.observeUpdates() }
        defer { observer.cancel() }
        session.send(.linked(userID: "u1", provider: .apple))
        let linked = await eventually { model.account.isLinked }
        #expect(linked)
    }

    // MARK: - load() ↔ observeUpdates() sıralama (clobber yarışı, review #12)

    @Test func liveStreamValueWinsOverStaleInitialLoadSnapshot() async {
        // Regresyon (review #12): load()'ın ayrı currentSummary() snapshot'ı (ESKİ, coin 10), canlı
        // stream'in replay ettiği TAZE değeri (coin 999) clobber ETMEMELİ. Stream (en taze) SON söz.
        let wallet = GatedWallet(
            snapshot: WalletSummary(coinBalance: 10, isVIP: false, vipRenewalDate: nil),
            live: WalletSummary(coinBalance: 999, isVIP: true, vipRenewalDate: nil)
        )
        let model = ProfilModel(
            session: MockSession(state: .guest(userID: "g1")),
            walletSummary: wallet,
            analytics: MockAnalytics(),
            delegate: ProfileDelegateSpy()
        )
        model.onAppear() // loadTask başlar; currentSummary() gate'te bekler
        let observer = Task { await model.observeUpdates() }
        defer { observer.cancel() }

        // Buggy'de stream hemen replay eder (999); fixed'de load bitene kadar abone olmaz (bounded bekle).
        _ = await eventually(iterations: 50) { model.wallet.coinBalance == 999 }
        wallet.releaseSnapshot() // load'ın eski snapshot'ı ancak şimdi (replay'den SONRA) yazılır
        await model.pendingWork()

        let fresh = await eventually { model.wallet.coinBalance == 999 }
        #expect(fresh) // canlı akışın taze değeri korunur, eski snapshot clobber etmez
        #expect(model.wallet.coinBalance == 999)
    }

    // MARK: - VIP yenileme tarihi uygulama diline göre yerelleşir (review #13)

    @Test func vipRenewalDateUsesAppLanguageLocale() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        let date = try #require(Calendar(identifier: .gregorian).date(from: components))

        let english = VIPRenewalDate.text(date, appLanguage: .english)
        let turkish = VIPRenewalDate.text(date, appLanguage: .turkish)

        // Cihaz Locale.current değil, seçili uygulama dili kullanılmalı → çıktılar dile göre farklı.
        #expect(english != turkish)
        #expect(english.contains("Jan")) // en: Ocak → "Jan"
        #expect(turkish.contains("Oca")) // tr: Ocak → "Oca"
    }

    @Test func profilModelExposesBoundAppLanguage() {
        let prefs = MockPreferences()
        prefs.set("tr", for: ProfilePreferenceKeys.appLanguageCode)
        let language = LanguagePreferenceService(preferences: prefs)
        let model = ProfilModel(
            session: MockSession(),
            walletSummary: FakeWalletSummary(),
            analytics: MockAnalytics(),
            delegate: ProfileDelegateSpy(),
            appLanguage: language
        )
        #expect(model.appLanguage == .turkish)
    }
}
