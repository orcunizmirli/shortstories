import AppFoundation
import PlayerKit

// PlayerKit oynatma-tercihi portları (04 §2.4 / §5.3 / SS-046). Ayrı dosya: AppComposition ana dosyası
// 400-satır bütçesinde; player-tercihi köprüleri burada gruplanır.

extension AppComposition {
    /// Veri tasarrufu portu (04 §5.3) → `PreferencesStoring`. Player prefetch/bitrate kararını türetir.
    var playerDataSaverProvider: any PlayerKit.PlaybackPreferencesProviding {
        PreferencesDataSaverProvider(preferences: dependencies.preferences)
    }

    /// Altyazı-tercihi portu (SS-046) → ProfileKit `SubtitleLanguageProviding` (kompozisyon kökü
    /// singleton'ı). Backend legible track'i bu tercihe göre seçer + canlı değişimi izler.
    var playerSubtitleProvider: any PlayerKit.SubtitlePreferenceProviding {
        SubtitlePreferenceAdapter(source: languagePreferences)
    }
}
