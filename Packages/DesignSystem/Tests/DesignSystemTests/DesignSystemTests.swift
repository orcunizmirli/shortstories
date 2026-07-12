import SwiftUI
import Testing
import UIKit
@testable import DesignSystem

@Suite("Token sanity")
struct TokenSanityTests {
    @Test func spacingOlcegiKesinArtan() {
        let scale: [CGFloat] = [
            DSSpacing.xxs, DSSpacing.xs, DSSpacing.s, DSSpacing.m,
            DSSpacing.l, DSSpacing.xl, DSSpacing.xxl, DSSpacing.xxxl
        ]
        for (smaller, larger) in zip(scale, scale.dropFirst()) {
            #expect(smaller < larger)
        }
    }

    @Test func spacingDegerleri4ptIzgarada() {
        #expect(DSSpacing.xxs == 2)
        #expect(DSSpacing.xs == 4)
        #expect(DSSpacing.s == 8)
        #expect(DSSpacing.m == 12)
        #expect(DSSpacing.l == 16)
        #expect(DSSpacing.xl == 24)
        #expect(DSSpacing.xxl == 32)
        #expect(DSSpacing.xxxl == 48)
    }

    @Test func radiusDegerleri() {
        #expect(DSRadius.chip == .infinity)
        #expect(DSRadius.card == 12)
        #expect(DSRadius.sheet == 16)
        #expect(DSRadius.button == 10)
        #expect(DSStroke.hairline > 0 && DSStroke.hairline < 1)
    }

    @Test func backgroundDarkTemadaOLEDSiyahi() {
        let resolved = UIColor(DSColors.background)
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        var r: CGFloat = -1, g: CGFloat = -1, b: CGFloat = -1, a: CGFloat = -1
        #expect(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r == 0 && g == 0 && b == 0 && a == 1)
    }

    @Test func overlayScrimThemeInvariant() {
        let base = UIColor(DSColors.overlayScrim)
        let dark = base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
        let light = base.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        #expect(dark == light)
    }

    @Test func semanticRenklerCozumleniyor() {
        let tokens: [Color] = [
            DSColors.background, DSColors.surface, DSColors.surfaceElevated,
            DSColors.surfaceTabBar, DSColors.textPrimary, DSColors.textSecondary,
            DSColors.textTertiary, DSColors.accent, DSColors.coinGold,
            DSColors.success, DSColors.warning, DSColors.danger,
            DSColors.overlayScrim, DSColors.borderSubtle
        ]
        for token in tokens {
            var alpha: CGFloat = -1
            #expect(UIColor(token).getRed(nil, green: nil, blue: nil, alpha: &alpha))
            #expect(alpha > 0)
        }
    }
}

@Suite("Bileşen kurulum smoke")
@MainActor
struct ComponentSmokeTests {
    @Test func dsButtonTumStilVeDurumlarKuruluyor() {
        let styles: [DSButton.Style] = [.primary, .secondary, .coinCTA]
        let sizes: [DSButton.Size] = [.regular, .compact]
        for style in styles {
            for size in sizes {
                for isLoading in [false, true] {
                    let button = DSButton("Test", style: style, size: size, isLoading: isLoading) {}
                    _ = button.body
                }
            }
        }
    }

    @Test func dsPrimaryButtonStyleKuruluyor() {
        // ModifiedContent.body Never'dır; kurulum UIHostingController ile doğrulanır.
        let host = UIHostingController(rootView: Button("Test") {}.buttonStyle(.dsPrimary))
        #expect(host.view != nil)
    }

    @Test func dsChipSeciliVeSecisizKuruluyor() {
        for isSelected in [false, true] {
            let chip = DSChip("Dram", isSelected: isSelected) {}
            _ = chip.body
        }
    }

    @Test func dsCardIcerikleKuruluyor() {
        let card = DSCard(padding: DSSpacing.m) {
            Text("İçerik")
        }
        _ = card.body
    }

    @Test func katalogKuruluyor() {
        let catalog = DSCatalogView()
        _ = catalog.body
    }
}
