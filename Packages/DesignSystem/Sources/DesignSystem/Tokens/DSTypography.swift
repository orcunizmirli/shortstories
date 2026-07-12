import SwiftUI

/// Semantic tipografi katmanı. Tüm stiller text-style tabanlıdır ve Dynamic
/// Type'a tepki verir; tek istisna `playerOverlay(size:weight:)`.
public enum DSTypography {
    /// Splash / kampanya başlıkları.
    public static let display = Font.system(.largeTitle, design: .default, weight: .bold)

    /// Ekran başlıkları.
    public static let headingL = Font.system(.title2, design: .default, weight: .semibold)

    /// Raf / kart başlıkları.
    public static let headingM = Font.system(.headline, design: .default)

    public static let body = Font.system(.body, design: .default)

    public static let bodyEmphasized = Font.system(.body, design: .default, weight: .semibold)

    public static let caption = Font.system(.caption, design: .default)

    public static let captionEmphasized = Font.system(.caption, design: .default, weight: .semibold)

    /// SS-011 istisnası: player overlay Dynamic Type'a ÖLÇEKLENMEZ — video
    /// üstü overlay yerleşimi sabit boyut ister.
    public static func playerOverlay(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        Font.system(size: size, weight: weight)
    }
}
