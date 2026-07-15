import AppFoundation
import Observation

/// `Ayarlar` ekran modeli (SS-131). @Observable/@MainActor; SwiftUI View ince kalır. Bölümler:
/// Dil (uygulama + altyazı AYRI — SS-161), bildirim tercihleri, oynatma tercihleri (otomatik
/// oynatma, veri tasarrufu), hesap yönetimi + yasal (delegate). Tercih değişimi ANINDA uygulanır
/// ve kalıcıdır: dil `LanguagePreferenceService` (yayınlar), diğerleri `PreferencesStoring` — her
/// ikisinin de kalıcılık tek kaynağı UserDefaults'tur. Her değişimde `settings_changed` (02 §4.14).
@MainActor
@Observable
public final class AyarlarModel {
    // MARK: - Durum (Observable) — dil

    public private(set) var appLanguage: AppLanguage
    public private(set) var subtitleLanguage: SubtitleLanguage
    public let availableAppLanguages: [AppLanguage]
    public let availableSubtitleLanguages: [SubtitleLanguage]

    // MARK: - Durum — oynatma

    public private(set) var autoplayEnabled: Bool
    public private(set) var dataSaverEnabled: Bool

    // MARK: - Durum — bildirim

    public private(set) var notificationsPrimary: Bool
    private var notificationCategories: [NotificationCategory: Bool]

    // MARK: - Bağımlılıklar

    private let preferences: any PreferencesStoring
    private let language: LanguagePreferenceService
    private let analytics: any AnalyticsTracking
    private let notificationPermission: (any NotificationPermissionStatusProviding)?
    private weak var delegate: (any SettingsDelegate)?

    public init(
        preferences: any PreferencesStoring,
        language: LanguagePreferenceService,
        analytics: any AnalyticsTracking,
        delegate: (any SettingsDelegate)?,
        notificationPermission: (any NotificationPermissionStatusProviding)? = nil
    ) {
        self.preferences = preferences
        self.language = language
        self.analytics = analytics
        self.notificationPermission = notificationPermission
        self.delegate = delegate

        appLanguage = language.appLanguage
        subtitleLanguage = language.currentSubtitleLanguage
        availableAppLanguages = LanguageCatalog.supportedAppLanguages
        availableSubtitleLanguages = LanguageCatalog.offeredSubtitleLanguages

        autoplayEnabled = preferences.value(for: PreferenceKeys.autoplayEnabled)
        dataSaverEnabled = preferences.value(for: PreferenceKeys.dataSaverEnabled)

        notificationsPrimary = preferences.value(for: ProfilePreferenceKeys.notificationsPrimary)
        var categories: [NotificationCategory: Bool] = [:]
        for category in NotificationCategory.allCases {
            categories[category] = preferences.value(for: category.preferenceKey)
        }
        notificationCategories = categories
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        trackScreenView()
        // Dil aynasını tek kaynaktan tazele (player altyazı sheet'inden değişmiş olabilir, 02 §4.3).
        appLanguage = language.appLanguage
        subtitleLanguage = language.currentSubtitleLanguage
    }

    // MARK: - Dil (SS-161)

    public func selectAppLanguage(_ value: AppLanguage) {
        guard language.setAppLanguage(value) else { return }
        appLanguage = value
        trackSettingChange(key: ProfilePreferenceKeys.appLanguageCode.name, value: .string(value.code))
    }

    public func selectSubtitleLanguage(_ value: SubtitleLanguage) {
        guard language.setSubtitleLanguage(value) else { return }
        subtitleLanguage = value
        trackSettingChange(key: PreferenceKeys.subtitleLanguageCode.name, value: .string(value.persistedValue))
    }

    // MARK: - Oynatma (SS-131/048)

    public func setAutoplayEnabled(_ isOn: Bool) {
        guard isOn != autoplayEnabled else { return }
        autoplayEnabled = isOn
        preferences.set(isOn, for: PreferenceKeys.autoplayEnabled)
        trackSettingChange(key: PreferenceKeys.autoplayEnabled.name, value: .bool(isOn))
    }

