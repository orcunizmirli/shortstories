import SwiftUI

/// İnce, determinate izleme ilerleme çubuğu (0...1). Kart altı ilerlemesi
/// (Devam Et rafı, Listem kartları) ve player alt çubuğunun görsel temelidir;
/// player'ın scrub etkileşimi PlayerKit'te bu bileşenin üstüne kurulur.
public struct DSProgressBar: View {
    private let progress: Double
    private let height: CGFloat

    /// - Parameters:
    ///   - progress: 0...1 aralığına kırpılır.
    ///   - height: Çubuk kalınlığı; varsayılan 2 pt (02 §4.3.2 alt ilerleme çubuğu).
    public init(progress: Double, height: CGFloat = 2) {
        self.progress = progress
        self.height = height
    }

    /// 0...1 aralığına kırpılmış değer; sonlu olmayan girdi (NaN/∞) 0 sayılır
    /// (test kancası). NaN, min/max'tan sızıp accessibilityValue'daki Int
    /// dönüşümünü çökertmesin diye isFinite guard'ı zorunludur.
    var clampedProgress: Double {
        guard progress.isFinite else { return 0 }
        return min(max(progress, 0), 1)
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DSColors.borderSubtle)
                Capsule()
                    .fill(DSColors.accent)
                    .frame(width: geometry.size.width * clampedProgress)
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("İzleme ilerlemesi")
        .accessibilityValue("%\(Int((clampedProgress * 100).rounded()))")
    }
}
