import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import ProfileKit

@Suite("SS-131 bildirim tercihleri okuma (saf)")
struct NotificationPreferencesTests {
    @Test func primaryOffGatesAllCategories() {
        let prefs = MockPreferences()
        prefs.set(false, for: ProfilePreferenceKeys.notificationsPrimary)
        let value = NotificationPreferences.read(from: prefs)
        #expect(value.primaryEnabled == false)
        #expect(value.isEnabled(.newEpisode) == false)
        #expect(value.isEnabled(.coinRewards) == false)
    }

    @Test func categoryToggleReflectedWhenPrimaryOn() {
        let prefs = MockPreferences()
        prefs.set(false, for: ProfilePreferenceKeys.notificationsRecommendations)
        let value = NotificationPreferences.read(from: prefs)
        #expect(value.primaryEnabled) // varsayılan true
        #expect(value.isEnabled(.newEpisode))
        #expect(value.isEnabled(.recommendations) == false)
    }

    // MARK: - enabledCategories primary master-switch'e tabidir (review #10)

    @Test func enabledCategoriesRespectPrimaryGate() {
        // Regresyon (review #10): ham kategori kümesi primary'den bağımsızdı; doğrudan iterasyon
        // ana master-switch kapısını atlayıp push katmanını yanlış tetikleyebiliyordu.
        let value = NotificationPreferences(
            primaryEnabled: false,
            enabledCategories: [.newEpisode, .coinRewards]
        )
        #expect(value.enabledCategories.isEmpty) // primary kapalı → doğrudan iterasyon hiçbirini görmez
        #expect(value.isEnabled(.newEpisode) == false)
    }

    @Test func enabledCategoriesReflectRawWhenPrimaryOn() {
        let value = NotificationPreferences(primaryEnabled: true, enabledCategories: [.newEpisode])
        #expect(value.enabledCategories == [.newEpisode])
        #expect(value.isEnabled(.newEpisode))
    }
}
