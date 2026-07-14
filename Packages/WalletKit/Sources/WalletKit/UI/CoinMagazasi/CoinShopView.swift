import AppFoundation
import DesignSystem
import SwiftUI

/// CoinMagazasi — SS-094. İnce SwiftUI katmanı; katalog birleştirme + satın alma durum makinesi
/// `CoinShopModel`'dedir. Fiyatlar StoreKit `displayPrice`'tan; ham renk yok, DS token/bileşenleri.
public struct CoinShopView: View {
    @State private var model: CoinShopModel

    public init(model: CoinShopModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                header
                content
                footer
            }
            .padding(DSSpacing.l)
        }
        .background(DSColors.background)
        .overlay(alignment: .bottom) { transientBanner }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    // MARK: - Başlık (06 §7.1)

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                DSCoinLabel(amount: model.balance.totalCoins, size: .large)
                    .animation(.snappy, value: model.balance.totalCoins)
                Spacer()
                Button { model.dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DSTypography.headingL)
                        .foregroundStyle(DSColors.textTertiary)
                }
                .accessibilityLabel("Kapat")
            }
            if model.balance.earnedCoins > 0 {
                Text("\(earnedCoinsText(model.balance.earnedCoins)) coin kazanılmış")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.textSecondary)
            }
            if let expiry = model.earnedExpiringSoon {
                Text("\(expiry.amount) coin yakında sona erecek")
                    .font(DSTypography.caption)
                    .foregroundStyle(DSColors.warning)
            }
            if model.firstTopUpEligible {
                firstTopUpBanner
            }
        }
    }

    private var firstTopUpBanner: some View {
        DSCard(padding: DSSpacing.m) {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: "sparkles")
                    .foregroundStyle(DSColors.coinGold)
                Text("İlk yüklemene özel: aldığın coin 2 KAT!")
                    .font(DSTypography.bodyEmphasized)
                    .foregroundStyle(DSColors.textPrimary)
                Spacer()
            }
        }
        .padding(.top, DSSpacing.s)
    }

    // MARK: - İçerik durumları (06 §7.4)

    @ViewBuilder
    private var content: some View {
        switch model.loadPhase {
        case .loading:
            DSStateView(.loading(skeleton: .grid(columns: 2)))
        case .failed:
            DSStateView(.error(message: "Mağaza şu an yüklenemedi", retry: { Task { await model.retry() } }))
        case .loaded:
            packageGrid
        }
    }

    private var packageGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DSSpacing.m),
                GridItem(.flexible(), spacing: DSSpacing.m)
            ],
            spacing: DSSpacing.m
        ) {
            ForEach(model.items) { item in
                CoinPackCard(
                    item: item,
                    isPurchasing: model.purchasePhase.inFlightProductID == item.productId,
                    isDisabled: model.purchasePhase.preventsNewPurchase
                ) {
                    Task { await model.purchase(item) }
                }
            }
        }
    }

    // MARK: - Alt (restore + yasal, 06 §11.3/§11.4)

    private var footer: some View {
        VStack(spacing: DSSpacing.s) {
            DSButton("Satın Alımları Geri Yükle", style: .secondary, size: .compact) {
                Task { await model.restore() }
            }
            VStack(spacing: DSSpacing.xxs) {
                Text("Coin'ler yalnız uygulama içinde geçerlidir, iade edilmez.")
                Text("Geri yükleme aboneliğinizi tanır; coin bakiyeniz hesabınızda saklıdır.")
            }
            .font(DSTypography.caption)
            .foregroundStyle(DSColors.textTertiary)
            .multilineTextAlignment(.center)
        }
        .padding(.top, DSSpacing.m)
    }

    // MARK: - Geçici durum banner'ı (başarı/pending/hata, 06 §7.4)

    @ViewBuilder
    private var transientBanner: some View {
        if let banner = model.purchasePhase.banner {
            statusBanner(bannerText, tone: banner.tone, autoDismiss: banner.autoDismisses)
        }
    }

    private var bannerText: LocalizedStringKey {
        switch model.purchasePhase {
        case .success:
            "Coin'ler hesabına eklendi"
        case .verificationPending:
            "Ödemen alındı, coin'ler birazdan hesabında"
        case .pending:
            "Onay bekleniyor. Onaylanınca coin'ler eklenecek"
        case .failed:
            "Satın alma tamamlanamadı, tekrar dene"
        case .invalidReceipt:
            "Satın alma doğrulanamadı — Destek"
        case .idle, .purchasing:
            ""
        }
    }

    private func bannerColor(_ tone: StorePurchaseBanner.Tone) -> Color {
        switch tone {
        case .success: DSColors.success
        case .warning: DSColors.warning
        case .danger: DSColors.danger
        }
    }

    private func statusBanner(_ text: LocalizedStringKey, tone: StorePurchaseBanner.Tone, autoDismiss: Bool) -> some View {
        Text(text)
            .font(DSTypography.captionEmphasized)
            .foregroundStyle(DSColors.textPrimary)
            .padding(DSSpacing.m)
            .frame(maxWidth: .infinity)
            .background(bannerColor(tone).opacity(0.2), in: RoundedRectangle(cornerRadius: DSRadius.card))
            .padding(DSSpacing.l)
            .onTapGesture { model.acknowledgeTransientPhase() }
            // Terminal hata/destek (.failed/.invalidReceipt) KALICI — auto-dismiss YOK; kullanıcı
            // elle kapatır ki "tekrar dene"/destek bilgisi 3sn'de silinmesin (06 §4.6).
            .task {
                if autoDismiss {
                    await autoDismissBanner()
                }
            }
    }

    private func autoDismissBanner() async {
        try? await Task.sleep(for: .seconds(3))
        model.acknowledgeTransientPhase()
    }
}

