import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import ProfileKit

/// SS-132 F2 — Google + e-posta bağlama, sağlayıcı-bağımsız ortak akıştan. Her sağlayıcı: `.linked`
/// (sıfır-kayıp — `userId` sunucuda korunur), 409 → conflict → switch, iptal/hata izole. Apple yolu
/// `HesapBaglamaModelTests` içinde regresyonsuz doğrulanır; burada aynı ortak akış Google/e-posta ile.
@MainActor
@Suite("SS-132 F2 HesapBaglamaModel — Google + e-posta (sağlayıcı-bağımsız)")
struct HesapBaglamaProviderLinkingTests {
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

    // MARK: - Google bağlama (F2)

    @Test func googleLinkingSuccessLinksZeroLossAndTracksProvider() async {
        // .linked → sıfır-kayıp (userId sunucuda korunur; client varlık kaybetmez) + provider "google".
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let account = AccountSummary(kind: .linked(provider: .google))
        let linking = FakeAccountLinking(link: .success(.linked(account)))
        let model = makeModel(linking: linking, analytics: analytics, delegate: spy)

        model.startGoogleLinking()
        await model.pendingWork()

        #expect(model.state == .linked(account))
        #expect(spy.linked == [account])
        #expect(model.activeProvider == .google)
        // Backend'e giden LinkCredential doğru sağlayıcıyı taşıdı (POST /auth/link provider alanı).
        #expect(linking.linkedProviderSequence == [.google])
        #expect(names(analytics) == ["link_account_started", "link_account_success"])
        #expect(analytics.events.first { $0.name == "link_account_success" }?
            .parameters["provider"] == .string("google"))
    }

    @Test func googleCancellationIsBenign() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let google = FakeGoogleSignIn(.failure(GoogleSignInError.cancelled))
        let linking = FakeAccountLinking()
        let model = makeModel(google: google, linking: linking, analytics: analytics, delegate: spy)

        model.startGoogleLinking()
        await model.pendingWork()

        #expect(model.state == .cancelled)
        #expect(spy.linked.isEmpty)
        #expect(linking.linkCallCount == 0) // backend'e hiç gitmedi
        #expect(names(analytics) == ["link_account_started"]) // yalnız started
    }

    @Test func googleFailureFailsWithGoogleUnavailable() async {
        let analytics = MockAnalytics()
        let model = makeModel(
            google: FakeGoogleSignIn(.failure(GoogleSignInError.failed)),
            analytics: analytics,
            delegate: HesapBaglamaDelegateSpy()
        )
        model.startGoogleLinking()
        await model.pendingWork()

        #expect(model.state == .failed(.googleUnavailable))
        #expect(names(analytics) == ["link_account_started", "link_account_failed"])
        #expect(analytics.events.last?.parameters["provider"] == .string("google"))
    }

    @Test func googleConflictSurfacesAndSwitchLinks() async {
        // 409 çakışma dalı sağlayıcı-bağımsız: Google akışında da conflict → switch → linked.
        let conflict = AccountLinkConflict(existingAccountMasked: "usr_**9a", switchToken: "swt_g", willDiscardGuestData: true)
        let switched = AccountSummary(kind: .linked(provider: .google))
        let linking = FakeAccountLinking(link: .success(.conflict(conflict)), switchTo: .success(switched))
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let model = makeModel(linking: linking, analytics: analytics, delegate: spy)

        model.startGoogleLinking()
        await model.pendingWork()
        #expect(model.state == .conflict(conflict))

        model.resolveConflictBySwitching()
        await model.pendingWork()

        #expect(model.state == .linked(switched))
        #expect(spy.linked == [switched])
        #expect(linking.switchCallCount == 1)
        // switch başarısı aktif sağlayıcıyı (google) korur.
        #expect(names(analytics) == ["link_account_started", "link_account_success"])
        #expect(analytics.events.last?.parameters["provider"] == .string("google"))
    }

    // MARK: - E-posta bağlama (F2)

    @Test func emailLinkingSuccessLinksZeroLossAndForwardsInputs() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let account = AccountSummary(kind: .linked(provider: .email))
        let emailPort = FakeEmailLink(.success(.stub))
        let linking = FakeAccountLinking(link: .success(.linked(account)))
        let model = makeModel(email: emailPort, linking: linking, analytics: analytics, delegate: spy)

        model.startEmailLinking(email: "user@example.com", password: "s3cret!!")
        await model.pendingWork()

        #expect(model.state == .linked(account))
        #expect(spy.linked == [account])
        #expect(model.activeProvider == .email)
        #expect(linking.linkedProviderSequence == [.email])
        // Girdiler porta iletildi; ham parola modelde kalmadan porta gitti.
        #expect(emailPort.lastEmail == "user@example.com")
        #expect(emailPort.lastPassword == "s3cret!!")
        #expect(names(analytics) == ["link_account_started", "link_account_success"])
        #expect(analytics.events.first?.parameters["provider"] == .string("email"))
    }

    @Test func emailCancellationIsBenign() async {
        let analytics = MockAnalytics()
        let spy = HesapBaglamaDelegateSpy()
        let emailPort = FakeEmailLink(.failure(EmailLinkError.cancelled))
        let linking = FakeAccountLinking()
        let model = makeModel(email: emailPort, linking: linking, analytics: analytics, delegate: spy)

        model.startEmailLinking(email: "user@example.com", password: "s3cret!!")
        await model.pendingWork()

        #expect(model.state == .cancelled)
        #expect(spy.linked.isEmpty)
        #expect(linking.linkCallCount == 0)
        #expect(names(analytics) == ["link_account_started"])
    }

    @Test func emailFailureFailsWithEmailUnavailable() async {
        let analytics = MockAnalytics()
        let model = makeModel(
            email: FakeEmailLink(.failure(EmailLinkError.failed)),
            analytics: analytics,
            delegate: HesapBaglamaDelegateSpy()
        )
        model.startEmailLinking(email: "user@example.com", password: "s3cret!!")
        await model.pendingWork()

        #expect(model.state == .failed(.emailUnavailable))
        #expect(names(analytics) == ["link_account_started", "link_account_failed"])
    }

    @Test func emailBackendErrorFailsWithLinkFailed() async {
        // Port başarılı ama backend link hata verirse → linkFailed (Apple ile aynı ayrım).
        let analytics = MockAnalytics()
        let model = makeModel(
            email: FakeEmailLink(.success(.stub)),
            linking: FakeAccountLinking(link: .failure(TestFailure())),
            analytics: analytics,
            delegate: HesapBaglamaDelegateSpy()
        )
        model.startEmailLinking(email: "user@example.com", password: "s3cret!!")
        await model.pendingWork()

        #expect(model.state == .failed(.linkFailed))
        #expect(names(analytics) == ["link_account_started", "link_account_failed"])
    }

    // MARK: - Sağlayıcılar izole + inFlightProvider

    @Test func providersAreIsolatedInFlightProviderReflectsActive() async {
        // Apple hata → failed; ardından Google başarı → linked. inFlightProvider akışa göre türer.
        let spy = HesapBaglamaDelegateSpy()
        let apple = FakeAppleSignIn(.failure(AppleSignInError.failed))
        let google = FakeGoogleSignIn(.success(.stub))
        let account = AccountSummary(kind: .linked(provider: .google))
        let linking = FakeAccountLinking(link: .success(.linked(account)))
        let model = makeModel(apple: apple, google: google, linking: linking, delegate: spy)

        model.startAppleLinking()
        await model.pendingWork()
        #expect(model.state == .failed(.appleUnavailable)) // Apple izole hata
        #expect(model.inFlightProvider == nil) // terminal → uçuşta değil

        model.startGoogleLinking()
        await model.pendingWork()
        #expect(model.state == .linked(account)) // Google akışı Apple hatasından etkilenmedi
        #expect(model.activeProvider == .google)
        #expect(linking.linkedProviderSequence == [.google])
    }

    // MARK: - LinkCredential sağlayıcı-bağımsız kimlik (provider alanı)

    @Test func linkCredentialCarriesProvider() {
        #expect(LinkCredential.apple(.stub).provider == .apple)
        #expect(LinkCredential.google(.stub).provider == .google)
        #expect(LinkCredential.email(.stub).provider == .email)
    }
}
