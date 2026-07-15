import SwiftUI

/// Standart buton. Bileşen-içi renk türetimleri (zemin üstü metin renkleri)
/// 03 §4.1 katman 3 gereği yalnız bu dosyada yaşar.
public struct DSButton: View {
    public enum Style: Sendable {
        case primary
        case secondary
        /// coinGold zemin — kanon paywall/coin CTA'sı.
        case coinCTA
        /// Yıkıcı eylem (hesap silme vb.) — `danger` zemin üstünde beyaz metin (SS-133).
        case destructive
    }

    public enum Size: Sendable {
        case regular
        case compact
    }

    private let title: LocalizedStringKey
    private let style: Style
    private let size: Size
    private let isLoading: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        style: Style = .primary,
        size: Size = .regular,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(size == .regular ? DSTypography.bodyEmphasized : DSTypography.captionEmphasized)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(foreground)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, size == .regular ? DSSpacing.xl : DSSpacing.l)
            .padding(.vertical, size == .regular ? DSSpacing.m : DSSpacing.s)
            .frame(maxWidth: size == .regular ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: DSRadius.button))
            .overlay {
                if style == .secondary {
                    RoundedRectangle(cornerRadius: DSRadius.button)
                        .strokeBorder(DSColors.borderSubtle, lineWidth: DSStroke.hairline)
                }
            }
        }
        .disabled(isLoading)
    }

    /// Bileşen-içi zemin türetimi (03 §4.1 katman 3) — `internal` yalnız izole test için.
    var background: Color {
        switch style {
        case .primary: DSColors.accent
        case .secondary: DSColors.surfaceElevated
        case .coinCTA: DSColors.coinGold
        case .destructive: DSColors.danger
        }
    }

    /// Bileşen-içi ön plan (zemin üstü metin) türetimi — ham renk YALNIZ burada yaşar.
    var foreground: Color {
        switch style {
        case .primary: .white
        case .secondary: DSColors.textPrimary
        case .coinCTA: .black // gold zemin üstünde kontrast için koyu
        case .destructive: .white // danger (kırmızı) zemin üstünde beyaz
        }
    }
}

/// SwiftUI-idiomatik kullanım: `Button("...") {}.buttonStyle(.dsPrimary)`.
public struct DSPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSTypography.bodyEmphasized)
            .foregroundStyle(.white)
            .padding(.horizontal, DSSpacing.xl)
            .padding(.vertical, DSSpacing.m)
            .frame(maxWidth: .infinity)
            .background(DSColors.accent, in: RoundedRectangle(cornerRadius: DSRadius.button))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

public extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle {
        DSPrimaryButtonStyle()
    }
}
