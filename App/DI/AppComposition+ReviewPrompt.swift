import AppFoundation
import StoreKit
import UIKit

// RTG-01 App Store puanlama istemi (00-genel-bakis.md §294): live `ReviewRequesting` impl'i +
// composition erişimi. Karar mantığı AppFoundation `ReviewPromptController`/`ReviewPromptPolicy`'de
// (saf/test-edilebilir); burada yalnız sistem çağrısı ve wiring.

/// `AppStore.requestReview(in:)` (iOS 16+) sarmalayıcısı. Aktif foreground `UIWindowScene` gerektirir;
/// yoksa sessizce atlar (Apple istemin gösterilip gösterilmeyeceğine zaten kendi karar verir).
struct StoreKitReviewRequester: ReviewRequesting {
    @MainActor
    func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            return
        }
        AppStore.requestReview(in: scene)
    }
}

extension AppComposition {
    /// Remote kill-switch (RTG-01 kabul kriteri): KAPALIysa istem hiç değerlendirilmez. Varsayılan AÇIK;
    /// remote config `false` yazarak tamamen kapatabilir (freeze-per-launch; 03 §11).
    private static let reviewPromptEnabledFlag = FlagKey(name: "retention.review_prompt_enabled", default: true)

    /// Puanlama istemi koordinatörü. Durum (pozitif-an sayacı + son-istem damgası) `PreferencesStoring`'de
    /// KALICI olduğundan, her erişimde taze bir controller güvenlidir (sayaç/guard prefs'ten okunur/yazılır).
    var reviewPromptController: ReviewPromptController {
        ReviewPromptController(
            requester: StoreKitReviewRequester(),
            preferences: dependencies.preferences,
            currentAppVersion: Self.appVersion
        )
    }

    /// TÜM pozitif-an tetik sitelerinin geçtiği tek giriş: remote kill-switch AÇIKsa controller'a iletir.
    /// (Frekans/eşik/sürüm terbiyesi controller/policy'de; burada kill-switch kapısı + "istek" analitiği.)
    /// Sistem istemi GERÇEKTEN talep edildiyse `review_prompt_requested` yazılır (RTG-01 kriter 5; Apple
    /// diyaloğu gösterip göstermediğini garanti etmez → event yalnız TALEBİ kaydeder).
    func requestReviewIfEnabled(_ trigger: ReviewPromptTrigger) {
        guard dependencies.featureFlags.value(for: Self.reviewPromptEnabledFlag) else {
            return
        }
        guard reviewPromptController.recordPositiveMoment(trigger) else {
            return
        }
        decoratedAnalytics.track(
            "review_prompt_requested",
            parameters: ["trigger": .string(Self.analyticsName(for: trigger))]
        )
    }

    private static func analyticsName(for trigger: ReviewPromptTrigger) -> String {
        switch trigger {
        case .episodeCompleted: "episode_completed"
        case .streakDay: "streak_day"
        }
    }
}
