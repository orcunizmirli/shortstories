/// Oynatma tercihleri (02 §4.14 Oynatma grubu, SS-131) — SAF değer tipi. Otomatik oynatma
/// varsayılan AÇIK; veri tasarrufu varsayılan KAPALI. Kalıcılık `PreferencesStoring`'dedir
/// (`PreferenceKeys.autoplayEnabled`/`dataSaverEnabled`).
public struct PlaybackPreferences: Sendable, Equatable {
    public let autoplayEnabled: Bool
    public let dataSaverEnabled: Bool

    public init(autoplayEnabled: Bool, dataSaverEnabled: Bool) {
        self.autoplayEnabled = autoplayEnabled
        self.dataSaverEnabled = dataSaverEnabled
    }

    /// Kanonik varsayılanlar (02 §4.14).
    public static let `default` = PlaybackPreferences(autoplayEnabled: true, dataSaverEnabled: false)
}

/// Oynatma tercihlerinin PlayerKit'in anlayacağı çalışma-zamanı yapılandırmasına eşlenmiş hali
/// (SS-048). Ham AVFoundation tipi SIZMAZ (kanon §2): PlayerKit bu değerleri
/// `preferredPeakBitRateForExpensiveNetwork`/prefetch stratejisine kendisi çevirir.
public struct PlaybackConfig: Sendable, Equatable {
    /// Bölüm sonu otomatik geçiş (02 §4.3: kapalıysa tekrar-izle + sonraki-bölüm butonları).
    public let autoAdvanceEnabled: Bool
    /// Hücresel ağda çözünürlük tavanı; `nil` = sınırsız (SS-048: veri tasarrufunda 480p).
    public let cellularMaxHeight: Int?
    /// Hücreselde sonraki bölüm prefetch'ine izin var mı (veri tasarrufunda durdurulur).
    public let prefetchAllowedOnCellular: Bool

    public init(autoAdvanceEnabled: Bool, cellularMaxHeight: Int?, prefetchAllowedOnCellular: Bool) {
        self.autoAdvanceEnabled = autoAdvanceEnabled
        self.cellularMaxHeight = cellularMaxHeight
        self.prefetchAllowedOnCellular = prefetchAllowedOnCellular
    }
}

/// Oynatma tercihi → player-config eşlemesi (SS-048) — SAF, yan etkisiz, izole test edilir.
public enum PlaybackConfigMapper {
    /// Veri tasarrufu çözünürlük tavanı (kanon §2 / 02 §4.14: hücreselde 480p + prefetch durdur).
    public static let dataSaverMaxHeight = 480

    public static func config(for preferences: PlaybackPreferences) -> PlaybackConfig {
        PlaybackConfig(
            autoAdvanceEnabled: preferences.autoplayEnabled,
            cellularMaxHeight: preferences.dataSaverEnabled ? dataSaverMaxHeight : nil,
            prefetchAllowedOnCellular: !preferences.dataSaverEnabled
        )
    }
}
