import AppFoundation
import DiscoverKit
import XCTest
@testable import ShortSeriesApp

/// SS-142 deep link yönlendirme sözleşmesinin saf (kompozisyonsuz) doğrulamaları. TabCoordinator
/// başarılı her çözümde `deeplink_opened {route_type, source}` atar (02 §8.4 kural 5); bu event ve
/// menşe enum'u sözleşmeyle kilitlenir — böylece emit fault üretmez ve `route_type`/`source`
/// değerleri 08 kataloğu + 02 §8.4 ile birebir kalır.
final class DeepLinkRoutingContractTests: XCTestCase {
    /// App tarafından emit edilen `deeplink_opened` registry'de KAYITLI olmalı (aksi halde
    /// `AppAnalyticsTracker` DEBUG'da assertionFailure tetikler — her deep link'te crash).
    func testDeeplinkOpenedEventIsRegistered() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("deeplink_opened"), .valid)
    }

    /// `DeepLinkSource` rawValue'ları 02 §8.4 kural 5 `source` enum'uyla birebir (`internal` Swift
    /// anahtar kelimesi olduğundan case adı `appInternal`, rawValue korunur).
    func testDeepLinkSourceRawValuesMatchSpec() {
        XCTAssertEqual(DeepLinkSource.push.rawValue, "push")
        XCTAssertEqual(DeepLinkSource.universal.rawValue, "universal")
        XCTAssertEqual(DeepLinkSource.qr.rawValue, "qr")
        XCTAssertEqual(DeepLinkSource.appInternal.rawValue, "internal")
    }

    /// `route_type` olarak atılan `DeepLinkRoute.analyticsType` değerleri iyi biçimli (snake_case)
    /// olmalı — analitik parametre değeri olarak temiz kalsın (08 §2.1).
    func testAllRouteAnalyticsTypesAreWellFormed() {
        let routes: [DeepLinkRoute] = [
            .home,
            .series(id: SeriesID("srs_abc123")),
            .episode(seriesId: SeriesID("srs_abc123"), number: 3),
            .play(seriesId: SeriesID("srs_abc123"), startSeconds: 42),
            .discover(genre: "drama"),
            .search(query: "aşk"),
            .rewards(anchor: .checkin),
            .coinStore(offer: "welcome"),
            .vip(preselectedPlan: "annual"),
            .myList(segment: .favorites),
            .profile,
            .settings(section: "playback"),
            .notifications
        ]
        for route in routes {
            XCTAssertTrue(
                AnalyticsEventRegistry.isWellFormed(route.analyticsType),
                "route_type '\(route.analyticsType)' snake_case olmalı (08 §2.1)"
            )
        }
    }
}
