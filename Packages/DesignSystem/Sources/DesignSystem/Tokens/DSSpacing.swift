import Foundation

/// 4pt ızgara boşluk ölçeği.
public enum DSSpacing {
    public static let xxs: CGFloat = 2
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

/// Köşe yarıçapı token'ları.
public enum DSRadius {
    /// Chip her zaman kapsüldür; bileşenler `Capsule()` kullanır, değer
    /// sözleşmeyi belgelemek içindir.
    public static let chip: CGFloat = .infinity
    public static let card: CGFloat = 12
    public static let sheet: CGFloat = 16
    public static let button: CGFloat = 10
}

/// Çizgi kalınlığı token'ları.
public enum DSStroke {
    /// 2x/3x ekranlarda tek fiziksel piksele yakın ince çizgi.
    public static let hairline: CGFloat = 0.5
}
