import SwiftUI

/// Tüm token ve bileşenleri state'leriyle sergileyen katalog (SS-007 demo
/// yüzeyi). `DesignSystemCatalog` app target'ı bu view'i host eder.
public struct DSCatalogView: View {
    private enum StateDemo: String, CaseIterable {
        case loading = "Yükleniyor"
        case loadingGrid = "Izgara"
        case empty = "Boş"
        case error = "Hata"
        case offline = "Offline"
    }

    @State private var selectedGenre = "Dram"
    @State private var isLoadingDemo = true
    @State private var stateDemo: StateDemo = .empty
    @State private var progressDemo = 0.62

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
        ("overlayForeground", DSColors.overlayForeground),
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
                section("DSBadge") { badgeStates }
                section("DSProgressBar") { progressStates }
                section("DSSectionHeader") { sectionHeaderStates }
                section("DSSeriesCard") { seriesCardStates }
                section("DSStateView") { stateViewStates }
                section("DSOfflineBanner") { offlineBannerStates }
                section("DSCoinLabel") { coinLabelStates }
                section("DSAvatar") { avatarStates }
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

// MARK: - F1 bileşen bölümleri (E2 devamı)

private extension DSCatalogView {
    var badgeStates: some View {
        HStack(alignment: .center, spacing: DSSpacing.l) {
            DSBadge(.newEpisode)
            DSBadge(.vip)
            DSBadge(.locked)
            DSBadge(.topRank(1))
        }
    }

    var progressStates: some View {
        VStack(spacing: DSSpacing.m) {
            ForEach([0.0, 0.33, 1.0], id: \.self) { value in
                DSProgressBar(progress: value)
            }
            DSProgressBar(progress: progressDemo, height: 6)
            HStack(spacing: DSSpacing.m) {
                Text("progress")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
                Slider(value: $progressDemo, in: 0 ... 1)
                    .tint(DSColors.accent)
                    .accessibilityLabel("İzleme ilerlemesi demo değeri")
            }
        }
    }

    var sectionHeaderStates: some View {
        VStack(spacing: DSSpacing.m) {
            DSSectionHeader("Trend", onSeeAll: {})
            DSSectionHeader("Senin İçin")
        }
    }

    var seriesCardStates: some View {
        VStack(alignment: .leading, spacing: DSSpacing.l) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DSSpacing.m) {
                    DSSeriesCard(title: "Kayıp Varis", subtitle: "Dram", badge: .newEpisode) {}
                    DSSeriesCard(title: "CEO'nun Sırrı", badge: .vip) {}
                    DSSeriesCard(title: "İntikam Gecesi", badge: .locked, progress: progressDemo) {}
                    DSSeriesCard(title: "Gizli Miras", badge: .topRank(1)) {}
                    DSSeriesCard(title: "Devam Et Kartı — Çok Uzun Bir Dizi Adı", progress: 0.4) {}
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.m), count: 3), spacing: DSSpacing.m) {
                DSSeriesCard(title: "Izgara Kartı", size: .grid) {}
                DSSeriesCard(title: "Yeni Bölüm", size: .grid, badge: .newEpisode) {}
                DSSeriesCard(title: "İki Satıra Taşan Dizi Adı Örneği", size: .grid, progress: 0.8) {}
            }
        }
    }

    var stateViewStates: some View {
        VStack(spacing: DSSpacing.m) {
            Picker("Durum", selection: $stateDemo) {
                ForEach(StateDemo.allCases, id: \.self) { demo in
                    Text(demo.rawValue).tag(demo)
                }
            }
            .pickerStyle(.segmented)
            Group {
                switch stateDemo {
                case .loading:
                    DSStateView(.loading)
                case .loadingGrid:
                    DSStateView(.loading(skeleton: .grid(columns: 3)))
                case .empty:
                    DSStateView(
                        .empty(
                            message: "Henüz favorin yok — kalbe dokun, burada birikir",
                            systemImage: "heart",
                            action: DSStateView.EmptyAction(title: "Keşfet'e Git", handler: {})
                        )
                    )
                case .error:
                    DSStateView(.error(message: "Bir şeyler ters gitti", retry: {}))
                case .offline:
                    DSStateView(.offline(retry: {}))
                }
            }
            .frame(minHeight: 220)
        }
    }

    var offlineBannerStates: some View {
        VStack(spacing: DSSpacing.m) {
            DSOfflineBanner()
            DSOfflineBanner(onRetry: {})
        }
    }

    var coinLabelStates: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSCoinLabel(amount: 70)
            DSCoinLabel(amount: 12500, size: .large)
        }
    }

    var avatarStates: some View {
        HStack(spacing: DSSpacing.l) {
            DSAvatar(name: "Ayşe Yılmaz")
            DSAvatar(name: "Zeynep", diameter: 56)
            DSAvatar(name: "")
        }
    }
}

#Preview {
    DSCatalogView()
}
