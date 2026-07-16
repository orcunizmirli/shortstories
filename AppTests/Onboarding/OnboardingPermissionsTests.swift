import Foundation
import XCTest
@testable import ShortSeriesApp

/// SS-064 / SS-156 — İzin adımı (adım 3) sonuç durumları: bildirim izni (verildi/reddedildi/ertelendi)
/// + ATT bayrağı/kapısı + tamamlanma süresi + registry drift guard'ı. Test double'ları
/// `OnboardingTestSupport`. Bu hedef CI'da KOŞMAZ (App target CI dışı); Xcode/lokal doğrulama içindir.
@MainActor
final class OnboardingPermissionsTests: XCTestCase {
    // MARK: - Bildirim izni sonuç durumları

    func testNotificationGrantedThenCompletesWhenAttDisabled() async {
        let harness = makeOnboardingHarness(notification: .granted, attEnabled: false)
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization()

        XCTAssertEqual(harness.model.notificationOutcome, .granted)
        XCTAssertEqual(harness.analytics.event(named: "onboarding_push_prompt")?.parameters["action"], .string("grant"))
        // ATT kapalı → tracking adımı atlanır, tamamlanır.
        XCTAssertNil(harness.analytics.event(named: "onboarding_att_prompt"))
        XCTAssertEqual(harness.model.completion, .completed)
    }

    func testNotificationDeniedOutcome() async {
        let harness = makeOnboardingHarness(notification: .denied, attEnabled: false)
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization()

        XCTAssertEqual(harness.model.notificationOutcome, .denied)
        XCTAssertEqual(harness.analytics.event(named: "onboarding_push_prompt")?.parameters["action"], .string("deny"))
    }

    func testNotificationDeferredEmitsNoPushEvent() {
        let harness = makeOnboardingHarness(attEnabled: false)
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        harness.model.deferNotifications() // "Şimdi değil" → sistem diyaloğu HİÇ tetiklenmez

        XCTAssertEqual(harness.model.notificationOutcome, .deferred)
        XCTAssertNil(harness.analytics.event(named: "onboarding_push_prompt"))
        XCTAssertFalse(harness.notification.wasRequested)
        XCTAssertEqual(harness.model.completion, .completed)
    }

    // MARK: - ATT sonuç durumları + bayrak/kapı

    func testAttPromptWhenEnabledAndNotDetermined() async {
        let harness = makeOnboardingHarness(
            notification: .granted,
            att: .authorized,
            attStatus: .notDetermined,
            attEnabled: true
        )
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization()
        XCTAssertEqual(harness.model.permissionsPhase, .trackingPrePrompt)
        XCTAssertNil(harness.model.completion) // henüz tamamlanmadı

        await harness.model.requestAppTracking()
        XCTAssertEqual(harness.model.trackingOutcome, .authorized)
        XCTAssertEqual(harness.analytics.event(named: "onboarding_att_prompt")?.parameters["action"], .string("authorized"))
        XCTAssertEqual(harness.model.completion, .completed)
    }

    func testAttSkippedWhenFlagDisabled() async {
        let harness = makeOnboardingHarness(notification: .granted, attStatus: .notDetermined, attEnabled: false)
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization()

        XCTAssertNotEqual(harness.model.permissionsPhase, .trackingPrePrompt)
        XCTAssertNil(harness.analytics.event(named: "onboarding_att_prompt"))
        XCTAssertEqual(harness.model.completion, .completed)
    }

    func testAttSkippedWhenAlreadyDeterminedGlobally() async {
        // 08 §9.1: ATT global reddedilmiş/kısıtlıysa istem HİÇ gösterilmez.
        let harness = makeOnboardingHarness(notification: .granted, attStatus: .denied, attEnabled: true)
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization()

        XCTAssertNotEqual(harness.model.permissionsPhase, .trackingPrePrompt)
        XCTAssertFalse(harness.tracking.wasRequested)
        XCTAssertNil(harness.analytics.event(named: "onboarding_att_prompt"))
        XCTAssertEqual(harness.model.completion, .completed)
    }

    func testDeferTrackingCompletesWithoutAttEvent() async {
        let harness = makeOnboardingHarness(notification: .granted, attStatus: .notDetermined, attEnabled: true)
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization()
        XCTAssertEqual(harness.model.permissionsPhase, .trackingPrePrompt)
        harness.model.deferTracking() // "Şimdi değil" → ATT sistem diyaloğu gösterilmez

        XCTAssertFalse(harness.tracking.wasRequested)
        XCTAssertNil(harness.analytics.event(named: "onboarding_att_prompt"))
        XCTAssertEqual(harness.model.completion, .completed)
    }

    func testAttActionMapping() {
        XCTAssertEqual(AppTrackingAuthorizationResult.restricted.analyticsAction, "restricted")
        XCTAssertEqual(AppTrackingAuthorizationResult.notDetermined.analyticsAction, "not_determined")
        XCTAssertEqual(AppTrackingAuthorizationResult.authorized.analyticsAction, "authorized")
        XCTAssertEqual(AppTrackingAuthorizationResult.denied.analyticsAction, "denied")
    }

    // MARK: - Tamamlanma + süre

    func testCompleteMeasuresDurationAndSetsFlag() async {
        let clock = OnboardingMutableClock(start: Date(timeIntervalSince1970: 1000))
        let harness = makeOnboardingHarness(notification: .granted, attEnabled: false, now: clock.now)
        harness.model.start() // t = 1000
        clock.advance(by: 7.4) // kullanıcı 7.4 sn geçirir
        harness.model.advance() // language → genre
        harness.model.advance() // genre → permissions
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization()

        let complete = harness.analytics.event(named: "onboarding_complete")
        XCTAssertEqual(complete?.parameters["duration_s"], .int(7)) // 7.4 → yuvarlanır
        XCTAssertTrue(harness.preferences.bool(for: "onboarding.completed"))
        XCTAssertEqual(harness.finishedWith, .completed)
    }

    // MARK: - Registry drift guard'ı

    func testEveryEmittedOnboardingEventIsRegistered() async {
        let harness = makeOnboardingHarness(
            notification: .granted,
            att: .authorized,
            attStatus: .notDetermined,
            attEnabled: true
        )
        // Tam akış: her onboarding event tipini üret.
        harness.model.start()
        harness.model.selectLanguage(.turkish)
        harness.model.advance() // language_select
        harness.model.toggleGenre("romance")
        harness.model.advance() // genre_select
        harness.model.continueFromValueProposition()
        await harness.model.requestNotificationAuthorization() // push_prompt
        await harness.model.requestAppTracking() // att_prompt + complete

        let emitted = Set(harness.analytics.eventNames)
        XCTAssertTrue(emitted.isSuperset(of: [
            "onboarding_start", "onboarding_step_view", "onboarding_language_select",
            "onboarding_genre_select", "onboarding_push_prompt", "onboarding_att_prompt",
            "onboarding_complete"
        ]))
        for name in emitted {
            XCTAssertEqual(
                AnalyticsEventRegistry.validate(name), .valid,
                "emit edilen '\(name)' registry'de KAYITLI değil (08 §2.3)"
            )
        }
    }
}