/// Paket kartı (06 §7.1/§7.2/§7.3): toplam coin (büyük) + baz/bonus dökümü + displayPrice +
/// bonus rozeti + katalog rozeti. Fiyat StoreKit'ten; coin/bonus çekirdek CoinPackage'tan.
private struct CoinPackCard: View {
    let item: CoinShopItem
    let isPurchasing: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSCard(padding: DSSpacing.m) {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    HStack {
                        if let badge = item.bonusBadgeText {
                            Text(badge)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.coinGold)
                        }
                        Spacer()
                        if let catalog = item.catalogBadge {
                            Text(catalog)
                                .font(DSTypography.caption)
                                .foregroundStyle(DSColors.accent)
                        }
                    }
                    DSCoinLabel(amount: item.displayedTotalCoins, size: .large)
                    if item.showsFirstTopUpDoubling {
                        Text("\(item.standardTotalCoins)")
                            .font(DSTypography.caption)
                            .strikethrough()
                            .foregroundStyle(DSColors.textTertiary)
                    } else if item.package.bonusCoins > 0 {
                        Text("\(item.package.baseCoins) + \(item.package.bonusCoins) bonus")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.textSecondary)
                    }
                    priceRow
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled && !isPurchasing ? 0.5 : 1)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var priceRow: some View {
        if isPurchasing {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else {
            Text(verbatim: item.displayPrice)
                .font(DSTypography.bodyEmphasized)
                .foregroundStyle(DSColors.coinGold)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, DSSpacing.xs)
                .background(DSColors.coinGold.opacity(0.15), in: RoundedRectangle(cornerRadius: DSRadius.button))
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(item.displayedTotalCoins) coin"]
        if item.package.bonusPercent > 0 {
            parts.append("yüzde \(item.package.bonusPercent) bonus dahil")
        }
        parts.append(item.displayPrice)
        return parts.joined(separator: ", ")
    }
}

/// Kazanılmış coin alt metni için biçimli sayı (DSCoinLabel biçimleyicisiyle tutarlı).
private func earnedCoinsText(_ amount: Int) -> String {
    let clamped = max(0, amount)
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    return formatter.string(from: NSNumber(value: clamped)) ?? "\(clamped)"
}
