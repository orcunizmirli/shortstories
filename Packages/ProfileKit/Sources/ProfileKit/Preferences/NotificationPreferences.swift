import AppFoundation

/// Bildirim tipi (02 §4.14: yeni bölüm, devam hatırlatması, coin/ödül, öneriler; push stratejisi
/// 07-retention-gamification.md). Her tip ayrı bir `PreferencesStoring` anahtarına yazılır.
public enum NotificationCategory: String, CaseIterable, Sendable, Equatable, Hashable {
    case newEpisode
    case continueReminder
    case coinRewards
    case recommendations

    /// `settings_changed` analitiği + kalıcılık için anahtar.
    var preferenceKey: PreferenceKey<Bool> {
        switch self {
        case .newEpisode: ProfilePreferenceKeys.notificationsNewEpisode
        case .continueReminder: ProfilePreferenceKeys.notificationsContinueReminder
        case .coinRewards: ProfilePreferenceKeys.notificationsCoinRewards
        case .recommendations: ProfilePreferenceKeys.notificationsRecommendations
        }
    }
}

/// Bildirim tercihlerinin SAF anlık görüntüsü — App'in push katmanı (SS-143) bunu `PreferencesStoring`
/// üzerinden okur (sessiz saat/frekans yerine tip-bazlı gate). Ana anahtar kapalıysa tüm tipler
/// etkisizdir (`isEnabled` bunu uygular).
public struct NotificationPreferences: Sendable, Equatable {
    /// Ana bildirim anahtarı (02 §4.14: kapalıysa tüm tipler etkisiz).
    public let primaryEnabled: Bool
    /// Ham (primary'den bağımsız) tip durumu — DIŞARI SIZDIRILMAZ (private): doğrudan iterasyon
    /// primary master-switch kapısını atlayamasın diye erişim `isEnabled(_:)`/`enabledCategories`
    /// üzerinden primary-gated zorlanır (review #10).
    private let rawEnabledCategories: Set<NotificationCategory>

    public init(primaryEnabled: Bool, enabledCategories: Set<NotificationCategory>) {
        self.primaryEnabled = primaryEnabled
        rawEnabledCategories = enabledCategories
    }

    /// Etkin tipler — primary KAPALIYSA daima BOŞ (master-switch her zaman uygulanır). App'in push
    /// katmanı bu kümeyi doğrudan iterese bile primary gate'i atlayamaz.
    public var enabledCategories: Set<NotificationCategory> {
        primaryEnabled ? rawEnabledCategories : []
    }

    /// Ana anahtar AND tip anahtarı.
    public func isEnabled(_ category: NotificationCategory) -> Bool {
        primaryEnabled && rawEnabledCategories.contains(category)
    }

    /// Kalıcı depodan okur (App push gate'i için tek çağrı).
    public static func read(from preferences: any PreferencesStoring) -> NotificationPreferences {
        let primary = preferences.value(for: ProfilePreferenceKeys.notificationsPrimary)
        var enabled: Set<NotificationCategory> = []
        for category in NotificationCategory.allCases where preferences.value(for: category.preferenceKey) {
            enabled.insert(category)
        }
        return NotificationPreferences(primaryEnabled: primary, enabledCategories: enabled)
    }
}
