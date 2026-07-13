import SwiftUI

/// Ekran üstü kalıcı ince offline banner'ı — 02 §3 birincil offline
/// davranışı ("Çevrimdışısın"). İçerik görünür kalırken bağlantı durumunu
/// ince bir şeritte bildirir; tam-ekran offline hali `DSStateView.offline`
/// olarak kalır. Retry opsiyoneldir.
public struct DSOfflineBanner: View {
    private let message: LocalizedStringKey
    private let retryTitle: LocalizedStringKey
    private let onRetry: (() -> Void)?

    public init(
        message: LocalizedStringKey = "Çevrimdışısın",
        retryTitle: LocalizedStringKey = "Tekrar Dene",
        onRetry: (() -> Void)? = nil
    ) {
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    /// Retry butonu görünür mü (test kancası).
    var showsRetry: Bool {
        onRetry != nil
    }

    /// Retry aksiyonu (test kancası).
    var retryAction: (() -> Void)? {
        onRetry
    }

    public var body: some View {
        HStack(spacing: DSSpacing.s) {
            Image(systemName: "wifi.slash")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
                .accessibilityHidden(true)
            Text(message)
                .font(DSTypography.captionEmphasized)
                .foregroundStyle(DSColors.textPrimary)
            Spacer(minLength: DSSpacing.s)
            if let onRetry {
                Button(action: onRetry) {
                    Text(retryTitle)
                        .font(DSTypography.captionEmphasized)
                        .foregroundStyle(DSColors.accent)
                }
            }
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.s)
        .frame(maxWidth: .infinity)
        .background(DSColors.surfaceElevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DSColors.borderSubtle)
                .frame(height: DSStroke.hairline)
        }
    }
}
