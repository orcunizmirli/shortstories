import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

// MARK: - DSProgressBar

@Suite("DSProgressBar")
@MainActor
struct DSProgressBarTests {
    @Test func ilerlemeSifirBirAraliginaKirpilir() {
        #expect(DSProgressBar(progress: -0.5).clampedProgress == 0)
        #expect(DSProgressBar(progress: 1.5).clampedProgress == 1)
    }

    @Test func gecerliIlerlemeDegismez() {
        #expect(DSProgressBar(progress: 0.62).clampedProgress == 0.62)
    }

    @Test func sonluOlmayanIlerlemeSifiraKirpilir() {
        // Regresyon: NaN clamp'ten sızıp accessibilityValue'daki
        // Int dönüşümünü çökertiyordu.
        #expect(DSProgressBar(progress: .nan).clampedProgress == 0)
        #expect(DSProgressBar(progress: .infinity).clampedProgress == 0)
        #expect(DSProgressBar(progress: -.infinity).clampedProgress == 0)
        _ = DSProgressBar(progress: .nan).body
    }

    @Test func kuruluyor() {
        for value in [0.0, 0.5, 1.0] {
            _ = DSProgressBar(progress: value).body
        }
    }
}

// MARK: - DSBadge

@Suite("DSBadge")
@MainActor
struct DSBadgeTests {
    @Test func tumVaryantlarKuruluyor() {
        let kinds: [DSBadge.Kind] = [.newEpisode, .vip, .locked, .topRank(3)]
        for kind in kinds {
            _ = DSBadge(kind).body
        }
    }

    @Test func erisilebilirlikMetinleriAnlamli() {
        #expect(DSBadge(.newEpisode).accessibilityText == "Yeni bölüm")
        #expect(DSBadge(.vip).accessibilityText == "VIP")
        #expect(DSBadge(.locked).accessibilityText == "Kilitli")
        #expect(DSBadge(.topRank(7)).accessibilityText.contains("7"))
    }

    @Test func topRankSirasiEnAzBirdir() {
        // Regresyon: doğrulanmamış rank "Top 0" / "Top -3" üretiyordu;
        // paketin sayısal clamp invariant'ı gereği rank = max(1, rank).
        #expect(DSBadge(.topRank(0)).accessibilityText == "Top 1")
        #expect(DSBadge(.topRank(-3)).accessibilityText == "Top 1")
        #expect(DSBadge(.topRank(7)).accessibilityText == "Top 7")
    }

    @Test func overlayVaryantOnPlaniThemeInvariant() {
        // Regresyon: topRank numarası theme-dynamic textPrimary kullanıyordu;
        // dosya sözleşmesi poster-overlay varyantlarını theme-invariant der.
        let base = UIColor(DSBadge.overlayVariantForeground)
        let dark = base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let light = base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(dark == light)
    }
}

// MARK: - DSSeriesCard

@Suite("DSSeriesCard")
@MainActor
struct DSSeriesCardTests {
    @Test func posterOraniIkiUctur() {
        let expected: CGFloat = 2.0 / 3.0
        #expect(DSSeriesCard.posterAspectRatio == expected)
    }

    @Test func tumVaryantlarKuruluyor() {
        let sizes: [DSSeriesCard.Size] = [.shelf, .grid]
        let badges: [DSBadge.Kind?] = [nil, .newEpisode, .vip, .locked, .topRank(1)]
        let progresses: [Double?] = [nil, 0.4]
        for size in sizes {
            for badge in badges {
                for progress in progresses {
                    let card = DSSeriesCard(title: "Kayıp Varis", size: size, badge: badge, progress: progress) {}
                    _ = card.body
                }
            }
        }
    }

    @Test func ilerlemeKirpilir() {
        #expect(DSSeriesCard(title: "T", progress: 1.7) {}.clampedProgress == 1)
        #expect(DSSeriesCard(title: "T", progress: -0.2) {}.clampedProgress == 0)
        #expect(DSSeriesCard(title: "T") {}.clampedProgress == nil)
    }

