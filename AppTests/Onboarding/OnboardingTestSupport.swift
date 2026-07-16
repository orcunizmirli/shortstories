import AppFoundation
import Foundation
import ProfileKit
@testable import ShortSeriesApp

// SS-064 — Onboarding testleri için paylaşılan test double'ları + harness. Dış sistemler (bildirim
// izni, ATT) fake port'larla sürülür → gerçek sistem izni olmadan koşar. Bu hedef CI'da KOŞMAZ (App
// target CI dışı); Xcode/lokal doğrulama içindir. Adlar `Onboarding*` ön ekiyle çakışmayı önler.

/// Kurulmuş model + gözlem noktaları.
@MainActor
struct OnboardingHarness {
    let model: OnboardingModel
    let analytics: OnboardingSpyAnalytics
    let preferences: OnboardingInMemoryPreferences
    let language: OnboardingFakeLanguageWriter
    let notification: OnboardingFakeNotificationRequester
    let tracking: OnboardingFakeTrackingRequester
    let finishBox: OnboardingFinishBox

    var finishedWith: OnboardingModel.Completion? {
        finishBox.value
    }

    /// Dil + tür adımını geçip izin adımına (adım 3) sürer.
    func driveToPermissions() {
        model.start()
        model.advance() // language → genre
        model.advance() // genre → permissions
    }
}

@MainActor
func makeOnboardingHarness(
    language languageService: (any OnboardingLanguageWriting)? = nil,
    preferences: OnboardingInMemoryPreferences = OnboardingInMemoryPreferences(),
    notification: NotificationAuthorizationResult = .granted,
    att: AppTrackingAuthorizationResult = .authorized,
    attStatus: AppTrackingAuthorizationResult = .notDetermined,
    attEnabled: Bool = false,
    now: @escaping () -> Date = { Date() }
) -> OnboardingHarness {
    let analytics = OnboardingSpyAnalytics()
    let fakeLanguage = OnboardingFakeLanguageWriter()
    let notif = OnboardingFakeNotificationRequester(result: notification)
    let track = OnboardingFakeTrackingRequester(status: attStatus, result: att)
    let finishBox = OnboardingFinishBox()
    let model = OnboardingModel(
        initialLanguage: .english,
        genreOptions: OnboardingGenreCatalog.embedded,
        language: languageService ?? fakeLanguage,
        preferences: preferences,
        notifications: notif,
        tracking: track,
        analytics: analytics,
        attEnabled: attEnabled,
        now: now,
        onFinish: { finishBox.value = $0 }
    )
    return OnboardingHarness(
        model: model,
        analytics: analytics,
        preferences: preferences,
        language: fakeLanguage,
        notification: notif,
        tracking: track,
        finishBox: finishBox
    )
}

// MARK: - Test double'ları

final class OnboardingFinishBox: @unchecked Sendable {
    var value: OnboardingModel.Completion?
}

final class OnboardingSpyAnalytics: AnalyticsTracking, @unchecked Sendable {
    struct Event: Equatable {
        let name: String
        let parameters: [String: AnalyticsValue]
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    var events: [Event] {
        lock.withLock { recorded }
    }

    var eventNames: [String] {
        events.map(\.name)
    }

    func event(named name: String) -> Event? {
        events.first { $0.name == name }
    }

    func reset() {
        lock.withLock { recorded.removeAll() }
    }

    func track(_ name: String, parameters: [String: AnalyticsValue]) {
        lock.withLock { recorded.append(Event(name: name, parameters: parameters)) }
    }
}

final class OnboardingInMemoryPreferences: PreferencesStoring, @unchecked Sendable {
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

    func string(for name: String) -> String {
        lock.withLock { storage[name] as? String ?? "" }
    }

    func bool(for name: String) -> Bool {
        lock.withLock { storage[name] as? Bool ?? false }
    }
}

final class OnboardingFakeLanguageWriter: OnboardingLanguageWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppLanguage?

    var lastSet: AppLanguage? {
        lock.withLock { stored }
    }

    @discardableResult
    func setAppLanguage(_ value: AppLanguage) -> Bool {
        lock.withLock {
            let changed = stored != value
            stored = value
            return changed
        }
    }
}

final class OnboardingFakeNotificationRequester: NotificationAuthorizationRequesting, @unchecked Sendable {
    private let result: NotificationAuthorizationResult
    private let lock = NSLock()
    private var requested = false

    var wasRequested: Bool {
        lock.withLock { requested }
    }

    init(result: NotificationAuthorizationResult) {
        self.result = result
    }

    func requestAuthorization() async -> NotificationAuthorizationResult {
        lock.withLock { requested = true }
        return result
    }
}

final class OnboardingFakeTrackingRequester: AppTrackingRequesting, @unchecked Sendable {
    let currentStatus: AppTrackingAuthorizationResult
    private let result: AppTrackingAuthorizationResult
    private let lock = NSLock()
    private var requested = false

    var wasRequested: Bool {
        lock.withLock { requested }
    }

    init(status: AppTrackingAuthorizationResult, result: AppTrackingAuthorizationResult) {
        currentStatus = status
        self.result = result
    }

    func requestAuthorization() async -> AppTrackingAuthorizationResult {
        lock.withLock { requested = true }
        return result
    }
}

final class OnboardingMutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        current = start
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    func now() -> Date {
        lock.withLock { current }
    }
}
