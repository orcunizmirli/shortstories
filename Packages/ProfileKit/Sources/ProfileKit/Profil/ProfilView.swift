import AppFoundation
import DesignSystem
import Foundation
import SwiftUI

/// `Profil` ekranı (SS-130) — ince SwiftUI katmanı: tüm karar `ProfilModel` + `AccountSummary`
/// saf türetiminde. Dark-first, DS token/bileşen; ham renk yok. Misafirde "Hesabını bağla" CTA;
/// bağlıda avatar + sağlayıcı. Cüzdan/VIP/geçmiş/Ayarlar/destek satırları delegate niyeti üretir.
public struct ProfilView: View {
    @State private var model: ProfilModel

    public init(model: ProfilModel) {
        _model = State(wrappedValue: model)
    }

    public var body: some View {
        Group {
            switch model.loadState {
            case .loading:
                DSStateView(.loading(skeleton: .shelf))
            case .loaded:
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DSColors.background)
        .onAppear { model.onAppear() }
        .task { await model.observeUpdates() }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: DSSpacing.l) {
                accountCard
                walletRow
                vipRow
                watchHistoryRow
                if model.notificationCenterEnabled {
                    navigationRow(title: "Bildirimler", systemImage: "bell.fill") { model.openNotificationCenter() }
                }
                navigationRow(title: "Ayarlar", systemImage: "gearshape.fill") { model.openSettings() }
                navigationRow(title: "Yardım & Destek", systemImage: "questionmark.circle.fill") {
                    model.openSupport()
                }
                versionFooter
            }
            .padding(DSSpacing.l)
        }
    }

    // MARK: - Hesap kartı

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.m) {
            HStack(spacing: DSSpacing.m) {
                DSAvatar(name: accountName, diameter: 52)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(verbatim: accountName)
                        .font(DSTypography.headingM)
                        .foregroundStyle(DSColors.textPrimary)
                    Text(accountSubtitle)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                }
                Spacer(minLength: DSSpacing.s)
            }
            if !model.account.isLinked {
                DSButton(linkCTATitle, size: .compact) { model.linkOrReauthenticate() }
            }
        }
        .padding(DSSpacing.l)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    // TODO: [F2] Bağlı hesapta gerçek avatar + ad + e-posta göster — bir profil-çekim portu
    // (ProfileFetching, R8) eklenip App canlı hesaba bağlanacak; şimdilik sağlayıcı adı gösterilir.
    private var accountName: String {
        switch model.account.kind {
        case .guest: "Misafir"
        case .linked, .sessionExpired: providerName
        }
    }

    private var providerName: String {
        model.account.provider?.profileDisplayName ?? "Hesap"
    }

    private var accountSubtitle: LocalizedStringKey {
        switch model.account.kind {
        case .guest: "Hesabını bağla, ilerlemen güvende olsun"
        case .linked: "\(providerName) ile bağlı"
        case .sessionExpired: "Oturumun düştü — yeniden giriş yap"
        }
    }

    private var linkCTATitle: LocalizedStringKey {
        model.account.isGuest ? "Hesabını Bağla" : "Yeniden Giriş Yap"
    }

    // MARK: - Cüzdan + VIP

    private var walletRow: some View {
        HStack(spacing: DSSpacing.m) {
            DSCoinLabel(amount: model.wallet.coinBalance, size: .large)
            Spacer(minLength: DSSpacing.s)
            DSButton("Coin Al", style: .coinCTA, size: .compact) { model.openCoinStore() }
        }
        .padding(DSSpacing.l)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
    }

    private var vipRow: some View {
        Button { model.openVIP() } label: {
            HStack(spacing: DSSpacing.m) {
                DSBadge(.vip)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(model.wallet.isVIP ? "VIP Üyeliğin" : "VIP'e Geç")
                        .font(DSTypography.bodyEmphasized)
                        .foregroundStyle(DSColors.textPrimary)
                    Text(vipSubtitle)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: DSSpacing.s)
                chevron
            }
            .padding(DSSpacing.l)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
        }
        .buttonStyle(.plain)
    }

    private var vipSubtitle: String {
        guard model.wallet.isVIP else {
            return "Tüm bölümler açık + günlük bonus coin + reklamsız"
        }
        if let date = model.wallet.vipRenewalDate {
            return "Yenileme: \(VIPRenewalDate.text(date, appLanguage: model.appLanguage))"
        }
        return "Aktif"
    }

    private var watchHistoryRow: some View {
        navigationRow(title: "İzleme Geçmişi", systemImage: "clock.arrow.circlepath") {
            model.openWatchHistory()
        }
    }

    // MARK: - Ortak satır

    private func navigationRow(
        title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.m) {
                Image(systemName: systemImage)
                    .font(DSTypography.headingM)
                    .foregroundStyle(DSColors.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.textPrimary)
                Spacer(minLength: DSSpacing.s)
                chevron
            }
            .padding(DSSpacing.l)
            .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSRadius.card))
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(DSTypography.caption)
            .foregroundStyle(DSColors.textTertiary)
            .accessibilityHidden(true)
    }

    private var versionFooter: some View {
        Text(verbatim: model.appVersion.isEmpty ? "" : "Sürüm \(model.appVersion)")
            .font(DSTypography.caption)
            .foregroundStyle(DSColors.textTertiary)
            .padding(.top, DSSpacing.s)
    }
}