    @Test func sonluOlmayanIlerlemeSifiraKirpilir() {
        // Regresyon: NaN, accessibilityText'teki Int dönüşümünü çökertiyordu.
        let card = DSSeriesCard(title: "T", progress: .nan) {}
        #expect(card.clampedProgress == 0)
        #expect(card.accessibilityText.contains("%0"))
        #expect(DSSeriesCard(title: "T", progress: .infinity) {}.clampedProgress == 0)
    }

    @Test func genisPosterKartGenisliginiSisirmez() {
        // Regresyon: 16:9 poster .scaledToFill ile ZStack'i şişiriyor,
        // 110 pt önerilen karta ~293 pt genişlik raporlanıyordu (kart 2:3
        // kalmıyor, hit-area görünür sınırın dışına taşıyordu).
        let posterImage = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        let proposal = CGSize(width: DSSeriesCard.shelfWidth, height: 1000)
        for size in [DSSeriesCard.Size.shelf, .grid] {
            let card = DSSeriesCard(title: "T", size: size, poster: Image(uiImage: posterImage)) {}
            let fitting = UIHostingController(rootView: card).sizeThatFits(in: proposal)
            #expect(fitting.width <= DSSeriesCard.shelfWidth + 0.5, "size: \(size)")
        }
    }

    @Test func erisilebilirlikEtiketiBaslikRozetVeIlerlemeIcerir() {
        let card = DSSeriesCard(title: "Kayıp Varis", badge: .locked, progress: 0.62) {}
        #expect(card.accessibilityText.contains("Kayıp Varis"))
        #expect(card.accessibilityText.contains("Kilitli"))
        #expect(card.accessibilityText.contains("62"))
    }

    @Test func rozetVeIlerlemeYoksaEtiketYalnizBaslik() {
        let card = DSSeriesCard(title: "Kayıp Varis") {}
        #expect(card.accessibilityText == "Kayıp Varis")
    }

    @Test func altYaziKuruluyorVeErisilebilirlikEtiketindeYerAlir() {
        // 02 §4.10: Trend rafı "başlık + tür alt yazı" ister.
        let card = DSSeriesCard(title: "Kayıp Varis", subtitle: "Dram", badge: .newEpisode) {}
        _ = card.body
        #expect(card.accessibilityText.contains("Dram"))
        #expect(DSSeriesCard(title: "T") {}.accessibilityText == "T")
    }
}

// MARK: - DSSectionHeader

@Suite("DSSectionHeader")
@MainActor
struct DSSectionHeaderTests {
    @Test func aksiyonsuzKuruluyorVeTumunuGorGizli() {
        let header = DSSectionHeader("Trend")
        #expect(header.showsSeeAll == false)
        _ = header.body
    }

    @Test func aksiyonluTumunuGorGosterir() {
        let header = DSSectionHeader("Trend", onSeeAll: {})
        #expect(header.showsSeeAll)
        _ = header.body
    }
}

// MARK: - DSStateView

@Suite("DSStateView")
@MainActor
struct DSStateViewTests {
    @Test func tumDurumlarKuruluyor() {
        let kinds: [DSStateView.Kind] = [
            .loading,
            .loading(skeleton: .grid(columns: 3)),
            .empty(
                message: "Henüz favorin yok",
                systemImage: "heart",
                action: DSStateView.EmptyAction(title: "Keşfet'e Git", handler: {})
            ),
            .empty(message: "Boş", systemImage: "tray", action: nil),
            .error(message: "Bir şeyler ters gitti", retry: {}),
            .offline(retry: {})
        ]
        for kind in kinds {
            _ = DSStateView(kind).body
        }
    }

    @Test func durumIkonlariSozlesmeyeUygun() {
        #expect(DSStateView(.loading).iconName == nil)
        #expect(DSStateView(.empty(message: "m", systemImage: "heart", action: nil)).iconName == "heart")
        #expect(DSStateView(.error(message: "m", retry: {})).iconName == "exclamationmark.triangle")
        #expect(DSStateView(.offline(retry: {})).iconName == "wifi.slash")
    }

    @Test func hataVeOfflineRetryAksiyonuTasir() {
        var retried = false
        DSStateView(.error(message: "m", retry: { retried = true })).retryAction?()
        #expect(retried)

        retried = false
        DSStateView(.offline(retry: { retried = true })).retryAction?()
        #expect(retried)
    }

