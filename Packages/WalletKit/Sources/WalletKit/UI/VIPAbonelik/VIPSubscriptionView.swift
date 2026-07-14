import AppFoundation
import DesignSystem
import SwiftUI

/// VIPAbonelik — SS-096. İnce SwiftUI katmanı; plan/intro/yönetim mantığı `VIPSubscriptionModel`
/// (+ `VIPPlanOption` saf türevleri) içindedir. Fiyat StoreKit `displayPrice`'tan; restore
/// butonu her zaman görünür (App Store Review). DS token/bileşenleri, ham renk yok.
public struct VIPSubscriptionView: View {
    @State private var model: VIPSubscriptionModel

    public init(model: VIPSubscriptionModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.l) {
                header
                if model.showsPaymentIssueBanner {
                    paymentIssueBanner
                }
                benefits
                switch model.mode {
                case .purchase:
                    purchaseSection
                case .management:
                    managementSection
                }
                footer
            }
            .padding(DSSpacing.l)
        }
        .background(DSColors.background)
        .overlay(alignment: .bottom) { transientBanner }
        .onAppear { model.onAppear() }
        .onDisappear { model.onDisappear() }
    }

    private var header: some View {
        HStack {
            Text("VIP")
                .font(DSTypography.display)
                .foregroundStyle(DSColors.textPrimary)
            Spacer()
            Button { model.dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.textTertiary)
            }
            .accessibilityLabel("Kapat")
        }
    }

    // MARK: - Ayrıcalıklar (06 §8.1)

    private var benefits: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            benefitRow(icon: "lock.open.fill", text: "Tüm bölümler açık")
            benefitRow(icon: "gift.fill", text: "Her gün bonus coin")
            benefitRow(icon: "hand.raised.slash.fill", text: "Reklamsız")
        }
    }

    private func benefitRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: DSSpacing.m) {
            Image(systemName: icon)
                .foregroundStyle(DSColors.coinGold)
            Text(text)
                .font(DSTypography.body)
                .foregroundStyle(DSColors.textPrimary)
        }
    }

    // MARK: - Satın alma modu (06 §8.1)

    @ViewBuilder
    private var purchaseSection: some View {
        switch model.loadPhase {
        case .loading:
            DSStateView(.loading(skeleton: .grid(columns: 1)))
        case .failed:
            DSStateView(.error(message: "Planlar yüklenemedi", retry: { Task { await model.retry() } }))
        case .loaded:
            VStack(spacing: DSSpacing.m) {
                ForEach(model.plans) { option in
                    planCard(option)
                }
                DSButton(ctaTitle, style: .coinCTA, isLoading: model.purchasePhase.isPurchasing) {
                    Task { await model.subscribe() }
                }
                .disabled(model.purchasePhase.preventsNewPurchase)
                renewalDisclosure
            }
        }
    }

    private func planCard(_ option: VIPPlanOption) -> some View {
        Button {
            model.select(option.plan)
        } label: {
            DSCard(padding: DSSpacing.m) {
                HStack(spacing: DSSpacing.m) {
                    Image(systemName: option.plan == model.selectedPlan ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(option.plan == model.selectedPlan ? DSColors.accent : DSColors.textTertiary)
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        Text(periodTitle(option.periodUnit))
                            .font(DSTypography.bodyEmphasized)
                            .foregroundStyle(DSColors.textPrimary)
                        Text(verbatim: VIPPlanCopy.priceSubtitle(for: option))
                            .font(DSTypography.caption)
                            .foregroundStyle(option.showsIntroOffer ? DSColors.coinGold : DSColors.textSecondary)
                    }
                    Spacer()
                    if option.isBestValue {
                        Text("EN AVANTAJLI")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.coinGold)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var ctaTitle: LocalizedStringKey {
        // Çok-dönemli intro dahil (ör. "ilk 3 ay X") — süre `VIPPlanCopy` üzerinden StoreKit'ten;
        // yalnız periodUnit kullanmak "ilk ay X" gibi yanıltıcı fiyat basında gösterirdi (06 §11.2).
        if let suffix = VIPPlanCopy.introCTASuffix(for: model.selectedOption) {
            return "VIP Başlat — \(suffix)"
        }
        return "VIP Ol"
    }

    // MARK: - Yönetim modu (06 §8.3)

    private var managementSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            DSCard {
                VStack(alignment: .leading, spacing: DSSpacing.s) {
                    if let plan = model.subscription.plan {
                        Text("Aktif plan: \(planName(plan))")
                            .font(DSTypography.bodyEmphasized)
                            .foregroundStyle(DSColors.textPrimary)
                    }
                    if let renewal = renewalText {
                        Text(renewal)
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.textSecondary)
                    }
                    if model.subscription.dailyBonusCoins > 0 {
                        Text("Günlük bonus: \(model.subscription.dailyBonusCoins) coin")
                            .font(DSTypography.caption)
                            .foregroundStyle(DSColors.textSecondary)
                    }
                }
            }
            DSButton("Aboneliği Yönet") {
                model.manageSubscription()
            }
        }
    }

    private var renewalText: LocalizedStringKey? {
        guard let expires = model.subscription.expiresAt else { return nil }
        let formatted = expires.formatted(date: .abbreviated, time: .omitted)
        if model.subscription.willAutoRenew {
            return "\(formatted) tarihinde yenilenecek"
        }
        return "\(formatted) tarihinde sona erecek"
    }

    // MARK: - Satın alma sonucu banner'ı (06 §4.6/§7.4 — CoinMagazasi ile simetrik)

    /// Ücretli akış geri bildirimi: `.failed` (tekrar dene), `.pending` (Ask-to-Buy onayı bekleniyor),
    /// `.verificationPending` (birazdan aktif), `.invalidReceipt` (destek). Yalnız iptal sessizdir
    /// (06 §7.5). Terminal hata/destek durumları KALICI (auto-dismiss yok).
    @ViewBuilder
    private var transientBanner: some View {
        if let banner = model.purchasePhase.banner {
            statusBanner(bannerText, tone: banner.tone, autoDismiss: banner.autoDismisses)
        }
    }

    private var bannerText: LocalizedStringKey {
        switch model.purchasePhase {
        case .success:
            "VIP aktif — tüm bölümler açık"
        case .verificationPending:
            "Ödemen alındı, aboneliğin birazdan aktif"
        case .pending:
            "Onay bekleniyor. Onaylanınca VIP aktifleşecek"
        case .failed:
            "İşlem tamamlanamadı, tekrar dene"
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

    // MARK: - Banner / alt

    private var paymentIssueBanner: some View {
        Text("Ödeme sorunu — ödeme yöntemini güncelle")
            .font(DSTypography.captionEmphasized)
            .foregroundStyle(DSColors.textPrimary)
            .padding(DSSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DSColors.warning.opacity(0.2), in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private var renewalDisclosure: some View {
        VStack(spacing: DSSpacing.xxs) {
            Text("Abonelik, mevcut dönem bitmeden en az 24 saat önce iptal edilmediği sürece otomatik yenilenir.")
            Text("Yönetim ve iptal App Store hesap ayarlarından yapılır.")
        }
        .font(DSTypography.caption)
        .foregroundStyle(DSColors.textTertiary)
        .multilineTextAlignment(.center)
    }

    private var footer: some View {
        VStack(spacing: DSSpacing.s) {
            DSButton("Satın Alımları Geri Yükle", style: .secondary, size: .compact) {
                Task { await model.restore() }
            }
            Text("Kullanım Koşulları · Gizlilik Politikası")
                .font(DSTypography.caption)
                .foregroundStyle(DSColors.textTertiary)
        }
        .padding(.top, DSSpacing.m)
    }

    // MARK: - Metin yardımcıları

    private func periodTitle(_ unit: PeriodUnit) -> LocalizedStringKey {
        switch unit {
        case .day: "Günlük"
        case .week: "Haftalık"
        case .month: "Aylık"
        case .year: "Yıllık"
        }
    }

    private func planName(_ plan: SubscriptionStatus.Plan) -> LocalizedStringKey {
        switch plan {
        case .weekly: "Haftalık"
        case .monthly: "Aylık"
        case .yearly: "Yıllık"
        case .unknown: "VIP"
        }
    }
}
