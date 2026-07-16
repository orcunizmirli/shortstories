import AppFoundation
import DiscoverKit
import Foundation
import ProfileKit
import XCTest
@testable import ShortSeriesApp

/// SS-060 / SS-064 — Launch routing DURUM MAKİNESİ testleri: `Splash → Onboarding | Tabs` geçişleri,
/// onboarding-tamamlandı geçişi, tekrar-açılışta onboarding atlanması ve soğuk-açılış deep-link
/// `PendingRoute` etkileşimi (03 §3.1/§3.2 kural 6). `LaunchCoordinator` kompozisyondan bağımsızdır →
/// closure/fake enjeksiyonuyla ağır kök kurmadan koşar. Bu hedef CI'da KOŞMAZ (App target CI dışı).
@MainActor
final class LaunchCoordinatorTests: XCTestCase {
    // MARK: - Cold-start routing kararı (Splash → Onboarding | Tabs)

    func testColdStartWithoutOnboardingGoesDirectlyToTabs() async {
        let harness = makeLaunchHarness(onboardingCompleted: true)
        await harness.coordinator.runLaunchSequence()

        XCTAssertEqual(harness.coordinator.launchState, .tabs)
        XCTAssertNil(harness.coordinator.onboardingModel)
    }

    func testColdStartRequiringOnboardingPresentsOnboarding() async {
        let harness = makeLaunchHarness(onboardingCompleted: false)
        await harness.coordinator.runLaunchSequence()

        XCTAssertEqual(harness.coordinator.launchState, .onboarding)
        XCTAssertNotNil(harness.coordinator.onboardingModel)
    }

    func testSplashRunsColdStartPreloadBeforeRouting() async {
        let ran = PreloadFlag()
        let harness = makeLaunchHarness(onboardingCompleted: true, preload: { ran.value = true })
        await harness.coordinator.runLaunchSequence()

        XCTAssertTrue(ran.value, "SS-060: routing kararından önce çekirdek ön-yükleme çalışmalı")
        XCTAssertEqual(harness.coordinator.launchState, .tabs)
    }

    // MARK: - Onboarding tamamlanma geçişi (completed / skipped → Tabs)

    func testOnboardingCompletionTransitionsToTabs() async {
        let harness = makeLaunchHarness(onboardingCompleted: false)
        await harness.coordinator.runLaunchSequence()
        XCTAssertNotNil(harness.coordinator.onboardingModel)

        driveOnboardingToCompletion(harness.coordinator.onboardingModel)

        XCTAssertEqual(harness.coordinator.launchState, .tabs)
        XCTAssertNil(harness.coordinator.onboardingModel)
    }

    func testOnboardingSkipTransitionsToTabs() async {
        let harness = makeLaunchHarness(onboardingCompleted: false)
        await harness.coordinator.runLaunchSequence()
        harness.coordinator.onboardingModel?.skip()

        XCTAssertEqual(harness.coordinator.launchState, .tabs)
        XCTAssertNil(harness.coordinator.onboardingModel)
    }

    // MARK: - Tekrar açılışta onboarding atlanır (bayrak persistleşti)

    func testRelaunchSkipsOnboardingAfterCompletion() async {
        // 1. açılış: onboarding gerekli → tamamla (model bayrağı paylaşılan prefs'e yazar).
        let prefs = LaunchInMemoryPreferences()
        let first = makeLaunchHarness(preferences: prefs)
        await first.coordinator.runLaunchSequence()
        XCTAssertEqual(first.coordinator.launchState, .onboarding)
        driveOnboardingToCompletion(first.coordinator.onboardingModel)
        XCTAssertEqual(first.coordinator.launchState, .tabs)
        XCTAssertTrue(prefs.value(for: PreferenceKeys.onboardingCompleted))

        // 2. açılış: AYNI prefs (bayrak true) → doğrudan Tab'lar, onboarding gösterilmez.
        let second = makeLaunchHarness(preferences: prefs)
        XCTAssertFalse(second.coordinator.needsOnboarding)
        await second.coordinator.runLaunchSequence()
        XCTAssertEqual(second.coordinator.launchState, .tabs)
        XCTAssertNil(second.coordinator.onboardingModel)
    }

