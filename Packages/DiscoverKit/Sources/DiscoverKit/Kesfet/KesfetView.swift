import ContentKit
import DesignSystem
import SwiftUI

/// Kesfet ekranı (SS-070/071/074) — ince SwiftUI katmanı: tüm karar `KesfetModel` +
/// `KesfetComposition` (saf) içindedir. Dark-first, DS token/bileşenleri; ham renk yok.
/// Dikey scroll raf mimarisi (02 §4.10): sabit üst bölge (arama + tür çipleri), banner,
/// yatay kart rafları. Raf başına yatay kaydırma.
public struct KesfetView: View {
    @State private var model: KesfetModel

    public init(model: KesfetModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if model.showsOfflineBanner {
                DSOfflineBanner(onRetry: { Task { await model.refresh() } })
            }
            topBar
            content
        }
        .background(DSColors.background)
        .onAppear { model.onAppear() }
    }

    // MARK: - Üst sabit bölge (02 §4.10)

    private var topBar: some View {
        VStack(spacing: DSSpacing.m) {
            searchBarButton
            genreChips
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.m)
    }

    /// Arama çubuğu görünümlü buton — dokununca `Arama`'ya push (klavye orada açılır).
    private var searchBarButton: some View {
        Button { model.openSearch() } label: {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DSColors.textTertiary)
                Text("Dizi, tür veya etiket ara")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(DSColors.surfaceElevated, in: Capsule())
        }
        .accessibilityLabel("Ara")
    }

    private var genreChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.s) {
                DSChip("Tümü", isSelected: model.selectedGenreID == nil) {
                    model.selectGenre(nil)
                }
                ForEach(model.composition.availableGenres) { genre in
                    DSChip(
                        LocalizedStringKey(genre.name),
                        isSelected: model.selectedGenreID == genre.id
                    ) {
                        model.selectGenre(genre.id)
                    }
                }
            }
        }
    }

    // MARK: - İçerik (durum makinesi, 02 §3)

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .idle, .loading:
            DSStateView(.loading(skeleton: .shelf))
            Spacer()
        case .error:
            DSStateView(.error(message: "Keşfet yüklenemedi", retry: { Task { await model.refresh() } }))
        case .offline:
            DSStateView(.offline(retry: { Task { await model.refresh() } }))
        case .loaded:
            if model.composition.isFilteredEmpty {
                filteredEmptyState
            } else {
                shelves
            }
        }
    }

    private var filteredEmptyState: some View {
        DSStateView(
            .empty(
                message: "Bu türde henüz içerik yok",
                systemImage: "square.grid.2x2",
                action: .init(title: "Filtreyi temizle") { model.clearFilter() }
            )
        )
    }

    private var shelves: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DSSpacing.xl) {
                bannerCarousel
                ForEach(model.composition.shelves) { shelf in
                    shelfSection(shelf)
                }
            }
            .padding(.vertical, DSSpacing.l)
        }
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var bannerCarousel: some View {
        let banners = model.composition.banners
        if !banners.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.m) {
                    ForEach(Array(banners.enumerated()), id: \.element.id) { index, banner in
                        Button { model.selectBanner(banner, position: index) } label: {
                            bannerCard(banner)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DSSpacing.l)
            }
        }
    }

    private func bannerCard(_ banner: Banner) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(DSColors.surfaceElevated)
            if let title = banner.title {
                Text(title)
                    .font(DSTypography.headingM)
                    .foregroundStyle(DSColors.overlayForeground)
                    .padding(DSSpacing.m)
            }
        }
        .frame(width: 300, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.card))
        .accessibilityLabel(banner.title.map { LocalizedStringKey($0) } ?? "Banner")
    }

    private func shelfSection(_ shelf: KesfetComposition.Shelf) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSSectionHeader(
                LocalizedStringKey(shelf.title),
                onSeeAll: { model.selectSeeAll(shelf: shelf) }
            )
            .padding(.horizontal, DSSpacing.l)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: DSSpacing.m) {
                    ForEach(Array(shelf.series.enumerated()), id: \.element.id) { index, series in
                        shelfCard(shelf: shelf, series: series, position: index)
                    }
                }
                .padding(.horizontal, DSSpacing.l)
            }
        }
    }

    private func shelfCard(shelf: KesfetComposition.Shelf, series: Series, position: Int) -> some View {
        HStack(alignment: .center, spacing: DSSpacing.xs) {
            if shelf.showsRankBadges {
                Text(verbatim: "\(position + 1)")
                    .font(DSTypography.display)
                    .foregroundStyle(DSColors.textSecondary)
            }
            DSSeriesCard(
                title: series.title,
                subtitle: series.genres.first?.name,
                size: .shelf
            ) {
                model.selectSeries(series, shelfID: shelf.id, position: position)
            }
        }
    }
}
