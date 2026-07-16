import AppFoundation
import DiscoverKit
import Foundation
import XCTest
@testable import ShortSeriesApp

/// SS-140/143 — `PushService` orkestrasyonu: token kaydı, push→deep-link köprüsü + `push_open` atıf
/// analitiği, foreground token/izin senkronu. Dış sistemler fake port'larla (gerçek APNs/UN yok).
@MainActor
final class PushServiceTests: XCTestCase {
    private let registrar = SpyDeviceTokenRegistrar()
    private let analytics = OnboardingSpyAnalytics()
    private let remote = SpyRemoteNotificationRegistering()
    private let dispatchSpy = RouteDispatchSpy()

    private func makeService(authorized: Bool = true, optIn: Bool = true) -> PushService {
        PushService(
            registrar: registrar,
            analytics: analytics,
            remoteRegistration: remote,
            authorization: StubAuthorizationReader(authorized: authorized),
            optInProvider: { optIn },
            dispatch: { [dispatchSpy] route, source in dispatchSpy.dispatch(route, source) }
        )
    }

    // MARK: - Token kaydı

    func testDidRegisterTokenForwardsHexAndOptIn() async {
        let service = makeService(optIn: true)
        await service.registerToken(data: Data([0x0A, 0xBC, 0xDE]))

        XCTAssertEqual(registrar.registrations, [.init(token: "0abcde", optIn: true)])
    }

    func testDidRegisterTokenUsesCurrentOptIn() async {
        let service = makeService(optIn: false)
        await service.registerToken(data: Data([0xFF]))

        XCTAssertEqual(registrar.registrations, [.init(token: "ff", optIn: false)])
    }

    // MARK: - Push'a dokunma → deep-link köprüsü + push_open (08 §3.6)

    func testNewEpisodePushOpensEpisodeRouteAndTracks() {
        let service = makeService()
        service.handleOpenedPush([
            "type": "new_episode",
            "campaign_id": "new_ep_2026",
            "route": "shortseries://series/srs_9f2c1a/episode/13",
            "series_id": "srs_9f2c1a"
        ])

        // Rota köprüsü: yeni bölüm → Ana Sayfa PlayerFeed bağlamsal (DeepLinkRoute.episode), menşe push.
        XCTAssertEqual(dispatchSpy.dispatched.count, 1)
        XCTAssertEqual(dispatchSpy.dispatched.first?.route, .episode(seriesId: SeriesID("srs_9f2c1a"), number: 13))
        XCTAssertEqual(dispatchSpy.dispatched.first?.source, .push)

        let event = analytics.event(named: "push_open")
        XCTAssertEqual(event?.parameters["push_type"], .string("new_episode"))
        XCTAssertEqual(event?.parameters["campaign_id"], .string("new_ep_2026"))
        XCTAssertEqual(event?.parameters["series_id"], .string("srs_9f2c1a"))
    }

    func testContinuePushOpensPlayRoute() {
        let service = makeService()
        service.handleOpenedPush([
            "type": "continue",
            "campaign_id": "resume_x",
            "route": "shortseries://play/srs_9f2c1a?t=42"
        ])

        XCTAssertEqual(dispatchSpy.dispatched.first?.route, .play(seriesId: SeriesID("srs_9f2c1a"), startSeconds: 42))
        XCTAssertEqual(analytics.event(named: "push_open")?.parameters["push_type"], .string("continue"))
        // series_id payload'da yok → çözülmüş play rotasından türetilir.
        XCTAssertEqual(analytics.event(named: "push_open")?.parameters["series_id"], .string("srs_9f2c1a"))
    }

    func testUnknownCampaignTypeIsSilentlyIgnored() {
        let service = makeService()
        service.handleOpenedPush([
            "type": "coin_reward",
            "campaign_id": "coins_promo",
            "route": "shortseries://store/coins"
        ])

        XCTAssertTrue(dispatchSpy.dispatched.isEmpty)
        XCTAssertFalse(analytics.eventNames.contains("push_open"))
    }

    func testMalformedPayloadDoesNotCrashOrTrack() {
        let service = makeService()
        service.handleOpenedPush(["foo": "bar"]) // route yok

        XCTAssertTrue(dispatchSpy.dispatched.isEmpty)
        XCTAssertFalse(analytics.eventNames.contains("push_open"))
    }

    // MARK: - Foreground senkronu (token rotasyonu + izin takibi)

    func testRefreshWhenAuthorizedRegistersAndReconcilesOptIn() async {
        let service = makeService(authorized: true, optIn: true)
        await service.refreshRegistration()

        XCTAssertEqual(remote.count, 1)
        XCTAssertEqual(registrar.optInUpdates, [true])
    }

    func testRefreshWhenNotAuthorizedDoesNotRegister() async {
        let service = makeService(authorized: false, optIn: false)
        await service.refreshRegistration()

        XCTAssertEqual(remote.count, 0)
        // İzin senkronu yine denenir (registrar token yoksa no-op'lar).
        XCTAssertEqual(registrar.optInUpdates, [false])
    }

    // MARK: - Saf analitik eşlemesi (izole)

    func testOpenParametersOmitsMissingOptionalFields() throws {
        let route = try XCTUnwrap(URL(string: "shortseries://home"))
        let payload = PushPayload(type: .newEpisode, campaignID: nil, route: route, seriesID: nil)
        let params = PushService.openParameters(payload: payload, route: .home)

        XCTAssertEqual(params["push_type"], .string("new_episode"))
        XCTAssertNil(params["campaign_id"])
        XCTAssertNil(params["series_id"])
    }
}
