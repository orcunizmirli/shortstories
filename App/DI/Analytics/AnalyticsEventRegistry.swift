/// Analitik event kayıt defteri (08-analitik-deney.md §2.1/§2.3 TEK DOĞRULUK KAYNAĞININ istemci
/// yansıması). Registry'de OLMAYAN bir event gönderilemez (§2.3): `AppAnalyticsTracker` her `track`
/// çağrısını buradan doğrular. Kayıt kompozisyon kökündedir çünkü event adları feature modüllerine
/// dağılmış olsa da (her feature kendi `analytics.track("...")` çağrısını yapar) tek doğrulama
/// noktası App'tir — R6 gereği Firebase/gerçek sink App kompozisyonunda hapsolur.
///
/// Doğrulama non-destructive'dir: bilinmeyen event üretimde DÜŞÜRÜLMEZ (analitik kaybı, gerçek
/// kullanıcı verisi, geri alınamaz), yalnız `fault` seviyesinde loglanır. Registry-drift LOKAL/DEBUG'da
/// yakalanır — `AppAnalyticsTracker` strictInDebug `assertionFailure` yolu ve App target testleri
/// (`AnalyticsRegistryGuardTests`); ANCAK bu App target CI matrisinde DEĞİL (pr.yml yalnız paket
/// testlerini koşar), dolayısıyla guard CI paket testlerinde koşmaz. Ayrıca ad biçimi (`snake_case`,
/// boş değil) kontrol edilir.
enum AnalyticsEventRegistry {
    /// 08 §3 kanonik event kataloğu — feature modüllerinin GERÇEKTEN emit ettiği adların birleşimi
    /// (kaynak taraması ile senkron) + ileri fazların bildirdiği stabil adlar. Yeni bir event eklenirken
    /// önce buraya kaydedilir (§2.3 "önce registry").
    static let known: Set<String> = [
        // Ortak
        "screen_view",
        "app_open",
        "deeplink_opened",
        "deeplink_fallback",

        // Player / feed (04, 08 §3.2)
        "video_start",
        "video_stall",
        "feed_impression",
        "swipe_next",
        "swipe_prev",

        // Keşfet / arama / detay (08 §3.1/§3.3)
        "discover_refreshed",
        "discover_shelf_see_all",
        "discover_banner_tapped",
        "discover_card_tapped",
        "genre_filter_selected",
        "tag_tapped",
        "search_open",
        "search_query",
        "search_no_result",
        "search_result_tap",
        "series_detail_view",
        "series_cta_tapped",
        "episode_grid_tapped",
        "share_tap",

        // Listem (08 §3.3)
        "mylist_segment_changed",
        "mylist_item_removed",
        "favorite_add",
        "favorite_remove",
        "favorite_opened",
        "continue_watching_tapped",

        // Monetizasyon / cüzdan (06, 08 §3.4)
        "unlock_coin",
        // SS-114 rewarded ad ile açma (08 §3.4 satır 198): WalletKit `UnlockSheetModel` emit eder;
        // reklam mekaniği event'leri (rewarded_ad_*) RewardsKit sahiplidir (§3.5).
        "unlock_ad",
        "unlock_sheet_dismissed",
        "unlock_insufficient_coins",
        "unlock_vip_upsell",
        "unlock_failed",
        "episode_unlock_prompt",
        "auto_unlock_toggled",
        "coin_store_view",
        "coin_purchase_start",
        "coin_purchase_success",
        "coin_purchase_cancel",
        "coin_purchase_fail",
        "subscription_view",
        "subscription_start",
        "subscription_success",
        "subscription_cancel_intent",
        "subscription_fail",
        "restore_tapped",
        "iap_credited",
        "iap_subscription_updated",
        "iap_product_missing",
        "iap_receipt_invalid",
        "iap_family_shared_rejected",
        "entitlement_mismatch",

        // Ödüller / retention (07, 08 §3.5)
        "checkin_view",
        "checkin_claim",
        "checkin_streak_break",
        "mission_view",
        "mission_progress",
        "mission_complete",
        "mission_claim",
        // SS-113/114 rewarded ad mekaniği (08 §3.5 reklam bloğu): RewardsKit `RewardedAdService` emit eder
        // (params: placement, ads_used_today, daily_cap). `unlock_ad` (WalletKit) satır seçimini, bunlar
        // reklam yaşam döngüsünü ölçer. Registry'de OLMAZSA strictInDebug ilk 'Reklam izle'de assertionFailure.
        "rewarded_ad_start",
        "rewarded_ad_complete",
        "rewarded_ad_fail",

        // Profil / ayarlar / hesap (08 §3.6)
        "profile_row_tapped",
        "settings_changed",
        // Push atıf (08 §3.6): `push_open` istemci-tarafı (AppFoundation/App emit eder); `push_received`
        // İSTEMCİDEN GÖNDERİLMEZ — teslimat backend'de APNs yanıtından loglanır (08 §3.6 Not).
        "push_open",
        "push_disabled",
        "link_account_started",
        "link_account_success",
        "link_account_failed",
        "account_delete_started",
        "account_delete_completed",
        // BildirimMerkezi (08 §3.6 — ProfileKit `NotificationCenterModel` emit eder; SS-144/NTF-04).
        // Model bunları emit ettiğinden registry'de OLMALARI ŞART: aksi halde strictInDebug her açılışta
        // `assertionFailure` tetikler. `notification_center_opened {unread_count}` (ilk yükleme çözülünce
        // bir kez), `notification_item_tapped {type, route}` (satır dokunuşu).
        "notification_center_opened",
        "notification_item_tapped",

        // Onboarding (08 §3.1 — SS-064 ShortSeriesApp emit eder; kanonik katalog birebir)
        "onboarding_start",
        "onboarding_step_view",
        "onboarding_language_select",
        "onboarding_genre_select",
        "onboarding_push_prompt",
        "onboarding_att_prompt",
        "onboarding_complete",
        "onboarding_skip"
    ]

    /// Event adı `snake_case` kalıbına uyuyor mu (§2.1): küçük harf/rakam/alt-çizgi, harfle başlar,
    /// boş/uç alt-çizgi yok.
    static func isWellFormed(_ name: String) -> Bool {
        guard let first = name.first, first.isLowercaseASCIILetter else { return false }
        guard !name.hasSuffix("_") else { return false }
        return name.allSatisfy { $0.isLowercaseASCIILetter || $0.isASCIIDigit || $0 == "_" }
    }

    /// Doğrulama sonucu — çağıran (tracker) buna göre loglar.
    enum Validation: Equatable {
        case valid
        /// Ad biçimi bozuk (§2.1 ihlali).
        case malformed
        /// Biçim doğru ama registry'de yok (§2.3 ihlali — kayıtsız event).
        case unregistered
    }

    static func validate(_ name: String) -> Validation {
        guard isWellFormed(name) else { return .malformed }
        return known.contains(name) ? .valid : .unregistered
    }
}

private extension Character {
    var isLowercaseASCIILetter: Bool {
        ("a" ... "z").contains(self)
    }

    var isASCIIDigit: Bool {
        ("0" ... "9").contains(self)
    }
}
