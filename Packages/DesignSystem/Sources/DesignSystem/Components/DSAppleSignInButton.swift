import SwiftUI

/// Sign in with Apple butonu (Apple HIG: koyu zemin üstünde okunur BEYAZ stil). Apple-imzalı
/// buton görünümü (beyaz zemin + siyah `apple.logo` + metin) tek bir DS bileşeninde kapsüllenir —
/// ham `.black`/`.white` renkleri 03 §4.1 katman 3 gereği YALNIZ burada yaşar; feature view'ları
/// bu bileşeni kullanır, ham renk türetmez. `isLoading` → spinner + devre dışı.
public struct DSAppleSignInButton: View {
    private let title: LocalizedStringKey
    private let isLoading: Bool
    private let action: () -> Void

    public init(
        _ title: LocalizedStringKey,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.s) {
                if isLoading {
                    ProgressView().tint(foreground)
                } else {
                    Image(systemName: "apple.logo")
                        .accessibilityHidden(true)
                    Text(title)
                        .font(DSTypography.bodyEmphasized)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DSSpacing.m)
            .background(background, in: RoundedRectangle(cornerRadius: DSRadius.button))
        }
        .disabled(isLoading)
    }

    /// Apple-imzalı buton zemini (HIG beyaz) — ham renk yalnız bu bileşende; `internal` sadece test.
    var background: Color {
        .white
    }

    /// Zemin üstü ön plan (HIG siyah).
    var foreground: Color {
        .black
    }
}
