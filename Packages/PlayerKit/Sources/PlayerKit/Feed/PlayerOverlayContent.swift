import DesignSystem
import SwiftUI

/// Hücre üstü overlay içeriği (02 §4.3.2 katmanları; PlayerKit-internal).
///
/// F1 sade dilim: üst bilgi bölgesi, sağ aksiyon rayı (kapalı liste — 04 §8.4:
/// Favori/Paylaş/Bölümler/Hız/Altyazı, yalnız İSKELET intent'leri) ve alt bilgi +
/// ilerleme çubuğu ALANLARI. Otomatik gizlenme, scrub etkileşimi, sayaçlar ve
/// canlı ilerleme SS-045'in sonraki dilimindedir. Jest katmanı UIKit'te kalır
/// (04 §8); buradaki butonlar delegate intent'lerine akar.
struct PlayerOverlayContent: View {
    /// Ray/alan aksiyonları: hücre → feed VC → `PlayerFeedDelegate` (Coordinator).
    struct Actions {
        var seriesDetail: () -> Void = {}
        var favorite: () -> Void = {}
        var share: () -> Void = {}
        var episodeList: () -> Void = {}
        var speed: () -> Void = {}
        var subtitles: () -> Void = {}
        var unlock: () -> Void = {}
    }

    /// Kilitli kart durumu (02 §4.3.5): bulanık poster + kilit rozeti + fiyat.
    struct LockState {
        let priceLabel: String?
    }

    let seriesTitle: String
    let episodeLabel: String
    let initialProgress: Double
    let lockState: LockState?
    let actions: Actions

    var body: some View {
        ZStack {
            gradientMasks
            VStack(spacing: 0) {
                topInfoArea
                Spacer()
                HStack(alignment: .bottom, spacing: DSSpacing.m) {
                    bottomInfoArea
                    rightRail
                }
            }
            .padding(DSSpacing.l)
            if let lockState {
                lockOverlay(lockState)
            }
        }
    }

    // MARK: - Katman 1: gradyan maskeleri (hit-test kapalı)

    private var gradientMasks: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [DSColors.overlayScrim, .clear], startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity)
                .opacity(0.6)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, DSColors.overlayScrim], startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: .infinity)
                .opacity(0.6)
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - Katman 2: üst bilgi bölgesi

    private var topInfoArea: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Button(action: actions.seriesDetail) {
                    Text(seriesTitle)
                        .font(DSTypography.playerOverlay(size: 17, weight: .bold))
                        .foregroundStyle(DSColors.overlayForeground)
                        .lineLimit(1)
                }
                Text(episodeLabel)
                    .font(DSTypography.playerOverlay(size: 13, weight: .medium))
                    .foregroundStyle(DSColors.overlayForeground.opacity(0.8))
            }
            Spacer()
        }
        .padding(.top, DSSpacing.xl)
    }

    // MARK: - Katman 3: sağ aksiyon rayı (kapalı liste — 04 §8.4)

    private var rightRail: some View {
        VStack(spacing: DSSpacing.m) {
            railButton("heart", label: "Favori", action: actions.favorite)
            railButton("arrowshape.turn.up.right", label: "Paylaş", action: actions.share)
            railButton("list.bullet", label: "Bölümler", action: actions.episodeList)
            railButton("gauge.with.needle", label: "Hız", action: actions.speed)
            railButton("captions.bubble", label: "Altyazı", action: actions.subtitles)
        }
    }

    private func railButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: DSSpacing.xxs) {
                Image(systemName: systemImage)
                    .font(DSTypography.playerOverlay(size: 22, weight: .semibold))
                Text(label)
                    .font(DSTypography.playerOverlay(size: 10, weight: .medium))
            }
            .foregroundStyle(DSColors.overlayForeground)
            .frame(width: 44, height: 44) // 02 §4.3.2: 44×44 pt hit alanı
        }
        .accessibilityLabel(label)
    }

    // MARK: - Katman 4: alt bilgi bölgesi

    private var bottomInfoArea: some View {
        VStack(alignment: .leading, spacing: DSSpacing.s) {
            Text(seriesTitle)
                .font(DSTypography.playerOverlay(size: 14, weight: .semibold))
                .foregroundStyle(DSColors.overlayForeground)
                .lineLimit(1)
            Text(episodeLabel)
                .font(DSTypography.playerOverlay(size: 12, weight: .medium))
                .foregroundStyle(DSColors.overlayForeground.opacity(0.8))
            // Scrub etkileşimi SS-045'in sonraki dilimi; görsel temel DSProgressBar (02 §4.3.2).
            DSProgressBar(progress: initialProgress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Kilitli kart (02 §4.3.5)

    private func lockOverlay(_ state: LockState) -> some View {
        ZStack {
            DSColors.overlayScrim.ignoresSafeArea()
            VStack(spacing: DSSpacing.m) {
                Image(systemName: "lock.fill")
                    .font(DSTypography.playerOverlay(size: 40, weight: .bold))
                    .foregroundStyle(DSColors.overlayForeground)
                if let priceLabel = state.priceLabel {
                    Text(priceLabel)
                        .font(DSTypography.playerOverlay(size: 15, weight: .semibold))
                        .foregroundStyle(DSColors.overlayForeground)
                }
                Button(action: actions.unlock) {
                    Text("Kilidi Aç")
                        .font(DSTypography.playerOverlay(size: 15, weight: .bold))
                        .foregroundStyle(DSColors.overlayForeground)
                        .padding(.horizontal, DSSpacing.xl)
                        .padding(.vertical, DSSpacing.s)
                        .background(DSColors.accent, in: Capsule())
                }
                .accessibilityLabel("Kilidi Aç")
            }
        }
    }
}
