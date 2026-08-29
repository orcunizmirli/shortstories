import Foundation

/// Oynatma hızı menüsü (04 §8.2) SAF yardımcısı: kanonik hız seçenekleri + etiket biçimi + güncel-hız
/// eşleme. Uygulama (`setPreferredRate`) `FeedPlaybackDirector`'da; kalıcılaştırma Ayarlar (SS-131).
/// Uzun-basma 2x bu tercihin ÜZERİNE geçicidir (`FeedHoldSpeedPolicy`); menü kalıcı tercihi belirler.
public enum PlaybackSpeedMenu {
    /// Kanonik hız seçenekleri (artan). 1.0 = normal.
    public static let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    /// Güncel hıza karşılık gelen seçenek (menüde işaretli gösterilecek); listede yoksa normal (1.0).
    public static func selected(for currentRate: Double) -> Double {
        rates.contains(currentRate) ? currentRate : 1.0
    }

    /// Kullanıcıya gösterilecek etiket: tam sayı "1x", kesirli "0.5x"/"1.25x" (gereksiz sıfır yok).
    public static func label(for rate: Double) -> String {
        if rate == rate.rounded() {
            return "\(Int(rate))x"
        }
        var text = String(format: "%.2f", rate)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        return "\(text)x"
    }
}
