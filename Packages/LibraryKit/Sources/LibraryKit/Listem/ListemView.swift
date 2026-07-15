import DesignSystem
import SwiftUI

/// `Listem` ekranı (SS-120) — ince SwiftUI katmanı: tüm karar `ListemModel` + saf türetimler
/// (`MyListSegment`/`ContinueWatchingItem`/`RelativeDay`) içindedir. Dark-first, DS token/bileşen;
/// ham renk yok. Poster görselini yükleme feature pipeline'ının işidir (DS kartları hazır `Image`
/// alır); bu sürümde placeholder yüzey çizilir.
public struct ListemView: View {
    @State private var model: ListemModel

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.s), count: 3)

    public init(model: ListemModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(spacing: DSSpacing.l) {
            header
            segmentPicker
            content
        }
        .padding(.top, DSSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSColors.background)
        .onAppear { model.onAppear() }
        .task { await model.syncAndReload() }
    }

    // MARK: - Başlık + segment kontrolü

    private var header: some View {
        HStack {
            Text("Listem")
                .font(DSTypography.headingL)
                .foregroundStyle(DSColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if model.segment == .favorites, !model.favorites.isEmpty {
                Button(model.isEditing ? "Bitti" : "Düzenle") {
                    model.toggleEditing()
                }
                .font(DSTypography.captionEmphasized)
                .foregroundStyle(DSColors.accent)
            }
        }
        .padding(.horizontal, DSSpacing.l)
    }

    private var segmentPicker: some View {
        Picker("Segment", selection: segmentBinding) {
            ForEach(model.visibleSegments, id: \.self) { segment in
                Text(segmentTitle(segment)).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, DSSpacing.l)
    }

    private var segmentBinding: Binding<MyListSegment> {
        Binding(get: { model.segment }, set: { model.selectSegment($0) })
    }

    private func segmentTitle(_ segment: MyListSegment) -> LocalizedStringKey {
        switch segment {
        case .favorites: "Favoriler"
        case .continueWatching: "Devam Et"
        case .downloads: "İndirilenler"
        }
    }

    // MARK: - İçerik

    @ViewBuilder
    private var content: some View {
        switch model.segment {
        case .favorites:
            favoritesContent
        case .continueWatching:
            continueContent
        case .downloads:
            Spacer()
        }
    }

    // MARK: - Favoriler

    @ViewBuilder
    private var favoritesContent: some View {
        switch model.favoritesState {
        case .loading:
            DSStateView(.loading(skeleton: .grid(columns: 3)))
        case .empty:
            DSStateView(.empty(
                message: "Henüz favorin yok — kalbe dokun, burada birikir",
                systemImage: "heart",
                action: DSStateView.EmptyAction(title: "Keşfet'e Göz At") { model.openDiscover() }
            ))
        case .loaded:
            favoritesGrid
        }
    }

    private var favoritesGrid: some View {
        ScrollView {
            VStack(spacing: DSSpacing.l) {
                if model.isEditing, !model.selectedForRemoval.isEmpty {
                    DSButton(
                        "Kaldır (\(model.selectedForRemoval.count))",
                        style: .secondary,
                        size: .compact
                    ) { Task { await model.removeSelected() } }
                        .padding(.horizontal, DSSpacing.l)
                }
                LazyVGrid(columns: gridColumns, spacing: DSSpacing.l) {
                    ForEach(model.favorites) { item in
                        favoriteCell(item)
                    }
                }
                .padding(.horizontal, DSSpacing.l)
            }
            .padding(.bottom, DSSpacing.xxl)
        }
    }

    private func favoriteCell(_ item: FavoriteItem) -> some View {
        DSSeriesCard(
            title: item.title,
            size: .grid,
            onTap: { favoriteTap(item) }
        )
        .opacity(cellOpacity(item))
        .overlay(alignment: .topTrailing) {
            if model.isEditing {
                Image(systemName: model.selectedForRemoval.contains(item.seriesID)
                    ? "checkmark.circle.fill" : "circle")
                    .font(DSTypography.headingM)
                    .foregroundStyle(model.selectedForRemoval.contains(item.seriesID)
                        ? DSColors.accent : DSColors.textTertiary)
                    .padding(DSSpacing.xs)
            }
        }
        .contextMenu {
            Button("Detaya Git") { model.openDetail(item.seriesID) }
            Button("Paylaş") { model.shareFavorite(item.seriesID) }
            Button("Favorilerden Kaldır", role: .destructive) {
                Task { await model.removeFavorite(item.seriesID) }
            }
        }
    }

    private func cellOpacity(_ item: FavoriteItem) -> Double {
        item.isAvailable ? 1 : 0.5
    }

    private func favoriteTap(_ item: FavoriteItem) {
        if model.isEditing {
            model.toggleSelection(item.seriesID)
        } else {
            model.openFavorite(item)
        }
    }

    // MARK: - Devam Et

    @ViewBuilder
    private var continueContent: some View {
        switch model.continueState {
        case .loading:
            DSStateView(.loading(skeleton: .grid(columns: 1)))
        case .empty:
            DSStateView(.empty(
                message: "İzlemeye başladıkların burada görünür",
                systemImage: "play.circle",
                action: DSStateView.EmptyAction(title: "Ana Sayfa'ya Git") { model.openHome() }
            ))
        case .loaded:
            continueList
        }
    }

    private var continueList: some View {
        ScrollView {
            LazyVStack(spacing: DSSpacing.m) {
                ForEach(model.continueItems) { item in
                    continueRow(item)
                }
            }
            .padding(.horizontal, DSSpacing.l)
            .padding(.bottom, DSSpacing.xxl)
        }
    }

    private func continueRow(_ item: ContinueWatchingItem) -> some View {
        Button { model.openContinue(item) } label: {
            HStack(spacing: DSSpacing.m) {
                poster(for: item)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(item.seriesTitle)
                        .font(DSTypography.bodyEmphasized)
                        .foregroundStyle(DSColors.textPrimary)
                        .lineLimit(1)
                    Text(subtitle(for: item))
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                        .lineLimit(1)
                    DSProgressBar(progress: item.progressFraction)
                    Text(relativeText(for: item))
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textTertiary)
                }
                Spacer(minLength: DSSpacing.s)
                Image(systemName: "play.circle.fill")
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.accent)
                    .accessibilityHidden(true)
            }
            .padding(DSSpacing.m)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
            .opacity(item.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button("Kaldır", role: .destructive) { model.hideContinueItem(item) }
        }
    }

    private func poster(for item: ContinueWatchingItem) -> some View {
        RoundedRectangle(cornerRadius: DSRadius.card)
            .fill(DSColors.surfaceElevated)
            .frame(width: 54, height: 81)
            .accessibilityHidden(true)
    }

    private func subtitle(for item: ContinueWatchingItem) -> String {
        if let number = item.episodeNumber {
            "Bölüm \(number) · %\(item.progressPercent)"
        } else {
            "%\(item.progressPercent)"
        }
    }

    private func relativeText(for item: ContinueWatchingItem) -> String {
        switch model.relativeDay(for: item) {
        case .today: "bugün"
        case .yesterday: "dün"
        case let .daysAgo(days): "\(days) gün önce"
        case let .weeksAgo(weeks): "\(weeks) hafta önce"
        case .longAgo: "uzun süre önce"
        }
    }
}
