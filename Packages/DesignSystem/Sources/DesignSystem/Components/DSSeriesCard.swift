import SwiftUI

/// Raf/ızgara dizi kartı (SS-013): 2:3 poster, başlık, opsiyonel rozet ve
/// izleme ilerleme çubuğu ("Devam Et" rafı). Poster görselini yüklemek
/// feature katmanının işidir — bileşen hazır `Image` alır, yoksa
/// yüzey rengi placeholder çizer (AsyncImage bilinçli olarak yok).
public struct DSSeriesCard: View {
    public enum Size: Sendable {
        /// Yatay raf kartı — sabit genişlik.
        case shelf
        /// Dikey ızgara hücresi — genişliği kolonundan alır.
        case grid
    }

    /// Kanonik poster oranı (02 §4.10: poster 2:3).
    static let posterAspectRatio: CGFloat = 2.0 / 3.0

    /// Yatay raf kartının sabit genişliği.
    static let shelfWidth: CGFloat = 110

    private let title: String
    private let subtitle: String?
    private let size: Size
    private let poster: Image?
    private let badge: DSBadge.Kind?
    private let progress: Double?
    private let onTap: () -> Void

    /// - Parameter subtitle: Opsiyonel tür alt yazısı (02 §4.10: Trend rafı
    ///   "başlık + tür alt yazı" ister).
    public init(
        title: String,
        subtitle: String? = nil,
        size: Size = .shelf,
        poster: Image? = nil,
        badge: DSBadge.Kind? = nil,
        progress: Double? = nil,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.size = size
        self.poster = poster
        self.badge = badge
        self.progress = progress
        self.onTap = onTap
    }

    /// 0...1 aralığına kırpılmış ilerleme; sonlu olmayan girdi (NaN/∞) 0
    /// sayılır (test kancası) — NaN, accessibilityText'teki Int dönüşümünü
    /// çökertmesin.
    var clampedProgress: Double? {
        progress.map { $0.isFinite ? min(max($0, 0), 1) : 0 }
    }

    /// VoiceOver etiketi: başlık + alt yazı + rozet + ilerleme (test kancası).
    var accessibilityText: String {
        var parts = [title]
        if let subtitle {
            parts.append(subtitle)
        }
        if let badge {
            parts.append(DSBadge(badge).accessibilityText)
        }
        if let clampedProgress {
            parts.append("%\(Int((clampedProgress * 100).rounded())) izlendi")
        }
        return parts.joined(separator: ", ")
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                posterView
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(title)
                        .font(DSTypography.captionEmphasized)
                        .foregroundStyle(DSColors.textPrimary)
                        .lineLimit(size == .shelf ? 1 : 2)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: size == .shelf ? Self.shelfWidth : nil)
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.card))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
    }

    /// Poster alanının boyutunu içerikten bağımsız `Color.clear` taban belirler;
    /// görsel overlay'de `.scaledToFill` ile çizilir. Aksi halde geniş (16:9)
    /// bir poster ZStack'in ideal boyutunu şişirip kartı 2:3'ten çıkarıyor ve
    /// Button hit-area'sını görünür kartın dışına taşırıyordu (clipShape çizimi
    /// kırpar, hit-testing'i değil — o yüzden karta ayrıca contentShape verilir).
    private var posterView: some View {
        Color.clear
            .aspectRatio(Self.posterAspectRatio, contentMode: .fit)
            .overlay {
                ZStack {
                    Rectangle()
                        .fill(DSColors.surfaceElevated)
                    if let poster {
                        poster
                            .resizable()
                            .scaledToFill()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DSRadius.card))
            .overlay(alignment: .topLeading) {
                if let badge {
                    DSBadge(badge)
                        .padding(DSSpacing.xs)
                }
            }
            .overlay(alignment: .bottom) {
                if let clampedProgress {
                    DSProgressBar(progress: clampedProgress)
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.bottom, DSSpacing.xs)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .strokeBorder(DSColors.borderSubtle, lineWidth: DSStroke.hairline)
            }
    }
}
