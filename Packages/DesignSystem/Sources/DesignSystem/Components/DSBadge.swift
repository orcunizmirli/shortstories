import SwiftUI

/// Rozet: yeni bölüm, VIP, kilit ve Top-10 sıra numarası varyantları
/// (02 §4.10 rafları, §4.3.5 kilitli kart, SS-013). Poster üstüne bindiği
/// için kilit varyantı theme-invariant `overlayScrim` zemini kullanır.
public struct DSBadge: View {
    public enum Kind: Equatable, Sendable {
        /// Yeni bölüm çıktı vurgusu.
        case newEpisode
        /// VIP içerik/ayrıcalık vurgusu.
        case vip
        /// Kilitli bölüm.
        case locked
        /// Top-10 rafı sıra numarası (numara posterin soluna taşar;
        /// yerleşim raf bileşeninin işidir, rozet yalnız numarayı çizer).
        case topRank(Int)
    }

    private let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    /// VoiceOver etiketi (test kancası).
    var accessibilityText: String {
        switch kind {
        case .newEpisode: "Yeni bölüm"
        case .vip: "VIP"
        case .locked: "Kilitli"
        case let .topRank(rank): "Top \(Self.clampedRank(rank))"
        }
    }

    /// Top-10 sırası en az 1'dir — paketin sayısal clamp invariant'ı
    /// (bkz. DSProgressBar/DSCoinLabel kırpmaları).
    private static func clampedRank(_ rank: Int) -> Int {
        max(1, rank)
    }

    /// Poster-overlay varyantlarının (locked, topRank) ön planı —
    /// theme-invariant overlay sınıfı (test kancası).
    static let overlayVariantForeground = DSColors.overlayForeground

    public var body: some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    /// Bileşen-içi renk türetimleri (accent/gold zemin üstü kontrast metin)
    /// 03 §4.1 katman 3 gereği yalnız bu dosyada yaşar.
    @ViewBuilder
    private var content: some View {
        switch kind {
        case .newEpisode:
            pill("Yeni", background: DSColors.accent, foreground: .white)
        case .vip:
            pill("VIP", background: DSColors.coinGold, foreground: .black)
        case .locked:
            Image(systemName: "lock.fill")
                .font(DSTypography.captionEmphasized)
                .foregroundStyle(Self.overlayVariantForeground) // overlay sınıfı: poster üstü her temada beyaz
                .padding(DSSpacing.s)
                .background(DSColors.overlayScrim, in: Circle())
        case let .topRank(rank):
            Text(verbatim: "\(Self.clampedRank(rank))")
                .font(DSTypography.display)
                .foregroundStyle(Self.overlayVariantForeground)
        }
    }

    private func pill(_ text: LocalizedStringKey, background: Color, foreground: Color) -> some View {
        Text(text)
            .font(DSTypography.captionEmphasized)
            .foregroundStyle(foreground)
            .padding(.horizontal, DSSpacing.s)
            .padding(.vertical, DSSpacing.xxs)
            .background(background, in: Capsule())
    }
}
