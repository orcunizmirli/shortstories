import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import ProfileKit

@MainActor
@Suite("SS-132 HesapBaglamaModel (durum makinesi, çakışma, iptal, analitik)")
struct HesapBaglamaModelTests {
    private func makeModel(
        apple: FakeAppleSignIn = FakeAppleSignIn(),
        google: FakeGoogleSignIn = FakeGoogleSignIn(),
        email: FakeEmailLink = FakeEmailLink(),
        linking: FakeAccountLinking = FakeAccountLinking(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: HesapBaglamaDelegateSpy
    ) -> HesapBaglamaModel {
        HesapBaglamaModel(
            appleSignIn: apple,
            googleSignIn: google,
            emailLink: email,
            linking: linking,
            analytics: analytics,
            delegate: delegate
        )
    }

    private func names(_ analytics: MockAnalytics) -> [String] {
        analytics.eventNames.filter { $0.hasPrefix("link_account_") }
    }

    // MARK: - Başlangıç

    @Test func startsIdle() {
        let model = makeModel(delegate: HesapBaglamaDelegateSpy())
        #expect(model.state == .idle)
    }

    // MARK: - Başarı yolu (idle → linking → linked)

    @Test func appleLinkingSuccessLinksAndTracks() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let account = AccountSummary(kind: .linked(provider: .apple))
        let model = makeModel(
            linking: FakeAccountLinking(link: .success(.linked(account))),
            analytics: analytics,
            delegate: spy
        )
        model.startAppleLinking()
        await model.pendingWork()

        #expect(model.state == .linked(account))
        #expect(spy.linked == [account])
        // started + success; failed YOK.
        #expect(names(analytics) == ["link_account_started", "link_account_success"])
        #expect(analytics.events.first { $0.name == "link_account_started" }?
            .parameters["provider"] == .string("apple"))
    }

    // MARK: - İptal (benign — success/failed ÜRETMEZ)

    @Test func appleCancellationIsBenign() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let apple = FakeAppleSignIn(.failure(AppleSignInError.cancelled))
        let linking = FakeAccountLinking()
        let model = makeModel(apple: apple, linking: linking, analytics: analytics, delegate: spy)
        model.startAppleLinking()
        await model.pendingWork()

        #expect(model.state == .cancelled)
        #expect(spy.linked.isEmpty)
        #expect(linking.linkCallCount == 0) // backend'e hiç gitmedi
        #expect(names(analytics) == ["link_account_started"]) // yalnız started
    }

    // MARK: - Apple hatası (gerçek hata → failed)

    @Test func appleFailureFails() async {
        let analytics = MockAnalytics()
        let model = makeModel(
            apple: FakeAppleSignIn(.failure(AppleSignInError.failed)),
            analytics: analytics,
            delegate: HesapBaglamaDelegateSpy()
        )
        model.startAppleLinking()
        await model.pendingWork()

        #expect(model.state == .failed(.appleUnavailable))
        #expect(names(analytics) == ["link_account_started", "link_account_failed"])
    }

    // MARK: - Backend hatası → failed

    @Test func backendLinkErrorFails() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let model = makeModel(
            linking: FakeAccountLinking(link: .failure(TestFailure())),
            analytics: analytics,
            delegate: spy
        )
        model.startAppleLinking()
        await model.pendingWork()

        #expect(model.state == .failed(.linkFailed))
        #expect(spy.linked.isEmpty)
        #expect(names(analytics) == ["link_account_started", "link_account_failed"])
    }

    // MARK: - Çakışma (409) dalı

    @Test func conflictSurfacesWithoutTerminalAnalytics() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let conflict = AccountLinkConflict(
            existingAccountMasked: "usr_**12ef",
            switchToken: "swt_77x",
            willDiscardGuestData: true
        )
        let model = makeModel(
            linking: FakeAccountLinking(link: .success(.conflict(conflict))),
            analytics: analytics,
            delegate: spy
        )
        model.startAppleLinking()
        await model.pendingWork()

        #expect(model.state == .conflict(conflict))
        #expect(spy.linked.isEmpty)
        // Henüz karar yok: yalnız started (success/failed YOK).
        #expect(names(analytics) == ["link_account_started"])
    }

    @Test func conflictResolveBySwitchingLinks() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let conflict = AccountLinkConflict(
            existingAccountMasked: "usr_**12ef",
            switchToken: "swt_77x",
            willDiscardGuestData: false
        )
        let switched = AccountSummary(kind: .linked(provider: .apple))
        let linking = FakeAccountLinking(link: .success(.conflict(conflict)), switchTo: .success(switched))
        let model = makeModel(linking: linking, analytics: analytics, delegate: spy)

        model.startAppleLinking()
        await model.pendingWork()
        #expect(model.state == .conflict(conflict))

        model.resolveConflictBySwitching()
        await model.pendingWork()

        #expect(model.state == .linked(switched))
        #expect(linking.switchCallCount == 1)
        #expect(spy.linked == [switched])
        #expect(names(analytics) == ["link_account_started", "link_account_success"])
    }

    @Test func conflictSwitchFailureFails() async {
        let analytics = MockAnalytics()
        let conflict = AccountLinkConflict(existingAccountMasked: "usr_**1", switchToken: "s", willDiscardGuestData: false)
        let linking = FakeAccountLinking(link: .success(.conflict(conflict)), switchTo: .failure(TestFailure()))
        let model = makeModel(linking: linking, analytics: analytics, delegate: HesapBaglamaDelegateSpy())

        model.startAppleLinking()
        await model.pendingWork()
        model.resolveConflictBySwitching()
        await model.pendingWork()

        #expect(model.state == .failed(.linkFailed))
        #expect(names(analytics) == ["link_account_started", "link_account_failed"])
    }

    @Test func conflictCancelIsBenign() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let conflict = AccountLinkConflict(existingAccountMasked: "usr_**1", switchToken: "s", willDiscardGuestData: true)
        let linking = FakeAccountLinking(link: .success(.conflict(conflict)))
        let model = makeModel(linking: linking, analytics: analytics, delegate: spy)

        model.startAppleLinking()
        await model.pendingWork()
        model.cancelConflict()

        #expect(model.state == .cancelled)
        #expect(linking.switchCallCount == 0)
        #expect(spy.linked.isEmpty)
        #expect(names(analytics) == ["link_account_started"]) // vazgeçmek benign
    }

    // MARK: - Çift-tetik koruması + reset

    @Test func resetReturnsToIdleFromTerminal() async {
        let model = makeModel(
            apple: FakeAppleSignIn(.failure(AppleSignInError.failed)),
            delegate: HesapBaglamaDelegateSpy()
        )
        model.startAppleLinking()
        await model.pendingWork()
        #expect(model.state == .failed(.appleUnavailable))
        model.reset()
        #expect(model.state == .idle)
    }

    @Test func resolveConflictOnlyValidFromConflict() {
        // conflict değilken switch NO-OP (backend'e gitmez).
        let linking = FakeAccountLinking()
        let model = makeModel(linking: linking, delegate: HesapBaglamaDelegateSpy())
        model.resolveConflictBySwitching()
        #expect(linking.switchCallCount == 0)
        #expect(model.state == .idle)
    }

    // MARK: - .linked terminal-başarı kilidi (çift oturum-yükseltme koruması)

    @Test func startLinkingAfterLinkedIsNoOp() async {
        // .linked terminal-başarı: startAppleLinking() yeniden TETİKLENEMEZ → ikinci didLink +
        // link_account_success ÜRETİLMEZ (çift oturum-yükseltme + funnel çift-sayım koruması).
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let account = AccountSummary(kind: .linked(provider: .apple))
        let apple = FakeAppleSignIn(.success(.stub))
        let model = makeModel(
            apple: apple,
            linking: FakeAccountLinking(link: .success(.linked(account))),
            analytics: analytics,
            delegate: spy
        )
        model.startAppleLinking()
        await model.pendingWork()
        #expect(model.state == .linked(account))
        #expect(spy.linked == [account])

        // İkinci tetik — no-op olmalı (Apple'a gidilmez, didLink/success tekrarlanmaz).
        model.startAppleLinking()
        await model.pendingWork()

        #expect(model.state == .linked(account))
        #expect(spy.linked == [account]) // hâlâ tek
        #expect(apple.callCount == 1) // ikinci Apple çağrısı yok
        #expect(names(analytics) == ["link_account_started", "link_account_success"]) // tek çift
    }

    // MARK: - .conflict meşgul: karar beklerken yeni akış çakışmayı düşürmez

    @Test func startLinkingDuringConflictDoesNotDropConflict() async {
        // Çakışma kararı beklerken startAppleLinking() → bekleyen conflict+switchToken SESSİZCE
        // düşmemeli (conflict→switching atlanmasın); kullanıcı açıkça switch/cancel seçmeli.
        let conflict = AccountLinkConflict(
            existingAccountMasked: "usr_**12ef",
            switchToken: "swt_77x",
            willDiscardGuestData: false
        )
        let apple = FakeAppleSignIn(.success(.stub))
        let linking = FakeAccountLinking(link: .success(.conflict(conflict)))
        let model = makeModel(apple: apple, linking: linking, delegate: HesapBaglamaDelegateSpy())

        model.startAppleLinking()
        await model.pendingWork()
        #expect(model.state == .conflict(conflict))

        model.startAppleLinking() // no-op olmalı
        await model.pendingWork()

        #expect(model.state == .conflict(conflict)) // conflict korundu
        #expect(apple.callCount == 1) // ikinci Apple çağrısı yok
    }

    @Test func resetDuringConflictDoesNotDropConflict() async {
        // reset() de çakışma kararını sessizce düşürmemeli — yalnız switch/cancel çıkış yoludur.
        let conflict = AccountLinkConflict(
            existingAccountMasked: "usr_**12ef",
            switchToken: "swt_77x",
            willDiscardGuestData: false
        )
        let linking = FakeAccountLinking(link: .success(.conflict(conflict)))
        let model = makeModel(linking: linking, delegate: HesapBaglamaDelegateSpy())

        model.startAppleLinking()
        await model.pendingWork()
        #expect(model.state == .conflict(conflict))

        model.reset() // no-op olmalı
        #expect(model.state == .conflict(conflict))
    }

    @Test func dismissInvokesDelegate() {
        let spy = HesapBaglamaDelegateSpy()
        let model = makeModel(delegate: spy)
        model.dismiss()
        #expect(spy.dismissed == 1)
    }

    // MARK: - Ham Apple/nesne sızmıyor (değer-tipi doğrulaması)

    @Test func appleCredentialIsPlainValueType() {
        // Public yüzey yalnız SAF alanlar taşır — ham ASAuthorization YOK (bu dosya AuthenticationServices
        // import ETMEZ ve derlenir → sızıntı yok). İkinci girişte email/fullName nil kalır.
        let credential = AppleCredential(identityToken: "jwt", userIdentifier: "u1")
        #expect(credential.email == nil)
        #expect(credential.fullName == nil)
        #expect(credential == AppleCredential(identityToken: "jwt", userIdentifier: "u1"))
    }
}
