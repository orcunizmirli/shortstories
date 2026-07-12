import SwiftUI

/// Tüm token ve bileşenleri state'leriyle sergileyen katalog (SS-007 demo
/// yüzeyi). `DesignSystemCatalog` app target'ı bu view'i host eder.
public struct DSCatalogView: View {
    @State private var selectedGenre = "Dram"
    @State private var isLoadingDemo = true

    private let genres = ["Dram", "Romantik", "Gerilim", "Komedi"]

    private let colorTokens: [(name: String, color: Color)] = [
        ("background", DSColors.background),
        ("surface", DSColors.surface),
        ("surfaceElevated", DSColors.surfaceElevated),
        ("surfaceTabBar", DSColors.surfaceTabBar),
        ("textPrimary", DSColors.textPrimary),
        ("textSecondary", DSColors.textSecondary),
        ("textTertiary", DSColors.textTertiary),
        ("accent", DSColors.accent),
        ("coinGold", DSColors.coinGold),
        ("success", DSColors.success),
        ("warning", DSColors.warning),
        ("danger", DSColors.danger),
        ("overlayScrim", DSColors.overlayScrim),
        ("borderSubtle", DSColors.borderSubtle)
    ]

    private let typographyTokens: [(name: String, font: Font)] = [
        ("display", DSTypography.display),
        ("headingL", DSTypography.headingL),
        ("headingM", DSTypography.headingM),
        ("body", DSTypography.body),
        ("bodyEmphasized", DSTypography.bodyEmphasized),
        ("caption", DSTypography.caption),
        ("captionEmphasized", DSTypography.captionEmphasized),
        ("playerOverlay(size: 15)", DSTypography.playerOverlay(size: 15))
    ]

    private let spacingTokens: [(name: String, value: CGFloat)] = [
        ("xxs", DSSpacing.xxs), ("xs", DSSpacing.xs), ("s", DSSpacing.s),
        ("m", DSSpacing.m), ("l", DSSpacing.l), ("xl", DSSpacing.xl),
        ("xxl", DSSpacing.xxl), ("xxxl", DSSpacing.xxxl)
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xxl) {
                section("Renkler") { colorGrid }
                section("Tipografi") { typographyList }
                section("Spacing") { spacingBars }
                section("Radius & Stroke") { radiusRow }
                section("DSButton") { buttonStates }
                section("DSChip") { chipStates }
                section("DSCard") { cardSample }
            }
            .padding(DSSpacing.l)
        }
        .background(DSColors.background)
        .preferredColorScheme(.dark) // kanon §2: dark-locked
    }

    // MARK: - Bölümler

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text(title)
                .font(DSTypography.headingL)
                .foregroundStyle(DSColors.textPrimary)
            content()
        }
    }

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: DSSpacing.m)], spacing: DSSpacing.m) {
            ForEach(colorTokens, id: \.name) { token in
                VStack(spacing: DSSpacing.xs) {
                    RoundedRectangle(cornerRadius: DSRadius.button)
                        .fill(token.color)
                        .frame(height: 44)
                        .overlay {
                            RoundedRectangle(cornerRadius: DSRadius.button)
                                .strokeBorder(DSColors.borderSubtle, lineWidth: DSStroke.hairline)
                        }
                    Text(token.name)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var typographyList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            ForEach(typographyTokens, id: \.name) { token in
                Text(token.name)
                    .font(token.font)
                    .foregroundStyle(DSColors.textPrimary)
            }
        }
    }

    private var spacingBars: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            ForEach(spacingTokens, id: \.name) { token in
                HStack(spacing: DSSpacing.m) {
                    Text(token.name)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                        .frame(width: 36, alignment: .leading)
                    Rectangle()
                        .fill(DSColors.accent)
                        .frame(width: token.value, height: DSSpacing.s)
                    Text(verbatim: "\(Int(token.value))pt")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textTertiary)
                }
            }
        }
    }

    private var radiusRow: some View {
        HStack(spacing: DSSpacing.l) {
            radiusSample("button", radius: DSRadius.button)
            radiusSample("card", radius: DSRadius.card)
            radiusSample("sheet", radius: DSRadius.sheet)
            VStack(spacing: DSSpacing.xs) {
                Capsule()
                    .fill(DSColors.surfaceElevated)
                    .frame(width: 56, height: 32)
                Text("chip")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
            }
        }
    }

    private func radiusSample(_ name: String, radius: CGFloat) -> some View {
        VStack(spacing: DSSpacing.xs) {
            RoundedRectangle(cornerRadius: radius)
                .fill(DSColors.surfaceElevated)
                .frame(width: 56, height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(DSColors.borderSubtle, lineWidth: DSStroke.hairline)
                }
            Text(name)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
        }
    }

    private var buttonStates: some View {
        VStack(spacing: DSSpacing.m) {
            DSButton("Primary — İzlemeye Başla") {}
            DSButton("Secondary — Listeye Ekle", style: .secondary) {}
            DSButton("Coin CTA — Bölümü Aç (30 coin)", style: .coinCTA) {}
            HStack(spacing: DSSpacing.m) {
                DSButton("Compact", size: .compact) {}
                DSButton("Compact Secondary", style: .secondary, size: .compact) {}
            }
            DSButton("Loading", isLoading: isLoadingDemo) {}
            Toggle("isLoading", isOn: $isLoadingDemo)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textSecondary)
                .tint(DSColors.accent)
            Button("ButtonStyle: .dsPrimary") {}
                .buttonStyle(.dsPrimary)
        }
    }

    private var chipStates: some View {
        HStack(spacing: DSSpacing.s) {
            ForEach(genres, id: \.self) { genre in
                DSChip(LocalizedStringKey(genre), isSelected: genre == selectedGenre) {
                    selectedGenre = genre
                }
            }
        }
    }

    private var cardSample: some View {
        DSCard {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                Text("Kayıp Varis")
                    .font(DSTypography.headingM)
                    .foregroundStyle(DSColors.textPrimary)
                Text("62 bölüm • Dram")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
                DSButton("Devam Et", size: .compact) {}
            }
        }
    }
}

#Preview {
    DSCatalogView()
}
