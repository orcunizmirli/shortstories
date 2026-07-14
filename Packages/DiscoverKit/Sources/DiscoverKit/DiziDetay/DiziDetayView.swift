import ContentKit
import DesignSystem
import SwiftUI

/// DiziDetay ekranı (SS-080/081/083) — ince SwiftUI katmanı: tüm karar `DiziDetayModel` +
/// saf türetimler (`ContinueWatchingTarget`/`EpisodeCellState`/`ReleaseScheduleInfo`) içindedir.
/// Dark-first, DS token/bileşenleri; ham renk yok.
public struct DiziDetayView: View {
    @State private var model: DiziDetayModel

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.s), count: 5)

    public init(model: DiziDetayModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        content
            .background(DSColors.background)
            .onAppear { model.onAppear() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            DSStateView(.loading(skeleton: .grid(columns: 5)))
        case .error:
            DSStateView(.error(message: "Dizi yüklenemedi", retry: { Task { await model.load() } }))
        case .offline:
            DSStateView(.offline(retry: { Task { await model.load() } }))
        case .removed:
            DSStateView(.empty(
                message: "Bu dizi artık yayında değil",
                systemImage: "film",
                action: DSStateView.EmptyAction(title: "Keşfet'e Dön") { model.openDiscover() }
            ))
        case .loaded:
            loaded
        }
    }

    @ViewBuilder
    private var loaded: some View {
        if let series = model.series {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.xl) {
                    hero(series)
                    ctaRow
                    synopsis(series)
                    if !series.tags.isEmpty {
                        tagChips(series)
                    }
                    episodeGrid
                }
                .padding(.bottom, DSSpacing.xxl)
            }
        }
    }

    // MARK: - Hero (§4.4)

    private func hero(_ series: Series) -> some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(DSColors.surfaceElevated)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(series.title)
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.overlayForeground)
                Text(metaLine(series))
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.overlayForeground)
            }
            .padding(DSSpacing.l)
        }
        .overlay(alignment: .topTrailing) {
            Button { model.share() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(DSTypography.headingM)
                    .foregroundStyle(DSColors.overlayForeground)
                    .padding(DSSpacing.m)
            }
            .accessibilityLabel("Paylaş")
        }
    }

    private func metaLine(_ series: Series) -> String {
        var parts = ["\(series.episodeCount) Bölüm"]
        parts.append(contentsOf: series.genres.prefix(2).map(\.name))
        parts.append(releaseText)
        return parts.joined(separator: " · ")
    }

    private var releaseText: String {
        switch model.releaseInfo {
        case .completed:
            "Tamamlandı"
        case .ongoingScheduled:
            model.releaseInfo?.newEpisodeWeekday(calendar: .current).map { "Yeni bölüm: \($0)" } ?? "Devam ediyor"
        case .ongoingUnknown, .none:
            "Devam ediyor"
        }
    }

    // MARK: - CTA (§4.4)

    private var ctaRow: some View {
        HStack(spacing: DSSpacing.m) {
            DSButton(ctaTitle) { model.primaryCTA() }
            Button { Task { await model.toggleFavorite() } } label: {
                Image(systemName: model.isFavorite ? "heart.fill" : "heart")
                    .font(DSTypography.headingM)
                    .foregroundStyle(model.isFavorite ? DSColors.accent : DSColors.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(DSColors.surfaceElevated, in: Circle())
            }
            .accessibilityLabel(model.isFavorite ? "Listeden çıkar" : "Listeye ekle")
        }
        .padding(.horizontal, DSSpacing.l)
    }

    private var ctaTitle: LocalizedStringKey {
        guard let target = model.ctaTarget, target.kind == .resume else {
            return "İzlemeye Başla"
        }
        return model.ctaLocked
            ? "Devam Et · Bölüm \(target.episodeNumber) 🔒"
            : "Devam Et · Bölüm \(target.episodeNumber)"
    }

    // MARK: - Özet (§4.4)

    private func synopsis(_ series: Series) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(series.synopsis)
                .font(DSTypography.body)
                .foregroundStyle(DSColors.textSecondary)
                .lineLimit(model.synopsisExpanded ? nil : 3)
            Button(model.synopsisExpanded ? "Daha az" : "Devamını gör") { model.toggleSynopsis() }
                .font(DSTypography.captionEmphasized)
                .foregroundStyle(DSColors.accent)
        }
        .padding(.horizontal, DSSpacing.l)
    }

    private func tagChips(_ series: Series) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.s) {
                ForEach(series.tags) { tag in
                    DSChip(LocalizedStringKey(tag.name), isSelected: false) {
                        model.selectTag(tag)
                    }
                }
            }
            .padding(.horizontal, DSSpacing.l)
        }
    }

    // MARK: - Bölüm ızgarası (§4.4)

    private var episodeGrid: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            Text("Bölümler")
                .font(DSTypography.headingM)
                .foregroundStyle(DSColors.textPrimary)
                .padding(.horizontal, DSSpacing.l)
            LazyVGrid(columns: gridColumns, spacing: DSSpacing.s) {
                ForEach(model.episodes) { episode in
                    episodeCell(episode)
                        .onAppear {
                            if episode.id == model.episodes.last?.id {
                                Task { await model.loadMoreEpisodes() }
                            }
                        }
                }
            }
            .padding(.horizontal, DSSpacing.l)
        }
    }

    private func episodeCell(_ episode: Episode) -> some View {
        let state = model.cellState(for: episode)
        return Button { model.selectEpisode(episode) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .fill(DSColors.surfaceElevated)
                episodeCellContent(episode: episode, state: state)
            }
            .frame(height: 48)
            .opacity(state == .watched ? 0.5 : 1)
            .overlay {
                if state == .current {
                    RoundedRectangle(cornerRadius: DSRadius.card)
                        .strokeBorder(DSColors.accent, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(episodeAccessibilityLabel(episode: episode, state: state))
    }

    @ViewBuilder
    private func episodeCellContent(episode: Episode, state: EpisodeCellState) -> some View {
        switch state {
        case let .locked(price):
            VStack(spacing: DSSpacing.xxs) {
                Image(systemName: "lock.fill")
                    .font(DSTypography.caption)
                if let price {
                    Text(verbatim: "\(price)")
                        .font(DSTypography.caption)
                }
            }
            .foregroundStyle(DSColors.textSecondary)
        case .scheduled:
            Image(systemName: "calendar")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textTertiary)
        case .watched:
            HStack(spacing: DSSpacing.xxs) {
                Text(verbatim: "\(episode.index)")
                Image(systemName: "checkmark")
                    .font(DSTypography.caption)
            }
            .font(DSTypography.bodyEmphasized)
            .foregroundStyle(DSColors.textSecondary)
        case .current, .available:
            Text(verbatim: "\(episode.index)")
                .font(DSTypography.bodyEmphasized)
                .foregroundStyle(state == .current ? DSColors.accent : DSColors.textPrimary)
        }
    }

    private func episodeAccessibilityLabel(episode: Episode, state: EpisodeCellState) -> String {
        let base = "Bölüm \(episode.index)"
        switch state {
        case .watched: return "\(base), izlendi"
        case .current: return "\(base), kaldığın bölüm"
        case .available: return base
        case let .locked(price): return price.map { "\(base), kilitli, \($0) coin" } ?? "\(base), kilitli"
        case .scheduled: return "\(base), yakında"
        }
    }
}
