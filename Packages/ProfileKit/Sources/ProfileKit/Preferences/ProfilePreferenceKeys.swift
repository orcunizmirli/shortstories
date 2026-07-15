import AppFoundation

/// ProfileKit-sahipli tercih anahtarları (03 §9 UserDefaults). ProfileKit, uygulama tercih
/// değerlerinin TEK KAYNAĞIDIR; App bu anahtarları `PreferencesStoring` (UserDefaults) üzerinden
/// okur. Oynatma (`autoplayEnabled`/`dataSaverEnabled`) ve altyazı (`subtitleLanguageCode`)
/// kanonik anahtarları `AppFoundation.PreferenceKeys`'te yaşar ve YENİDEN KULLANILIR (anahtar
/// kayması olmasın); burada ProfileKit'e özgü olanlar tanımlanır.
public enum ProfilePreferenceKeys {
    /// Uygulama arayüz dili (SS-161). Altyazı kodu AF `PreferenceKeys.subtitleLanguageCode`'dadır.
    public static let appLanguageCode = PreferenceKey(name: "language.app_code", default: "en")

    // MARK: - Bildirim tercihleri (02 §4.14 Bildirimler grubu)

    /// Ana bildirim anahtarı (sistem iznine bağlıdır; bağlama App/SS-140'ta).
    public static let notificationsPrimary = PreferenceKey(name: "notifications.primary_enabled", default: true)
    public static let notificationsNewEpisode = PreferenceKey(name: "notifications.new_episode", default: true)
    public static let notificationsContinueReminder = PreferenceKey(
        name: "notifications.continue_reminder", default: true
    )
    public static let notificationsCoinRewards = PreferenceKey(name: "notifications.coin_rewards", default: true)
    public static let notificationsRecommendations = PreferenceKey(name: "notifications.recommendations", default: true)
}
