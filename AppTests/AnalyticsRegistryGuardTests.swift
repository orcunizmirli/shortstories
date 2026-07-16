import AppFoundation
import Foundation
import XCTest
@testable import ShortSeriesApp

/// REGISTRY ⊇ EMIT guard'ı (08 §2.3): feature paketlerinin GERÇEKTEN emit ettiği her event adı
/// `AnalyticsEventRegistry.known` içinde olmalı. Kayıtsız bir ad `AppAnalyticsTracker`'da DEBUG'da
/// `assertionFailure` tetikler (debug crash) — bu bulgu bir test-boşluğuydu. `emittedEventNames`
/// `grep -r 'analytics.track(' Packages/*/Sources` taramasının kar-donmuş halidir; yeni bir feature
/// event'i eklenip registry'e yazılmazsa bu test kırmızıya döner (drift'i CI/lokal yakalar).
final class AnalyticsRegistryGuardTests: XCTestCase {
    /// Feature paketlerinin emit ettiği event adları (kaynak taraması; registry bu kümeyi KAPSAMALI).
    static let emittedEventNames: [String] = [
        // Ortak / yaşam döngüsü
        "screen_view", "deeplink_fallback",
        // Player / feed (PlayerKit)
        "video_start", "video_stall", "swipe_next", "swipe_prev",
        // Keşfet / arama / detay (DiscoverKit, LibraryKit)
        "discover_refreshed", "discover_shelf_see_all", "discover_banner_tapped", "discover_card_tapped",
        "genre_filter_selected", "tag_tapped",
        "search_open", "search_query", "search_no_result", "search_result_tap",
        "series_detail_view", "series_cta_tapped", "episode_grid_tapped", "share_tap",
        // Listem (LibraryKit)
        "mylist_segment_changed", "mylist_item_removed", "favorite_add", "favorite_remove",
        "favorite_opened", "continue_watching_tapped",
        // Monetizasyon / cüzdan (WalletKit)
        "unlock_coin", "unlock_sheet_dismissed", "unlock_insufficient_coins", "unlock_vip_upsell",
        "unlock_failed", "episode_unlock_prompt", "auto_unlock_toggled",
        "coin_store_view", "coin_purchase_start", "coin_purchase_success", "coin_purchase_cancel",
        "coin_purchase_fail",
        "subscription_view", "subscription_start", "subscription_success", "subscription_cancel_intent",
        "subscription_fail", "restore_tapped",
        "iap_credited", "iap_subscription_updated", "iap_product_missing", "iap_receipt_invalid",
        "iap_family_shared_rejected", "entitlement_mismatch",
        // Ödüller / retention (RewardsKit)
        "checkin_view", "checkin_claim", "checkin_streak_break",
        "mission_view", "mission_progress", "mission_complete", "mission_claim",
        // Profil / ayarlar / hesap (ProfileKit)
        "profile_row_tapped", "settings_changed", "push_disabled",
        "link_account_started", "link_account_success", "link_account_failed",
        "account_delete_started", "account_delete_completed"
    ]

    func testRegistrySupersetsEveryEmittedEvent() {
        for name in Self.emittedEventNames {
            XCTAssertEqual(
                AnalyticsEventRegistry.validate(name), .valid,
                "emit edilen '\(name)' registry'de KAYITLI değil (08 §2.3 — önce registry'e ekle)"
            )
        }
    }

    /// Kayıtlı event'ler tracker'ı sürerken FAULT üretmemeli ve sink'e ulaşmalı (non-destructive emit).
    func testTrackerEmitsEveryKnownEventWithoutFault() {
        let logger = SpyLogger()
        let sink = SpySink()
        let tracker = AppAnalyticsTracker(logger: logger, sinks: [sink], strictInDebug: false)
        for name in Self.emittedEventNames {
            tracker.track(name, parameters: [:])
        }
        XCTAssertTrue(logger.faults.isEmpty, "bilinen event'ler fault üretmemeli: \(logger.faults)")
        XCTAssertEqual(sink.events.count, Self.emittedEventNames.count)
    }

    /// Kayıtsız ad tracker'ı sürüldüğünde fault loglanır (DEBUG'da assertionFailure yolu — strict kapalı
    /// tutulur ki test çökmesin; üretimde event DÜŞÜRÜLMEZ, yalnız `fault`).
    func testTrackerFaultsOnUnregisteredEvent() {
        let logger = SpyLogger()
        let sink = SpySink()
        let tracker = AppAnalyticsTracker(logger: logger, sinks: [sink], strictInDebug: false)
        tracker.track("totally_unregistered_event", parameters: [:])
        XCTAssertEqual(logger.faults.count, 1, "kayıtsız event tam bir fault loglamalı")
        XCTAssertTrue(logger.faults.first?.contains("unregistered") ?? false)
        // Non-destructive: doğrulama başarısız olsa da event sink'e yine ulaşır.
        XCTAssertEqual(sink.events.count, 1)
    }

    /// Biçimsiz ad (snake_case ihlali) fault loglar ama düşürülmez.
    func testTrackerFaultsOnMalformedEvent() {
        let logger = SpyLogger()
        let tracker = AppAnalyticsTracker(logger: logger, strictInDebug: false)
        tracker.track("CamelCaseEvent", parameters: [:])
        XCTAssertEqual(logger.faults.count, 1)
        XCTAssertTrue(logger.faults.first?.contains("malformed") ?? false)
    }
}

// MARK: - Test spy'ları (Sendable — tracker Sendable bağımlılık taşır)

private final class SpyLogger: Logging, @unchecked Sendable {
    private let lock = NSLock()
    private var faultMessages: [String] = []

    var faults: [String] {
        lock.lock(); defer { lock.unlock() }
        return faultMessages
    }

    func log(_ level: LogLevel, _ message: String) {
        guard level == .fault else { return }
        lock.lock(); defer { lock.unlock() }
        faultMessages.append(message)
    }
}

private final class SpySink: AnalyticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    func record(event name: String, parameters _: [String: AnalyticsValue]) {
        lock.lock(); defer { lock.unlock() }
        recorded.append(name)
    }
}
