import SwiftUI
import UIKit

/// Primitive palet katmanı (03 §4.1 katman 1) — YALNIZ semantic katman
/// (`DSColors`) tarafından referans alınır; bu yüzden dosya-private'tır.
private enum Palette {
    static let black = UIColor(rgb: 0x000000)
    static let white = UIColor(rgb: 0xFFFFFF)
    static let gray900 = UIColor(rgb: 0x121212)
    static let gray800 = UIColor(rgb: 0x1E1E1E)
    static let gray100 = UIColor(rgb: 0xF2F2F7)
    static let ink = UIColor(rgb: 0x111111)
    static let pink = UIColor(rgb: 0xFF375F)
    static let gold = UIColor(rgb: 0xFFC542)
    static let green = UIColor(rgb: 0x30D158)
    static let yellow = UIColor(rgb: 0xFFD60A)
    static let red = UIColor(rgb: 0xFF453A)
}

/// Semantic renk katmanı — dark-first (kanon §2: dark-locked, OLED siyahı).
/// Feature paketleri YALNIZ bu katmanı kullanır; ham renk tanımı bu paketin
/// dışında lint ile yasaktır. Light değerleri F0'da makul başlangıçlardır
/// (uygulama sistem temasını takip etmez; dark birincil kaynaktır).
public enum DSColors {
    // MARK: - Zemin

    /// OLED siyahı ana zemin (#000000).
    public static let background = dynamic(dark: Palette.black, light: Palette.white)

    /// Standart yüzey (#121212).
    public static let surface = dynamic(dark: Palette.gray900, light: Palette.gray100)

    /// Yükseltilmiş yüzey — kart, sheet (#1E1E1E).
    public static let surfaceElevated = dynamic(dark: Palette.gray800, light: Palette.white)

    /// Tab bar zemini — PlayerFeed üstünde %85 opak koyu (02 §5: `surface.tabBar`).
    public static let surfaceTabBar = dynamic(
        dark: Palette.black.withAlphaComponent(0.85),
        light: Palette.white.withAlphaComponent(0.85)
    )

    // MARK: - Metin

    public static let textPrimary = dynamic(dark: Palette.white, light: Palette.ink)

    /// %70 beyaz (dark).
    public static let textSecondary = dynamic(
        dark: Palette.white.withAlphaComponent(0.70),
        light: Palette.ink.withAlphaComponent(0.70)
    )

    /// %45 beyaz (dark).
    public static let textTertiary = dynamic(
        dark: Palette.white.withAlphaComponent(0.45),
        light: Palette.ink.withAlphaComponent(0.45)
    )

    // MARK: - Vurgu / marka

    /// Seçili sekme + primary CTA. F0 placeholder marka değeri.
    public static let accent = dynamic(dark: Palette.pink, light: Palette.pink)

    /// Coin/paywall vurgusu (SS-010 "coin-gold").
    public static let coinGold = dynamic(dark: Palette.gold, light: Palette.gold)

    // MARK: - Durum

    public static let success = dynamic(dark: Palette.green, light: Palette.green)
    public static let warning = dynamic(dark: Palette.yellow, light: Palette.yellow)
    public static let danger = dynamic(dark: Palette.red, light: Palette.red)

    // MARK: - Katman (theme-invariant sınıf — 03 §4.1)

    /// Player üstü scrim/gradyan tabanı. Theme-invariant: video üstü
    /// okunabilirlik tema tercihinden bağımsızdır — trait dinamiği YOKTUR,
    /// ileride tema ekseni eklense bile her temada koyu kalır.
    public static let overlayScrim = Color(Palette.black.withAlphaComponent(0.60))

    /// Poster/scrim üstü ön plan (kilit ikonu, Top-10 numarası vb.).
    /// Theme-invariant: overlay sınıfındaki içerik koyu görsel/scrim üstünde
    /// okunur kalmak için her temada beyazdır — trait dinamiği YOKTUR.
    public static let overlayForeground = Color(Palette.white)

    // MARK: - Kenar

    public static let borderSubtle = dynamic(
        dark: Palette.white.withAlphaComponent(0.12),
        light: Palette.ink.withAlphaComponent(0.12)
    )

    // MARK: - Yardımcı

    private static func dynamic(dark: UIColor, light: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .light ? light : dark
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
