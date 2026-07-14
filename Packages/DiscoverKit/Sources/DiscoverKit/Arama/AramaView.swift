import ContentKit
import DesignSystem
import SwiftUI

/// Arama ekranı (SS-072/073) — ince SwiftUI katmanı: debounce/karar `AramaModel` +
/// `SearchInputMachine` (saf) içindedir. Dark-first, DS token/bileşenleri; ham renk yok.
public struct AramaView: View {
    @State private var model: AramaModel
    @FocusState private var searchFieldFocused: Bool

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.m), count: 3)

    public init(model: AramaModel) {
        _model = State(wrappedValue: model)
    }

    private var queryBinding: Binding<String> {
        Binding(get: { model.queryText }, set: { model.queryChanged($0) })
    }

    public var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .background(DSColors.background)
        .onAppear {
            model.onAppear()
            searchFieldFocused = true
        }
    }

    // MARK: - Arama çubuğu

    private var searchBar: some View {
        HStack(spacing: DSSpacing.m) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DSColors.textTertiary)
                TextField("Ara", text: queryBinding)
                    .focused($searchFieldFocused)
                    .textFieldStyle(.plain)
                    .foregroundStyle(DSColors.textPrimary)
                    .submitLabel(.search)
                    .onSubmit { model.submit() }
                    .autocorrectionDisabled()
                if !model.queryText.isEmpty {
                    Button { model.queryChanged("") } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DSColors.textTertiary)
                    }
                    .accessibilityLabel("Temizle")
                }
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)
            .background(DSColors.surfaceElevated, in: Capsule())

            Button("İptal") { model.cancel() }
                .font(DSTypography.body)
                .foregroundStyle(DSColors.accent)
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.vertical, DSSpacing.m)
    }

    // MARK: - İçerik (mod makinesi)

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .browsing:
            browsing
        case .suggesting:
            suggestionList
        case .results:
            resultsArea
        case let .noResult(query):
            noResult(query: query)
        }
    }

    // MARK: Boş sorgu: son + popüler (§4.11)

    private var browsing: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                if !model.recentSearches.isEmpty {
                    recentSection
                }
                if !model.popularSearches.isEmpty {
                    popularSection
                }
            }
            .padding(DSSpacing.l)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack {
                Text("Son Aramalar")
                    .font(DSTypography.headingM)
                    .foregroundStyle(DSColors.textPrimary)
                Spacer()
                Button("Temizle") { model.clearRecents() }
                    .font(DSTypography.captionEmphasized)
                    .foregroundStyle(DSColors.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.s) {
                    ForEach(model.recentSearches, id: \.self) { query in
                        DSChip(LocalizedStringKey(query), isSelected: false) {
                            model.selectQuery(query)
                        }
                    }
                }
            }
        }
    }

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text("Popüler Aramalar")
                .font(DSTypography.headingM)
                .foregroundStyle(DSColors.textPrimary)
            ForEach(Array(model.popularSearches.enumerated()), id: \.element) { index, query in
                Button { model.selectQuery(query) } label: {
                    HStack(spacing: DSSpacing.m) {
                        Text(verbatim: "\(index + 1)")
                            .font(DSTypography.bodyEmphasized)
                            .foregroundStyle(DSColors.textTertiary)
                        Text(query)
                            .font(DSTypography.body)
                            .foregroundStyle(DSColors.textPrimary)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Öneri listesi (§4.11)

    private var suggestionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(model.suggestions) { suggestion in
                    Button { model.selectSuggestion(suggestion) } label: {
                        HStack(spacing: DSSpacing.m) {
                            Image(systemName: suggestion.kind == .series ? "play.rectangle" : "magnifyingglass")
                                .foregroundStyle(DSColors.textTertiary)
                            Text(suggestion.text)
                                .font(DSTypography.body)
                                .foregroundStyle(DSColors.textPrimary)
                            Spacer()
                        }
                        .padding(.horizontal, DSSpacing.l)
                        .padding(.vertical, DSSpacing.m)
                    }
                }
            }
        }
    }

    // MARK: Sonuç ızgarası (§4.11)

    @ViewBuilder
    private var resultsArea: some View {
        if model.isLoadingResults {
            DSStateView(.loading(skeleton: .grid(columns: 3)))
        } else if model.hasResultsError {
            DSStateView(.error(message: "Arama başarısız", retry: { model.retryResults() }))
        } else {
            resultsGrid
        }
    }

    private var resultsGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: DSSpacing.m) {
                ForEach(Array(model.results.enumerated()), id: \.element.id) { index, series in
                    DSSeriesCard(
                        title: series.title,
                        subtitle: series.genres.first?.name,
                        size: .grid
                    ) {
                        model.selectResult(series, position: index)
                    }
                    .onAppear {
                        if series.id == model.results.last?.id, model.canLoadMore {
                            Task { await model.loadMore() }
                        }
                    }
                }
            }
            .padding(DSSpacing.l)
            if model.isLoadingMore {
                ProgressView().tint(DSColors.textSecondary)
            }
        }
    }

    // MARK: Sonuç yok (§4.11)

    private func noResult(query: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.xl) {
                Text("\"\(query)\" için sonuç yok")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textSecondary)
                    .padding(.top, DSSpacing.xl)
                if !model.popularSearches.isEmpty {
                    popularSection
                }
                // §4.11 boş durum: kullanıcıyı içeriğe geri götüren Keşfet CTA'sı.
                DSButton("Keşfet'e Dön", size: .compact) { model.cancel() }
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacing.l)
        }
    }
}
