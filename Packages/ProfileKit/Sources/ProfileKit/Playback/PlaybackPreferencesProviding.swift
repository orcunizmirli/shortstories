import AppFoundation

/// Oynatma tercihi OKUMA portu (SS-131 → SS-048). PlayerKit veri-tasarrufu/otomatik-oynatma
/// kararını `PlaybackConfigMapper` ile bu porttan türetir; ProfileKit'i import etmeden (R2) App
/// DI kompozisyonunda bağlanır. Pull-based (ağ sinyali değişiminde player okur); anlık publish
/// altyazıda gereklidir (`SubtitleLanguageProviding`), oynatmada değil.
public protocol PlaybackPreferencesProviding: Sendable {
    var currentPlaybackPreferences: PlaybackPreferences { get }
}

/// `PreferencesStoring` üzerine ince canlı adaptör (App kompozisyonu bunu bağlar; testler
/// in-memory `MockPreferences` ile besler). Değerler tek kaynak UserDefaults'tan okunur.
public struct PreferencePlaybackProvider: PlaybackPreferencesProviding {
    private let preferences: any PreferencesStoring

    public init(preferences: any PreferencesStoring) {
        self.preferences = preferences
    }

    public var currentPlaybackPreferences: PlaybackPreferences {
        PlaybackPreferences(
            autoplayEnabled: preferences.value(for: PreferenceKeys.autoplayEnabled),
            dataSaverEnabled: preferences.value(for: PreferenceKeys.dataSaverEnabled)
        )
    }
}