    // MARK: - Deep-link PendingRoute etkileşimi (03 §3.2 kural 6)

    func testDeepLinkDuringSplashIsDeferredUntilTabs() async {
        let harness = makeLaunchHarness(onboardingCompleted: true)
        // Splash sırasında (henüz launch dizisi koşmadan) gelen rota düşürülmez, bekletilir.
        harness.coordinator.dispatch(.home, source: .universal)
        XCTAssertEqual(harness.coordinator.pendingRoute, .home)
        XCTAssertTrue(harness.dispatched.isEmpty, "Splash'ta rota Tab'lara delege EDİLMEZ")

        await harness.coordinator.runLaunchSequence()

        XCTAssertEqual(harness.coordinator.launchState, .tabs)
        XCTAssertNil(harness.coordinator.pendingRoute, "Tab'lara geçince bekleyen rota temizlenir")
        XCTAssertEqual(harness.dispatched.records.map(\.route), [.home])
        XCTAssertEqual(harness.dispatched.records.first?.source, .universal, "Menşe korunur")
    }

    func testDeepLinkDuringOnboardingAppliedAfterCompletion() async {
        let harness = makeLaunchHarness(onboardingCompleted: false)
        await harness.coordinator.runLaunchSequence()
        XCTAssertEqual(harness.coordinator.launchState, .onboarding)

        // Onboarding sırasında gelen deep link bekletilir (kural 6): Onboarding rotayı düşürmez.
        harness.coordinator.dispatch(.series(id: SeriesID("srs_1")), source: .push)
        XCTAssertTrue(harness.dispatched.isEmpty)
        XCTAssertEqual(harness.coordinator.pendingRoute, .series(id: SeriesID("srs_1")))

        driveOnboardingToCompletion(harness.coordinator.onboardingModel)

        XCTAssertEqual(harness.coordinator.launchState, .tabs)
        XCTAssertEqual(harness.dispatched.records.map(\.route), [.series(id: SeriesID("srs_1"))])
        XCTAssertEqual(harness.dispatched.records.first?.source, .push)
        XCTAssertNil(harness.coordinator.pendingRoute)
    }

    func testDeepLinkAfterTabsDispatchesImmediately() async {
        let harness = makeLaunchHarness(onboardingCompleted: true)
        await harness.coordinator.runLaunchSequence()
        XCTAssertEqual(harness.coordinator.launchState, .tabs)

        harness.coordinator.dispatch(.profile, source: .universal)

        XCTAssertNil(harness.coordinator.pendingRoute)
        XCTAssertEqual(harness.dispatched.records.map(\.route), [.profile])
    }

    func testOnlyLastPendingRouteIsKept() async {
        let harness = makeLaunchHarness(onboardingCompleted: true)
        harness.coordinator.dispatch(.home, source: .universal)
        harness.coordinator.dispatch(.profile, source: .push)
        XCTAssertEqual(harness.coordinator.pendingRoute, .profile)

        await harness.coordinator.runLaunchSequence()

        XCTAssertEqual(harness.dispatched.records.map(\.route), [.profile])
        XCTAssertEqual(harness.dispatched.records.first?.source, .push)
    }

    // MARK: - Guard'lar / idempotency

    func testRunLaunchSequenceAfterTabsDoesNotReRoute() async {
        let harness = makeLaunchHarness(onboardingCompleted: false)
        await harness.coordinator.runLaunchSequence() // → onboarding
        driveOnboardingToCompletion(harness.coordinator.onboardingModel) // → tabs

        // Tekrar çağrı: advanceFromSplash guard'ı (.splash değil) → durum değişmez.
        await harness.coordinator.runLaunchSequence()
        XCTAssertEqual(harness.coordinator.launchState, .tabs)
    }

