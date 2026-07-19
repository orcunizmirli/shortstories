import DesignSystem
import SwiftUI

/// VIP win-back dönüş banner'ı (SS-099 F2 — 06 §8.2/§8.4, 07 §7). Eski/lapsed VIP'e "geri dön"
/// çağrısı ya da auto-renew kapalı VIP'e "aboneliğin {tarih}te sona erecek" bilgisi. Mesaj tek
/// KAYNAKtır: `WinBackSurface` App-enjekte varyant/tarih/fiyattan türetir, View verbatim çizer.
/// CTA mevcut VIP satın-alma akışına bağlanır (`onCTA`). DS token/bileşenleri, ham renk yok.
struct WinBackBannerView: View {
    let surface: WinBackSurface
    let isPurchasing: Bool
    let isDisabled: Bool
    /// Compliance-gated offer fiyatı (model `winBackBannerOfferPrice`): YALNIZ §11.4 açıklaması TAM
    /// iken dolu → fiyatlı CTA + bitişik açıklama; `nil` → nötr "geri dön".
    let offerDisplayPrice: String?
    /// Fiyatlı CTA'nın §11.4 açıklaması (model `winBackRenewalDisclosure`) — CTA'ya BİTİŞİK, HER modda.
    let renewalDisclosure: WinBackRenewalDisclosure?
    let onCTA: () -> Void
    let onAppear: () -> Void

    var body: some View {
        DSCard(padding: DSSpacing.m) {
            VStack(alignment: .leading, spacing: DSSpacing.s) {
                HStack(spacing: DSSpacing.s) {
                    DSBadge(.vip)
                    Text("Sana özel")
                        .font(DSTypography.captionEmphasized)
                        .foregroundStyle(DSColors.coinGold)
                }
                if let message = surface.message {
                    Text(verbatim: message)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DSButton(ctaTitle, style: .coinCTA, size: .compact, isLoading: isPurchasing) {
                    onCTA()
                }
                .disabled(isDisabled)
                if let disclosure = renewalDisclosure {
                    // Fiyatlı satın-alma CTA'sına BİTİŞİK §11.4 açıklaması (App Store 3.1.2) — HER modda.
                    Text(verbatim: disclosure.priceSummary)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    RenewalDisclosureText()
                }
            }
        }
        .onAppear(perform: onAppear)
    }

    /// CTA metni: compliance-gated fiyat varsa fiyatlı "Geri dön: {fiyat}", aksi halde nötr dönüş
    /// çağrısı. Fiyat StoreKit'ten (`offerDisplayPrice`); hardcode yok.
    private var ctaTitle: LocalizedStringKey {
        if let price = offerDisplayPrice {
            return "Geri dön: \(price)"
        }
        return "VIP'e geri dön"
    }
}

/// Otomatik-yenileme statik açıklaması (06 §11.4) — plan satın-alma bölümü VE fiyatlı win-back
/// banner'ı ORTAK kullanır (tek kaynak). DS token; ham renk yok.
struct RenewalDisclosureText: View {
    var body: some View {
        VStack(spacing: DSSpacing.xxs) {
            Text("Abonelik, mevcut dönem bitmeden en az 24 saat önce iptal edilmediği sürece otomatik yenilenir.")
            Text("Yönetim ve iptal App Store hesap ayarlarından yapılır.")
        }
        .font(DSTypography.caption)
        .foregroundStyle(DSColors.textTertiary)
        .multilineTextAlignment(.center)
    }
}
