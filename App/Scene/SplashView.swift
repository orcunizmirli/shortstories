import DesignSystem
import SwiftUI

/// SS-060 — Splash / açılış ekranı (03 §3.1). Logo + marka adı; arka planda `LaunchCoordinator` çekirdek
/// ön-yüklemeyi (misafir oturumu + ilk feed/video prefetch tetiği) sürdürürken görünür. Ön-yükleme +
/// minimum zemin dolunca koordinatör routing kararını verir (Onboarding | Tab'lar); bu görünüm yalnız
/// launch dizisini başlatır (`.task { beginLaunch() }`) — akış kararı koordinatördedir (ince view).
///
/// Kanon §2: dark-locked, portrait. Ham renk yok (DS token). Görsel olarak sistem launch screen'iyle
/// (portrait, OLED siyahı) süreklilik kurar — kullanıcı "iki ayrı ekran" hissetmez.
struct SplashView: View {
    let launch: LaunchCoordinator

    var body: some View {
        ZStack {
            DSColors.background.ignoresSafeArea()

            VStack(spacing: DSSpacing.l) {
                Image(systemName: "play.rectangle.fill")
                    .font(DSTypography.display)
                    .foregroundStyle(DSColors.accent)
                    .accessibilityHidden(true)

                Text(verbatim: "ShortSeries")
                    .font(DSTypography.headingL)
                    .foregroundStyle(DSColors.textPrimary)

                ProgressView()
                    .tint(DSColors.textTertiary)
                    .padding(.top, DSSpacing.s)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ShortSeries yükleniyor")
        .task { launch.beginLaunch() }
    }
}
