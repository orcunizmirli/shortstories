import Foundation

/// Altyazı tercihi OKUMA portu — PlayerKit-yerel tüketici sınırı (R2: ProfileKit import EDİLMEZ; App
/// kompozisyonu `LanguagePreferenceService`'i bir adaptörle köprüler — `PlaybackPreferencesProviding`/
/// veri-tasarrufu deseni birebir). Değer BCP-47 birincil alt-etiket; `nil` = altyazı kapalı.
/// `AVPlayerBackend` bunu tüketir: yüklemede + tercih değişiminde `AVMediaSelectionGroup`'ta eşleşen
/// legible track'i seçer (SS-046).
public protocol SubtitlePreferenceProviding: Sendable {
    /// Anlık altyazı dili kodu (senkron); `nil` = kapalı. Uygulamanın OTORİTE kaynağı (stream yalnız tetik).
    var currentSubtitleCode: String? { get }
    /// Altyazı dili değişimleri; replay'li (abone mevcut değerle başlar). `nil` = kapalı.
    func subtitleCodeUpdates() -> AsyncStream<String?>
}
