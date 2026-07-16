import AppFoundation
import ProfileKit
import XCTest
@testable import ShortSeriesApp

/// SS-064 — Onboarding adım DURUM MAKİNESİ testleri (dil → tür → izin; ileri/geri/atla). İzin sonuç
/// durumları ayrı dosyadadır (`OnboardingPermissionsTests`). Test double'ları `OnboardingTestSupport`.
@MainActor
final class OnboardingModelTests: XCTestCase {
    // MARK: - start / adım görünürlüğü

    func testStartEmitsStartThenFirstStepViewOnce() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.start() // idempotent

        XCTAssertEqual(harness.analytics.eventNames, ["onboarding_start", "onboarding_step_view"])
        let stepView = harness.analytics.events[1]
        XCTAssertEqual(stepView.parameters["step"], .string("language"))
        XCTAssertEqual(stepView.parameters["step_index"], .int(0))
        XCTAssertEqual(harness.model.step, .language)
    }

    // MARK: - Adım 1: dil

    func testLanguageAdvanceCommitsAndEmitsSelect() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.selectLanguage(.turkish)
        harness.model.advance()

        XCTAssertEqual(harness.language.lastSet, .turkish)
        XCTAssertEqual(harness.model.step, .genre)
        let select = harness.analytics.event(named: "onboarding_language_select")
        XCTAssertEqual(select?.parameters["language"], .string("tr"))
        // Dil adımından tür adımına geçince step_view(genre, 1) atılır.
        let genreStepView = harness.analytics.events.last
        XCTAssertEqual(genreStepView?.name, "onboarding_step_view")
        XCTAssertEqual(genreStepView?.parameters["step_index"], .int(1))
    }

    /// Kanon: seçim GERÇEK `LanguagePreferenceService`'e yazılır (composition-intended yol).
    func testLanguageWritesToRealLanguagePreferenceService() {
        let prefs = OnboardingInMemoryPreferences()
        let service = LanguagePreferenceService(preferences: prefs)
        let harness = makeOnboardingHarness(language: service, preferences: prefs)
        harness.model.start()
        harness.model.selectLanguage(.spanish)
        harness.model.advance()

        XCTAssertEqual(service.appLanguage, .spanish)
    }

    // MARK: - Adım 2: tür (seç / atla)

    func testGenreSelectionPersistsInCatalogOrderAndEmits() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.advance() // → genre
        // Ters sırada seç; persist katalog sırasını korumalı (deterministik).
        harness.model.toggleGenre("revenge")
        harness.model.toggleGenre("romance")
        harness.model.advance() // → permissions (commit)

        XCTAssertEqual(
            harness.preferences.string(for: "onboarding.selected_genres"),
            "romance,revenge"
        )
        let genre = harness.analytics.event(named: "onboarding_genre_select")
        XCTAssertEqual(genre?.parameters["genres"], .string("romance,revenge"))
        XCTAssertEqual(genre?.parameters["genre_count"], .int(2))
        XCTAssertEqual(harness.model.step, .permissions)
    }

    func testGenreSkipEmitsNoGenreEventAndDoesNotPersist() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.advance() // → genre
        harness.model.toggleGenre("romance") // seçim var ama ATLA basılıyor
        harness.model.skipGenreStep()

        XCTAssertNil(harness.analytics.event(named: "onboarding_genre_select"))
        XCTAssertEqual(harness.preferences.string(for: "onboarding.selected_genres"), "")
        XCTAssertEqual(harness.model.step, .permissions)
        XCTAssertEqual(harness.analytics.events.last?.parameters["step"], .string("permissions"))
    }

    func testAdvanceWithoutGenreSelectionEmitsNoGenreEvent() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.advance() // → genre
        harness.model.advance() // "Devam" seçimsiz → permissions, genre_select YOK

        XCTAssertNil(harness.analytics.event(named: "onboarding_genre_select"))
        XCTAssertEqual(harness.model.step, .permissions)
    }

    // MARK: - Geri

    func testBackReturnsToPreviousStepAndReemitsStepView() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.advance() // → genre
        harness.analytics.reset()
        harness.model.back() // → language

        XCTAssertEqual(harness.model.step, .language)
        XCTAssertEqual(harness.analytics.events.count, 1)
        XCTAssertEqual(harness.analytics.events.first?.name, "onboarding_step_view")
        XCTAssertEqual(harness.analytics.events.first?.parameters["step"], .string("language"))
    }

    func testBackFromPermissionsResetsPhaseToGenre() {
        let harness = makeOnboardingHarness()
        harness.driveToPermissions()
        harness.model.continueFromValueProposition()
        XCTAssertEqual(harness.model.permissionsPhase, .notificationPrePrompt)
        harness.model.back() // → genre

        XCTAssertEqual(harness.model.step, .genre)
        XCTAssertEqual(harness.model.permissionsPhase, .valueProposition)
    }

    // MARK: - Skip (flow-abandon)

    func testSkipEmitsSkipAtCurrentStepAndMarksCompleted() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.advance() // → genre
        harness.model.skip()

        let skip = harness.analytics.event(named: "onboarding_skip")
        XCTAssertEqual(skip?.parameters["skipped_at_step"], .string("genre"))
        XCTAssertEqual(harness.model.completion, .skipped)
        XCTAssertTrue(harness.preferences.bool(for: "onboarding.completed"))
        XCTAssertEqual(harness.finishedWith, .skipped)
    }

    func testSkipIsIdempotent() {
        let harness = makeOnboardingHarness()
        harness.model.start()
        harness.model.skip()
        harness.model.skip()

        XCTAssertEqual(harness.analytics.events.filter { $0.name == "onboarding_skip" }.count, 1)
    }
}
