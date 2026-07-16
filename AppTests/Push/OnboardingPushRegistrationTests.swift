import AppFoundation
import XCTest
@testable import ShortSeriesApp

/// SS-140 — Onboarding bildirim izni SONUCU APNs kaydını tetikler mi? İzin VERİLİNCE `register
/// ForRemoteNotifications()` çağrılır (token akışı başlar); reddedilirse/ertelenirse çağrılmaz
/// (izin yoksa kayıt yok — 01 ONB-05 hak yakmaz). Test double'ları `OnboardingTestSupport` + `PushTestSupport`.
@MainActor
final class OnboardingPushRegistrationTests: XCTestCase {
    private func makeModel(
        notification: NotificationAuthorizationResult,
        remote: SpyRemoteNotificationRegistering
    ) -> OnboardingModel {
        OnboardingModel(
            initialLanguage: .english,
            genreOptions: OnboardingGenreCatalog.embedded,
            language: OnboardingFakeLanguageWriter(),
            preferences: OnboardingInMemoryPreferences(),
            notifications: OnboardingFakeNotificationRequester(result: notification),
            tracking: OnboardingFakeTrackingRequester(status: .notDetermined, result: .authorized),
            analytics: OnboardingSpyAnalytics(),
            attEnabled: false,
            remoteNotifications: remote
        )
    }

    private func driveToNotificationPrePrompt(_ model: OnboardingModel) {
        model.start()
        model.advance() // language → genre
        model.advance() // genre → permissions (valueProposition)
        model.continueFromValueProposition() // → notificationPrePrompt
    }

    func testGrantTriggersRemoteRegistration() async {
        let remote = SpyRemoteNotificationRegistering()
        let model = makeModel(notification: .granted, remote: remote)
        driveToNotificationPrePrompt(model)

        await model.requestNotificationAuthorization()

        XCTAssertEqual(remote.count, 1)
    }

    func testDenyDoesNotTriggerRemoteRegistration() async {
        let remote = SpyRemoteNotificationRegistering()
        let model = makeModel(notification: .denied, remote: remote)
        driveToNotificationPrePrompt(model)

        await model.requestNotificationAuthorization()

        XCTAssertEqual(remote.count, 0)
    }

    func testDeferDoesNotTriggerRemoteRegistration() {
        let remote = SpyRemoteNotificationRegistering()
        let model = makeModel(notification: .granted, remote: remote)
        driveToNotificationPrePrompt(model)

        model.deferNotifications() // "Şimdi değil" — sistem diyaloğu tetiklenmez → kayıt yok

        XCTAssertEqual(remote.count, 0)
    }
}
