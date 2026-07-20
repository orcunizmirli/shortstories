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

            if let note = model.viewState.coinSpendNote {
                earnedFirstNote(note)
            }

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

    /// Earned-önce harcama şeffaflığı (SS-115 D2 / 06 §2.4): "önce kazanılmış coin kullanılır"
    /// açıklaması. Mesaj saf `EarnedFirstNote`'tan (tek kaynak); burada yalnız DS token'la çizilir.
    private func earnedFirstNote(_ note: EarnedFirstNote) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "info.circle")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textTertiary)
            Text(verbatim: note.message)
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Reklam satırı (06 §6.2 #4 — SS-114; görünürlük/durum server+config-otoriter port'tan)

    /// Satır yalnız port `available`/`capReached` verince orderedOptions'a girer (`hidden` → çizilmez).
    /// `available` → dokununca `watchAd()` (reklam → server SSV → kilit + kesintisiz oynatma). `capReached`
    /// → görünür ama devre dışı ("Yarın yeni hak", 06 §9.2). fill-yok/hata → inline "birazdan tekrar dene".
    private var adRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            Button {
                Task { await model.watchAd() }
            } label: {
                DSCard(padding: DSSpacing.m) {
                    HStack(spacing: DSSpacing.m) {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(isAdActionable ? DSColors.accent : DSColors.textTertiary)
                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(adRowTitle)
                                .font(DSTypography.body)
                                .foregroundStyle(isAdActionable ? DSColors.textPrimary : DSColors.textTertiary)
                            if let subtitle = adRowSubtitle {
                                Text(subtitle)
                                    .font(DSTypography.caption)
                                    .foregroundStyle(DSColors.textTertiary)
                            }
                        }
                        Spacer()
                        if model.isWatchingAd {
                            ProgressView()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!isAdActionable)

            if let adWatchError = model.adWatchError {
                Text(adErrorText(adWatchError))
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.warning)
            }
        }
    }

    private var isAdActionable: Bool {
        model.adAvailability.isActionable && !model.isWatchingAd
    }

    private var adRowTitle: LocalizedStringKey {
        switch model.adAvailability {
        case .available:
            "Reklam izle, bölümü aç"
        case let .capReached(_, dailyCap):
            if let dailyCap {
                "Yarın \(dailyCap) yeni hak"
            } else {
                "Yarın yeni hakların olacak"
            }
        case .hidden:
            "" // satır render edilmez (orderedOptions'ta yok)
        }
    }

    /// "Bugün N/M hak kaldı" — yalnız server kalan hak + cap biliniyorsa (istemci saymaz).
    private var adRowSubtitle: LocalizedStringKey? {
        guard let indicator = model.adAvailability.remainingIndicator else { return nil }
        return "Bugün \(indicator.remaining)/\(indicator.dailyCap) hak kaldı"
    }

    private func adErrorText(_ error: AdWatchError) -> LocalizedStringKey {
        switch error {
        case .temporarilyUnavailable: "Şu an reklam yok, birazdan tekrar dene"
        case .rewardRejected: "Ödül doğrulanamadı, tekrar dene"
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