    public func setDataSaverEnabled(_ isOn: Bool) {
        guard isOn != dataSaverEnabled else { return }
        dataSaverEnabled = isOn
        preferences.set(isOn, for: PreferenceKeys.dataSaverEnabled)
        trackSettingChange(key: PreferenceKeys.dataSaverEnabled.name, value: .bool(isOn))
    }

    /// Güncel oynatma tercihleri (App bunu `PlaybackConfigMapper` ile PlayerKit'e taşır).
    public var playbackPreferences: PlaybackPreferences {
        PlaybackPreferences(autoplayEnabled: autoplayEnabled, dataSaverEnabled: dataSaverEnabled)
    }

    // MARK: - Bildirim (02 §4.14)

    public func isNotificationCategoryEnabled(_ category: NotificationCategory) -> Bool {
        notificationCategories[category] ?? true
    }

    public func setNotificationsPrimary(_ isOn: Bool) {
        // 02 §4.14: ana anahtar AÇILMAK istenip sistem bildirim izni KAPALIYSA, uygulama-içi anahtar
        // sistem izni olmadan etkisizdir → açmak yerine sistem Ayarlar'a yönlendir (review #11).
        // İzin portu bağlı değilse (nil) kontrol atlanır (izin verildi varsayılır — App bağlar).
        if isOn, let notificationPermission, !notificationPermission.isSystemNotificationPermissionGranted {
            openSystemNotificationSettings()
            return
        }
        guard isOn != notificationsPrimary else { return }
        notificationsPrimary = isOn
        preferences.set(isOn, for: ProfilePreferenceKeys.notificationsPrimary)
        trackSettingChange(key: ProfilePreferenceKeys.notificationsPrimary.name, value: .bool(isOn))
        if !isOn {
            // 08 §3.6: ana anahtar kapatıldığında ayrıca push_disabled.
            analytics.track("push_disabled", parameters: ["source": .string("ayarlar")])
        }
    }

    public func setNotificationCategory(_ category: NotificationCategory, enabled: Bool) {
        guard isNotificationCategoryEnabled(category) != enabled else { return }
        notificationCategories[category] = enabled
        preferences.set(enabled, for: category.preferenceKey)
        trackSettingChange(key: category.preferenceKey.name, value: .bool(enabled))
    }

    /// Sistem bildirim izni kapalıyken ana anahtar açılmak istenirse (View karar verir).
    public func openSystemNotificationSettings() {
        delegate?.settingsOpensSystemNotificationSettings()
    }

    // MARK: - Hesap (02 §4.13/4.14; SS-132/133 App'te)

    public func openAccountManagement() {
        delegate?.settingsOpensAccountManagement()
    }

    public func requestSignOut() {
        delegate?.settingsRequestsSignOut()
    }

    /// "Hesabı sil" → yıkıcı silme ekranını AÇAR (SS-133). Çift-onay kapısı, geri-alma uyarısı ve
    /// `account_delete_started/completed` event'lerinin TEK sahibi `HesapSilmeModel`'dir; Ayarlar
    /// yalnız yönlendirir — kendi çift-onay/silme mantığı, started event'i ve durum bayrağı YOK
    /// (aksi halde funnel çift-sayım + paralel silme yolu App Store 5.1.1(v) zorunlu ekranlarını atlar).
    public func requestAccountDeletion() {
        delegate?.settingsRequestsAccountDeletion()
    }

    // MARK: - Yasal (SS-175)

    public func openLegalPage(_ page: LegalPage) {
        delegate?.settingsOpensLegalPage(page)
    }

    // MARK: - İç (analitik, 02 §4.14)

    private func trackScreenView() {
        analytics.track("screen_view", parameters: ["screen_name": .string("ayarlar")])
    }

    /// Tek generic event (02 §4.14: `settings_changed {key, value}`).
    private func trackSettingChange(key: String, value: AnalyticsValue) {
        analytics.track("settings_changed", parameters: ["key": .string(key), "value": value])
    }
}