    @Test func loadingVeBosDurumRetrySunmaz() {
        #expect(DSStateView(.loading).retryAction == nil)
        #expect(DSStateView(.empty(message: "m", systemImage: "tray", action: nil)).retryAction == nil)
    }

    @Test func bosDurumCTAsiBaslikVeAksiyonuBirlikteTasir() {
        // Regresyon: eski (actionTitle, action) çiftinde yalnız biri verilirse
        // buton sessizce düşüyordu; EmptyAction geçersiz durumu temsil edilemez yapar.
        var tapped = false
        let view = DSStateView(
            .empty(
                message: "m",
                systemImage: "heart",
                action: DSStateView.EmptyAction(title: "Keşfet'e Git", handler: { tapped = true })
            )
        )
        view.emptyAction?.handler()
        #expect(tapped)
        #expect(DSStateView(.empty(message: "m", systemImage: "tray", action: nil)).emptyAction == nil)
        #expect(DSStateView(.loading).emptyAction == nil)
    }

    @Test func loadingSkeletonVaryantlari() {
        // 02 §3: raflar için shelf (varsayılan), kart ızgaraları için grid.
        #expect(DSStateView(.loading).loadingSkeleton == .shelf)
        #expect(DSStateView(.loading(skeleton: .grid(columns: 3))).loadingSkeleton == .grid(columns: 3))
        #expect(DSStateView(.offline(retry: {})).loadingSkeleton == nil)
        _ = DSStateView(.loading(skeleton: .grid(columns: 2))).body
    }
}

// MARK: - DSOfflineBanner

@Suite("DSOfflineBanner")
@MainActor
struct DSOfflineBannerTests {
    @Test func retryliVeRetrysizKuruluyor() {
        _ = DSOfflineBanner().body
        _ = DSOfflineBanner(onRetry: {}).body
    }

    @Test func retryAksiyonuYalnizVerildigindeSunulur() {
        #expect(DSOfflineBanner().showsRetry == false)
        #expect(DSOfflineBanner(onRetry: {}).showsRetry)
    }

    @Test func retryAksiyonuTasir() {
        var retried = false
        DSOfflineBanner(onRetry: { retried = true }).retryAction?()
        #expect(retried)
        #expect(DSOfflineBanner().retryAction == nil)
    }
}

// MARK: - DSCoinLabel

@Suite("DSCoinLabel")
@MainActor
struct DSCoinLabelTests {
    @Test func miktarBinlikAyraclaBicimlenir() {
        #expect(DSCoinLabel.formattedAmount(1250, locale: Locale(identifier: "en_US")) == "1,250")
        #expect(DSCoinLabel.formattedAmount(0, locale: Locale(identifier: "en_US")) == "0")
    }

    @Test func negatifMiktarSifiraKirpilir() {
        #expect(DSCoinLabel.formattedAmount(-70, locale: Locale(identifier: "en_US")) == "0")
    }

    @Test func kuruluyor() {
        for size in [DSCoinLabel.Size.regular, .large] {
            _ = DSCoinLabel(amount: 70, size: size).body
        }
    }
}

// MARK: - DSAvatar

@Suite("DSAvatar")
@MainActor
struct DSAvatarTests {
    @Test func basHarflerIlkIkiKelimeden() {
        #expect(DSAvatar.initials(from: "Ayşe Yılmaz") == "AY")
        #expect(DSAvatar.initials(from: "Zeynep") == "Z")
        #expect(DSAvatar.initials(from: "Ali Veli Kırk") == "AV")
    }

    @Test func kucukHarfBuyukHarfeCevrilir() {
        #expect(DSAvatar.initials(from: "ayşe yılmaz") == "AY")
    }

    @Test func bosIsimBosBasHarfDondurur() {
        #expect(DSAvatar.initials(from: "").isEmpty)
        #expect(DSAvatar.initials(from: "   ").isEmpty)
    }

