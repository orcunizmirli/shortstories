import AppFoundation
import DiscoverKit
import XCTest
@testable import ShortSeriesApp

/// SS-143 — push atıf event sözleşmesi (08 §3.6). `push_open` istemci-tarafı emit edilir → registry'de
/// KAYITLI olmalı (aksi halde `AppAnalyticsTracker` DEBUG'da her push'ta assertionFailure). `push_received`
/// istemciden GÖNDERİLMEZ (teslimat backend'de APNs yanıtından loglanır — 08 §3.6 Not) → registry'de yok.
final class PushAnalyticsContractTests: XCTestCase {
    func testPushOpenIsRegistered() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("push_open"), .valid)
    }

    func testPushOpenIsWellFormed() {
        XCTAssertTrue(AnalyticsEventRegistry.isWellFormed("push_open"))
    }

    /// `push_received` istemci event'i DEĞİL (08 §3.6 Not): registry'ye eklenmez, emit edilmez.
    func testPushReceivedIsNotAClientEvent() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("push_received"), .unregistered)
    }

    /// F2 (SS-143): `push_open.push_type` wire değerleri 08 §3.6 enum'uyla birebir
    /// (`new_episode|continue|coin_reward|recommendation`). `PushService.openParameters` bu rawValue'yu
    /// emit eder → drift olursa backend atıf kırılır.
    func testPushTypeRawValuesMatchSpec() {
        XCTAssertEqual(PushCampaignType.newEpisode.rawValue, "new_episode")
        XCTAssertEqual(PushCampaignType.continueWatching.rawValue, "continue")
        XCTAssertEqual(PushCampaignType.coinReward.rawValue, "coin_reward")
        XCTAssertEqual(PushCampaignType.recommendation.rawValue, "recommendation")
    }

    /// F2 hedef rotalarının `route_type` (deeplink_opened) değerleri 08 §8.3 kataloğu ile birebir:
    /// coin-ödül → `coin_store`/`rewards`, öneri → `series`. TabCoordinator bu değerlerle emit eder.
    func testF2TargetRouteTypesMatchCatalog() {
        XCTAssertEqual(DeepLinkRoute.coinStore(offer: nil).analyticsType, "coin_store")
        XCTAssertEqual(DeepLinkRoute.rewards(anchor: .checkin).analyticsType, "rewards")
        XCTAssertEqual(DeepLinkRoute.series(id: SeriesID("srs_9f2c1a")).analyticsType, "series")
    }
}
