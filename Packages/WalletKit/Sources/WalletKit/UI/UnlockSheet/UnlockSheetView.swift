import AppFoundation
import DesignSystem
import SwiftUI

/// UnlockSheet (paywall) — SS-093. İnce SwiftUI katmanı: tüm karar `UnlockSheetModel` +
/// `UnlockSheetViewState` (saf) içindedir. Dark-first, DS token/bileşenleri; ham renk yok.
public struct UnlockSheetView: View {
    @State private var model: UnlockSheetModel

    public init(model: UnlockSheetModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.l) {
            header
            optionsStack
            if let errorReason = model.errorReason {
                errorRow(errorReason)
            }
            footer
        }
        .padding(DSSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColors.surface)
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    // MARK: - Başlık (06 §6.2 #1)

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(model.seriesTitle)
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.textPrimary)
                Text("Bölüm \(model.episodeNumber) · Bu bölüm kilitli")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
                if let teaser = model.teaserText {
                    Text(teaser)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DSSpacing.l)
            Button {
                model.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.textTertiary)
            }
            .accessibilityLabel("Kapat")
        }
    }

    // MARK: - Seçenekler (06 §6.2 sabit sıralama coin → reklam → VIP, yalnız görünür satırlar)

    private var optionsStack: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack {
                Text("Bakiyen")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textSecondary)
                Spacer()
                DSCoinLabel(amount: model.viewState.balanceTotal)
            }
            ForEach(model.viewState.orderedOptions, id: \.self) { option in
                switch option {
                case .coin:
                    coinRow
                case .ad:
                    adRow
                case .vip:
                    vipRow
                }
            }
        }
    }

    // MARK: Coin satırı (birincil)

    private var coinRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            DSButton(
                coinButtonTitle,
                style: .coinCTA,
                isLoading: model.isUnlocking
            ) {
                Task { await model.primaryAction() }
            }
            .disabled(isCoinButtonDisabled)

            Toggle(isOn: autoUnlockBinding) {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text("Sonraki bölümleri otomatik aç")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textPrimary)
                    Text("Kilitli bölümler sorulmadan coin ile açılır")
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textTertiary)
                }
            }
            .tint(DSColors.accent)
        }
    }

    private var coinButtonTitle: LocalizedStringKey {
        switch model.viewState.coinState {
        case let .sufficient(price):
            "\(price) coin ile kilidi aç"
        case let .insufficient(_, shortfall):
            "\(shortfall) coin daha gerekli — Coin Al"
        case .priceUnavailable:
            "Fiyat yüklenemedi, tekrar dene"
        case .balanceProblem:
            "Bakiye sorunu — Coin Mağazası"
        case nil:
            ""
        }
    }

    private var isCoinButtonDisabled: Bool {
        if case .priceUnavailable = model.viewState.coinState {
            return true
        }
        return model.isUnlocking
    }

    private var autoUnlockBinding: Binding<Bool> {
        Binding(get: { model.autoUnlockEnabled }, set: { model.setAutoUnlock($0) })
    }

    // MARK: Reklam satırı (Faz 2 — bayrak açıksa)

    private var adRow: some View {
        DSCard(padding: DSSpacing.m) {
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .foregroundStyle(DSColors.textSecondary)
                Text("Reklam izle, bölümü aç")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textPrimary)
                Spacer()
            }
        }
    }

    // MARK: VIP upsell satırı (06 §6.2 #5)

    private var vipRow: some View {
        Button {
            model.vipUpsellTapped()
        } label: {
            DSCard(padding: DSSpacing.m) {
                HStack(spacing: DSSpacing.m) {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text("VIP ol")
                            .font(DSTypography.bodyEmphasized)
                            .foregroundStyle(DSColors.textPrimary)
                        Text("Tüm bölümler · günlük bonus coin · reklamsız")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.textSecondary)
                    }
                    Spacer()
                    if model.viewState.showsVIPIntro {
                        DSBadge(.vip)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(DSColors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hata (06 §6.6)

    private func errorRow(_ reason: UnlockErrorReason) -> some View {
        Text(errorText(reason))
            .font(DSTypography.caption)
            .foregroundStyle(reason == .priceChanged ? DSColors.warning : DSColors.danger)
    }

    private func errorText(_ reason: UnlockErrorReason) -> LocalizedStringKey {
        switch reason {
        case .network: "Bağlantı sorunu, tekrar dene"
        case .priceChanged: "Fiyat güncellendi"
        }
    }

    // MARK: - Alt (yasal mini linkler yer tutucu)

    private var footer: some View {
        Text("Coin'ler yalnız uygulama içinde geçerlidir, iade edilmez.")
            .font(DSTypography.caption)
            .foregroundStyle(DSColors.textTertiary)
    }
}
