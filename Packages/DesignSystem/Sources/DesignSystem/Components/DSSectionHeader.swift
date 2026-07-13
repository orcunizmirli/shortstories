import SwiftUI

/// Raf başlığı + opsiyonel "Tümü" aksiyonu (02 §4.10: her raf başlığının
/// sağında "Tümü" → dikey ızgara sayfası).
public struct DSSectionHeader: View {
    private let title: LocalizedStringKey
    private let seeAllTitle: LocalizedStringKey
    private let onSeeAll: (() -> Void)?

    public init(
        _ title: LocalizedStringKey,
        seeAllTitle: LocalizedStringKey = "Tümü",
        onSeeAll: (() -> Void)? = nil
    ) {
        self.title = title
        self.seeAllTitle = seeAllTitle
        self.onSeeAll = onSeeAll
    }

    /// "Tümü" butonu görünür mü (test kancası).
    var showsSeeAll: Bool {
        onSeeAll != nil
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.m) {
            Text(title)
                .font(DSTypography.headingM)
                .foregroundStyle(DSColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DSSpacing.s)
            if let onSeeAll {
                Button(action: onSeeAll) {
                    HStack(spacing: DSSpacing.xxs) {
                        Text(seeAllTitle)
                            .font(DSTypography.captionEmphasized)
                        Image(systemName: "chevron.right")
                            .font(DSTypography.caption)
                    }
                    .foregroundStyle(DSColors.textSecondary)
                }
                .accessibilityHint("Rafın tamamını ızgara görünümünde açar")
            }
        }
    }
}
