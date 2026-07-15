import AppFoundation
import AppFoundationTestSupport
import Testing
@testable import ProfileKit

@MainActor
@Suite("SS-131 AyarlarModel (durum, kalıcılık, niyet, analitik)")
struct AyarlarModelTests {
    private func makeModel(
        preferences: MockPreferences = MockPreferences(),
        analytics: MockAnalytics = MockAnalytics(),
        delegate: SettingsDelegateSpy = SettingsDelegateSpy(),
        notificationPermission: (any NotificationPermissionStatusProviding)? = nil
    ) -> (model: AyarlarModel, language: LanguagePreferenceService) {
        let language = LanguagePreferenceService(preferences: preferences)
        let model = AyarlarModel(
            preferences: preferences,
            language: language,
            analytics: analytics,
            delegate: delegate,
            notificationPermission: notificationPermission
        )
        return (model, language)
    }

    // MARK: - Varsayılanlar + screen_view

    @Test func onAppearTracksScreenView() {
        let analytics = MockAnalytics()
        let (model, _) = makeModel(analytics: analytics)
        model.onAppear()
        #expect(analytics.events.contains {
            $0.name == "screen_view" && $0.parameters["screen_name"] == .string("ayarlar")
        })
    }

    @Test func defaultsFromPreferences() {
        let (model, _) = makeModel()
        #expect(model.autoplayEnabled) // varsayılan AÇIK
        #expect(model.dataSaverEnabled == false) // varsayılan KAPALI
        #expect(model.notificationsPrimary)
        #expect(model.appLanguage == .english)
        #expect(model.subtitleLanguage == .english)
    }

    // MARK: - Oynatma

    @Test func toggleAutoplayPersistsAndTracks() {
        let prefs = MockPreferences()
        let analytics = MockAnalytics()
        let (model, _) = makeModel(preferences: prefs, analytics: analytics)
        model.setAutoplayEnabled(false)
        #expect(model.autoplayEnabled == false)
        #expect(prefs.value(for: PreferenceKeys.autoplayEnabled) == false)
        #expect(analytics.events.contains {
            $0.name == "settings_changed"
                && $0.parameters["key"] == .string(PreferenceKeys.autoplayEnabled.name)
                && $0.parameters["value"] == .bool(false)
        })
    }

    @Test func dataSaverMapsTo480() {
        let (model, _) = makeModel()
        model.setDataSaverEnabled(true)
        #expect(model.dataSaverEnabled)
        #expect(PlaybackConfigMapper.config(for: model.playbackPreferences).cellularMaxHeight == 480)
    }

    @Test func settingSameValueDoesNotEmit() {
        let analytics = MockAnalytics()
        let (model, _) = makeModel(analytics: analytics)
        model.setAutoplayEnabled(true) // zaten true
        #expect(analytics.events.contains { $0.name == "settings_changed" } == false)
    }

    // MARK: - Dil (SS-161 bağımsızlık)

    @Test func selectSubtitleUpdatesServiceAndPersists() {
        let prefs = MockPreferences()
        let analytics = MockAnalytics()
        let (model, service) = makeModel(preferences: prefs, analytics: analytics)
        model.selectSubtitleLanguage(.spanish)
        #expect(model.subtitleLanguage == .spanish)
        #expect(service.currentSubtitleLanguage == .spanish)
        #expect(prefs.value(for: PreferenceKeys.subtitleLanguageCode) == "es")
        #expect(analytics.events.contains {
            $0.name == "settings_changed" && $0.parameters["value"] == .string("es")
        })
    }

    @Test func selectAppLanguagePersistsIndependentlyOfSubtitle() {
        let prefs = MockPreferences()
        let (model, service) = makeModel(preferences: prefs)
        model.selectAppLanguage(.turkish)
        #expect(model.appLanguage == .turkish)
        #expect(service.appLanguage == .turkish)
        #expect(prefs.value(for: ProfilePreferenceKeys.appLanguageCode) == "tr")
        // Altyazı bağımsız — dokunulmadı.
        #expect(model.subtitleLanguage == .english)
        #expect(prefs.value(for: PreferenceKeys.subtitleLanguageCode) == "en")
    }

    // MARK: - Bildirim

    @Test func primaryNotificationOffEmitsPushDisabled() {
        let prefs = MockPreferences()
        let analytics = MockAnalytics()
        let (model, _) = makeModel(preferences: prefs, analytics: analytics)
        model.setNotificationsPrimary(false)
        #expect(model.notificationsPrimary == false)
        #expect(prefs.value(for: ProfilePreferenceKeys.notificationsPrimary) == false)
        #expect(analytics.events.contains {
            $0.name == "push_disabled" && $0.parameters["source"] == .string("ayarlar")
        })
        #expect(analytics.events.contains { $0.name == "settings_changed" })
    }

    @Test func notificationCategoryTogglePersists() {
        let prefs = MockPreferences()
        let (model, _) = makeModel(preferences: prefs)
        model.setNotificationCategory(.recommendations, enabled: false)
        #expect(model.isNotificationCategoryEnabled(.recommendations) == false)
        #expect(prefs.value(for: ProfilePreferenceKeys.notificationsRecommendations) == false)
    }

    // MARK: - Bildirim ana anahtar ↔ sistem izni (02 §4.14; review #11)

    @Test func primaryOnWithSystemPermissionDeniedRoutesToSystemSettings() {
        // Regresyon (review #11): sistem izni kapalıyken ana anahtar açılmak istenirse uygulama-içi
        // anahtar açılmamalı; kullanıcı sistem Ayarlar'a yönlendirilmeli (uygulama-içi anahtar etkisiz).
        let prefs = MockPreferences()
        prefs.set(false, for: ProfilePreferenceKeys.notificationsPrimary) // başlangıç KAPALI
        let spy = SettingsDelegateSpy()
        let (model, _) = makeModel(
            preferences: prefs,
            delegate: spy,
            notificationPermission: FakeNotificationPermission(granted: false)
        )
        model.setNotificationsPrimary(true)
        #expect(spy.systemNotificationSettings == 1) // sistem Ayarlar'a yönlendirdi
        #expect(model.notificationsPrimary == false) // uygulama-içi anahtar AÇILMADI
        #expect(prefs.value(for: ProfilePreferenceKeys.notificationsPrimary) == false)
    }

    @Test func primaryOnWithSystemPermissionGrantedEnables() {
        let prefs = MockPreferences()
        prefs.set(false, for: ProfilePreferenceKeys.notificationsPrimary)
        let spy = SettingsDelegateSpy()
        let (model, _) = makeModel(
            preferences: prefs,
            delegate: spy,
            notificationPermission: FakeNotificationPermission(granted: true)
        )
        model.setNotificationsPrimary(true)
        #expect(model.notificationsPrimary) // izin var → normal açılır
        #expect(prefs.value(for: ProfilePreferenceKeys.notificationsPrimary))
        #expect(spy.systemNotificationSettings == 0)
    }

    @Test func primaryOffNeverRoutesToSystemSettings() {
        // Kapatma sistem iznine bakmaz (izin kapalı olsa bile ana anahtarı kapatabilmeli).
        let prefs = MockPreferences()
        let spy = SettingsDelegateSpy()
        let (model, _) = makeModel(
            preferences: prefs,
            delegate: spy,
            notificationPermission: FakeNotificationPermission(granted: false)
        )
        model.setNotificationsPrimary(false)
        #expect(model.notificationsPrimary == false)
        #expect(spy.systemNotificationSettings == 0)
    }

    // MARK: - Hesap silme: Ayarlar YALNIZ yönlendirir (silmenin tek sahibi HesapSilme ekranı)

    @Test func accountDeletionRoutesToScreenWithoutOwningDeletion() {
        // Çift silme-yolu + funnel çift-sayım (App Store 5.1.1(v) riski) önlemi: Ayarlar kendi
        // account_delete_started event'ini ATMAZ, isDeletingAccount durumu TUTMAZ — yalnız silme
        // ekranına yönlendirir (settingsRequestsAccountDeletion). Started/completed sahibi HesapSilme.
        let spy = SettingsDelegateSpy()
        let analytics = MockAnalytics()
        let (model, _) = makeModel(analytics: analytics, delegate: spy)

        model.requestAccountDeletion()

        #expect(spy.accountDeletion == 1) // silme ekranına yönlendirdi
        #expect(analytics.events.contains { $0.name == "account_delete_started" } == false)
    }

    // MARK: - Yasal + hesap niyetleri

    @Test func legalPageInvokesDelegate() {
        let spy = SettingsDelegateSpy()
        let (model, _) = makeModel(delegate: spy)
        model.openLegalPage(.privacyPolicy)
        model.openLegalPage(.eula)
        #expect(spy.legalPages == [.privacyPolicy, .eula])
    }

    @Test func accountIntentsInvokeDelegate() {
        let spy = SettingsDelegateSpy()
        let (model, _) = makeModel(delegate: spy)
        model.openAccountManagement()
        model.requestSignOut()
        model.openSystemNotificationSettings()
        #expect(spy.accountManagement == 1)
        #expect(spy.signOut == 1)
        #expect(spy.systemNotificationSettings == 1)
    }

    // MARK: - Kalıcılık tek kaynak

    @Test func preferencesArePersistentSingleSource() {
        // Bir model yazar; aynı prefs ile YENİ model onları okur — ProfileKit tercih değerlerinin
        // tek kaynağı UserDefaults'tur (burada in-memory MockPreferences).
        let prefs = MockPreferences()
        let (writer, _) = makeModel(preferences: prefs)
        writer.setAutoplayEnabled(false)
        writer.setDataSaverEnabled(true)
        writer.setNotificationCategory(.coinRewards, enabled: false)
        writer.selectSubtitleLanguage(.turkish)

        let language = LanguagePreferenceService(preferences: prefs)
        let reader = AyarlarModel(
            preferences: prefs,
            language: language,
            analytics: MockAnalytics(),
            delegate: SettingsDelegateSpy()
        )
        #expect(reader.autoplayEnabled == false)
        #expect(reader.dataSaverEnabled)
        #expect(reader.isNotificationCategoryEnabled(.coinRewards) == false)
        #expect(reader.subtitleLanguage == .turkish)
    }
}
