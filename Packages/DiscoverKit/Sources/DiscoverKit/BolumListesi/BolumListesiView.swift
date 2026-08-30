import ContentKit
import DesignSystem
import SwiftUI

/// BolumListesi sheet (04 §8.5): player feed sağ-ray "Bölümler" → 5 sütunlu bölüm ızgarası. İnce SwiftUI
/// katmanı; tüm karar `BolumListesiModel`'de. Kilitli bölüm kilit ikonuyla; aktif bölüm vurgulu. Bir
/// bölüme dokunmak `model.selectEpisode` (App feed'i o bölüme geçirir + sheet kapanır). Dark-first, DS token.
public struct BolumListesiView: View {
    @State private var model: BolumListesiModel

    private let gridColumns = Array(repeating: GridItem(.flexible(), spacing: DSSpacing.s), count: 5)

    public init(model: BolumListesiModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        NavigationStack {
            content
                .background(DSColors.background)
                .navigationTitle("Bölümler")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(DSColors.textPrimary)
                        }
                        .accessibilityLabel("Kapat")
                    }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadState {
        case .loading:
            DSStateView(.loading(skeleton: .grid(columns: 5)))
        case .error:
            DSStateView(.error(message: "Bölümler yüklenemedi", retry: { Task { await model.load() } }))
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: DSSpacing.s) {
                ForEach(model.rows) { row in
                    cell(row)
                }
            }
            .padding(DSSpacing.l)
        }
    }

    private func cell(_ row: BolumListesiModel.Row) -> some View {
        Button {
            model.selectEpisode(row)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: DSRadius.button)
                    .fill(row.isCurrent ? DSColors.accent : DSColors.surface)
                    .overlay(
                        Text("\(row.number)")
                            .font(DSTypography.bodyEmphasized)
                            .foregroundStyle(row.isCurrent ? DSColors.overlayForeground : DSColors.textPrimary)
                    )
                    .aspectRatio(1, contentMode: .fit)
                if row.isScheduled {
                    Image(systemName: "calendar")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                        .padding(DSSpacing.xs)
                } else if !row.isPlayable {
                    Image(systemName: "lock.fill")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                        .padding(DSSpacing.xs)
                }
            }
        }
        .accessibilityLabel("Bölüm \(row.number)\(cellStatusLabel(row))\(row.isCurrent ? ", şu an" : "")")
    }

    private func cellStatusLabel(_ row: BolumListesiModel.Row) -> String {
        if row.isScheduled {
            return ", yakında"
        }
        return row.isPlayable ? "" : ", kilitli"
    }
}