    @Test func basHarflerLocaleDuyarliBuyutulur() {
        // Regresyon: uppercased() locale-bağımsızdı — 'işıl irmak' TR'de
        // 'İİ' yerine 'II' üretiyordu.
        #expect(DSAvatar.initials(from: "işıl irmak", locale: Locale(identifier: "tr_TR")) == "İİ")
        #expect(DSAvatar.initials(from: "işıl irmak", locale: Locale(identifier: "en_US")) == "II")
    }

    @Test func bosBasHarfliIsimdeErisilebilirlikJenerikEtiketeDuser() {
        // Regresyon: fallback name.isEmpty'ye bakıyordu — '   ' isimde
        // VoiceOver boşluk okuyordu; koşul initials-boş olmalı.
        #expect(DSAvatar(name: "   ").accessibilityLabelText == "Profil avatarı")
        #expect(DSAvatar(name: "").accessibilityLabelText == "Profil avatarı")
        #expect(DSAvatar(name: "Ayşe Yılmaz").accessibilityLabelText == "Ayşe Yılmaz")
    }

    @Test func kuruluyor() {
        _ = DSAvatar(name: "Ayşe Yılmaz").body
        _ = DSAvatar(name: "").body
    }
}

// MARK: - Renk yardımcısı (color-space bağımsız RGBA karşılaştırma)

@MainActor
private func rgba(_ color: Color, _ style: UIUserInterfaceStyle) -> [CGFloat] {
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    UIColor(color)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        .getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a]
}

// MARK: - DSButton (yıkıcı stil — review #14)

@Suite("DSButton")
@MainActor
struct DSButtonTests {
    @Test func destructiveStyleUsesDangerBackgroundAndWhiteForeground() {
        // Yıkıcı CTA'nın ham renkleri (danger zemin + beyaz metin) DS bileşeninde yaşar; feature
        // view'ı yalnız `.destructive` semantiğini seçer (03 §4.1).
        let button = DSButton("Sil", style: .destructive) {}
        #expect(rgba(button.background, .dark) == rgba(DSColors.danger, .dark))
        #expect(rgba(button.foreground, .dark) == [1, 1, 1, 1]) // beyaz
        _ = button.body
    }

    @Test func tumStillerKuruluyor() {
        for style in [DSButton.Style.primary, .secondary, .coinCTA, .destructive] {
            _ = DSButton("Etiket", style: style) {}.body
        }
    }
}

// MARK: - DSAppleSignInButton (Apple-imzalı buton — review #14)

@Suite("DSAppleSignInButton")
@MainActor
struct DSAppleSignInButtonTests {
    @Test func appleHIGWhiteBackgroundBlackForeground() {
        let button = DSAppleSignInButton("Apple ile Devam Et") {}
        // Apple-imzalı görünüm theme-invariant beyaz zemin + siyah ön plan (ham renk yalnız DS'te).
        #expect(rgba(button.background, .dark) == [1, 1, 1, 1]) // beyaz
        #expect(rgba(button.background, .light) == [1, 1, 1, 1])
        #expect(rgba(button.foreground, .dark) == [0, 0, 0, 1]) // siyah
    }

    @Test func kuruluyorVeYuklenmeDurumu() {
        _ = DSAppleSignInButton("Apple ile Devam Et") {}.body
        _ = DSAppleSignInButton("Apple ile Devam Et", isLoading: true) {}.body
    }
}

// MARK: - Token sanity genişletmesi

@Suite("Token sanity — E2 genişletme")
struct TokenSanityExtensionTests {
    @Test func surfaceTabBarDarkTemada85Opak() {
        let resolved = UIColor(DSColors.surfaceTabBar)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var alpha: CGFloat = -1
        #expect(resolved.getRed(nil, green: nil, blue: nil, alpha: &alpha))
        #expect(abs(alpha - 0.85) < 0.001)
    }

    @Test func metinHiyerarsisiAlfaIleAzalir() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        func alpha(of color: Color) -> CGFloat {
            var value: CGFloat = -1
            _ = UIColor(color).resolvedColor(with: dark).getRed(nil, green: nil, blue: nil, alpha: &value)
            return value
        }
        #expect(alpha(of: DSColors.textPrimary) > alpha(of: DSColors.textSecondary))
        #expect(alpha(of: DSColors.textSecondary) > alpha(of: DSColors.textTertiary))
    }
}