    func testBeginLaunchEventuallyReachesTabs() async {
        let harness = makeLaunchHarness(onboardingCompleted: true)
        harness.coordinator.beginLaunch()
        harness.coordinator.beginLaunch() // idempotent — ikinci çağrı yeni dizi başlatmaz

        await waitUntil { harness.coordinator.launchState == .tabs }
        XCTAssertEqual(harness.coordinator.launchState, .tabs)
    }
}

// MARK: - Harness + fakes

@MainActor
private struct LaunchHarness {
    let coordinator: LaunchCoordinator
    let preferences: LaunchInMemoryPreferences
    let dispatched: LaunchDispatchSpy
}

@MainActor
private func makeLaunchHarness(
    onboardingCompleted: Bool? = nil,
    preferences: LaunchInMemoryPreferences = LaunchInMemoryPreferences(),
    preload: @escaping @MainActor () async -> Void = {}
) -> LaunchHarness {
    // Yalnız açıkça verilince tohumla; `nil` iken mevcut (persistleşmiş) değeri KORU → relaunch testi
    // ilk açılışta yazılan bayrağı ikinci açılışta okuyabilsin.
    if let onboardingCompleted {
        preferences.set(onboardingCompleted, for: PreferenceKeys.onboardingCompleted)
    }
    let dispatched = LaunchDispatchSpy()
    let coordinator = LaunchCoordinator(
        preferences: preferences,
        preload: preload,
        makeOnboarding: { onFinish in makeLaunchTestOnboardingModel(preferences: preferences, onFinish: onFinish) },
        dispatchToTabs: { route, source in dispatched.record(route, source) },
        minimumSplashDuration: .zero,
        sleep: { _ in } // deterministik: splash zeminini anında geç
    )
    return LaunchHarness(coordinator: coordinator, preferences: preferences, dispatched: dispatched)
}

/// Onboarding modelini gerçek adım makinesiyle kurar; `preferences` LaunchCoordinator ile PAYLAŞILIR ki
/// tamamlanınca yazılan `onboardingCompleted` bayrağı relaunch testinde görünür.
@MainActor
private func makeLaunchTestOnboardingModel(
    preferences: any PreferencesStoring,
    onFinish: @escaping @MainActor (OnboardingModel.Completion) -> Void
) -> OnboardingModel {
    OnboardingModel(
        initialLanguage: .english,
        genreOptions: OnboardingGenreCatalog.embedded,
        language: OnboardingFakeLanguageWriter(),
        preferences: preferences,
        notifications: OnboardingFakeNotificationRequester(result: .granted),
        tracking: OnboardingFakeTrackingRequester(status: .notDetermined, result: .authorized),
        analytics: OnboardingSpyAnalytics(),
        attEnabled: false,
        onFinish: onFinish
    )
}

/// Onboarding'i (ATT kapalı) tamamlanmaya (completed) sürer: dil → tür → değer önerisi → bildirim ertele.
@MainActor
private func driveOnboardingToCompletion(_ model: OnboardingModel?) {
    guard let model else { return }
    model.start()
    model.advance() // language → genre
    model.advance() // genre → permissions (valueProposition)
    model.continueFromValueProposition() // → notificationPrePrompt
    model.deferNotifications() // ATT kapalı → complete(.completed)
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition(), clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private final class LaunchDispatchSpy {
    struct Record {
        let route: DeepLinkRoute
        let source: DeepLinkSource
    }

    private(set) var records: [Record] = []

    var isEmpty: Bool {
        records.isEmpty
    }

    func record(_ route: DeepLinkRoute, _ source: DeepLinkSource) {
        records.append(Record(route: route, source: source))
    }
}

@MainActor
private final class PreloadFlag {
    var value = false
}

private final class LaunchInMemoryPreferences: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: any PreferenceValue] = [:]

    func value<V: PreferenceValue>(for key: PreferenceKey<V>) -> V {
        lock.withLock { storage[key.name] as? V ?? key.default }
    }

    func set<V: PreferenceValue>(_ value: V, for key: PreferenceKey<V>) {
        lock.withLock { storage[key.name] = value }
    }

    func removeValue(for key: PreferenceKey<some PreferenceValue>) {
        lock.withLock { storage[key.name] = nil }
    }
}
