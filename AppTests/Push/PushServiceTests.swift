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

    // MARK: - F2 (SS-143) coin-ödül + öneri push'ları

    func testCoinRewardPushOpensCoinStoreRouteAndTracks() {
        let service = makeService()
        service.handleOpenedPush([
            "campaignType": "coin_reward",
            "campaignId": "coins_promo",
            "deeplink": "shortseries://store/coins"
        ])

        // Coin-ödül → CoinMağaza (sabit-path, içerik ID yok), menşe push.
        XCTAssertEqual(dispatchSpy.dispatched.count, 1)
        XCTAssertEqual(dispatchSpy.dispatched.first?.route, .coinStore(offer: nil))
        XCTAssertEqual(dispatchSpy.dispatched.first?.source, .push)

        let event = analytics.event(named: "push_open")
        XCTAssertEqual(event?.parameters["push_type"], .string("coin_reward"))
        XCTAssertEqual(event?.parameters["campaign_id"], .string("coins_promo"))
        // Coin/ödül yüzeyi içerik taşımaz → series_id yok.
        XCTAssertNil(event?.parameters["series_id"])
    }

    func testCoinRewardPushCanTargetRewardsCheckin() {
        let service = makeService()
        service.handleOpenedPush([
            "campaignType": "coin_reward",
            "campaignId": "streak_reminder",
            "deeplink": "shortseries://rewards/checkin"
        ])

        // Aynı kampanya tipi ÖdülMerkezi check-in şeridine de yönlenebilir (rota belirler).
        XCTAssertEqual(dispatchSpy.dispatched.first?.route, .rewards(anchor: .checkin))
        XCTAssertEqual(analytics.event(named: "push_open")?.parameters["push_type"], .string("coin_reward"))
    }

    func testRecommendationPushOpensSeriesDetailAndTracks() {
        let service = makeService()
        service.handleOpenedPush([
            "campaignType": "recommendation",
            "campaignId": "for_you_2026",
            "deeplink": "shortseries://series/srs_9f2c1a",
            "seriesId": "srs_9f2c1a"
        ])

        // Öneri → önerilen dizi DiziDetay (Keşfet stack'i, TabCoordinator .series delegesi).
        XCTAssertEqual(dispatchSpy.dispatched.count, 1)
        XCTAssertEqual(dispatchSpy.dispatched.first?.route, .series(id: SeriesID("srs_9f2c1a")))
        XCTAssertEqual(dispatchSpy.dispatched.first?.source, .push)

        let event = analytics.event(named: "push_open")
        XCTAssertEqual(event?.parameters["push_type"], .string("recommendation"))
        XCTAssertEqual(event?.parameters["campaign_id"], .string("for_you_2026"))
        XCTAssertEqual(event?.parameters["series_id"], .string("srs_9f2c1a"))
    }

    func testRecommendationPushWithInvalidSeriesIdTracksButDoesNotDispatch() {
        let service = makeService()
        // Geçersiz-ID savunması: PushPayload parse olur (ID doğrulaması burada YAPILMAZ) ama
        // DeepLinkRoute(url:) contentIDPattern regex'ini geçmeyen ID'yi düşürür → rota nil.
        service.handleOpenedPush([
            "campaignType": "recommendation",
            "campaignId": "for_you_2026",
            "deeplink": "shortseries://series/not-a-valid-id",
            "seriesId": "not-a-valid-id"
        ])

        // Rota düşürüldü → hiçbir dispatch olmaz (path injection'a set edilemez).
        XCTAssertTrue(dispatchSpy.dispatched.isEmpty)
        // Ama push_open YİNE atılır (atıf kaybolmaz) — push_type payload rawValue'sundan.
        let event = analytics.event(named: "push_open")
        XCTAssertEqual(event?.parameters["push_type"], .string("recommendation"))
        // series_id payload'dan taşınır (rota çözülmese de analitik atıf korunur).
        XCTAssertEqual(event?.parameters["series_id"], .string("not-a-valid-id"))
    }

    func testUnknownCampaignTypeIsSilentlyIgnored() {
        let service = makeService()
        // F1/F2 dışı wire tip → PushPayload nil (savunmacı gate) → dispatch YOK, push_open atılmaz.
        service.handleOpenedPush([
            "campaignType": "flash_sale",
            "campaignId": "promo",
            "deeplink": "shortseries://store/coins"
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
