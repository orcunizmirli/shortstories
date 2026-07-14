import AppFoundation
import Foundation
import Testing
@testable import DiscoverKit

/// Deep link / universal link şeması (02 §8.2/§8.4). Saf URL ↔ Route türetimi.
@Suite("DeepLinkResolver")
struct DeepLinkResolverTests {
    private func route(_ string: String) -> DeepLinkRoute? {
        guard let url = URL(string: string) else { return nil }
        return DeepLinkResolver.route(from: url)
    }

    // MARK: - Custom scheme çözümleme (§8.2)

    @Test func home() {
        #expect(route("shortseries://home") == .home)
    }

    @Test func seriesDetail() {
        #expect(route("shortseries://series/srs_9f2c1a") == .series(id: SeriesID("srs_9f2c1a")))
    }

    @Test func episodeContextual() {
        #expect(
            route("shortseries://series/srs_9f2c1a/episode/7")
                == .episode(seriesId: SeriesID("srs_9f2c1a"), number: 7)
        )
    }

    @Test func playWithStartSeconds() {
        #expect(
            route("shortseries://play/srs_9f2c1a?t=42")
                == .play(seriesId: SeriesID("srs_9f2c1a"), startSeconds: 42)
        )
    }

    @Test func playWithoutStartSeconds() {
        #expect(
            route("shortseries://play/srs_9f2c1a")
                == .play(seriesId: SeriesID("srs_9f2c1a"), startSeconds: nil)
        )
    }

    @Test func discoverWithGenre() {
        #expect(route("shortseries://discover?genre=romance") == .discover(genre: "romance"))
    }

    @Test func discoverWithoutGenre() {
        #expect(route("shortseries://discover") == .discover(genre: nil))
    }

    @Test func searchWithQuery() {
        #expect(route("shortseries://search?q=ceo%20romance") == .search(query: "ceo romance"))
    }

    @Test func rewardsRoot() {
        #expect(route("shortseries://rewards") == .rewards(anchor: nil))
    }

    @Test func rewardsCheckin() {
        #expect(route("shortseries://rewards/checkin") == .rewards(anchor: .checkin))
    }

    @Test func coinStore() {
        #expect(route("shortseries://store/coins?offer=launch") == .coinStore(offer: "launch"))
    }

    @Test func vip() {
        #expect(route("shortseries://store/vip?plan=weekly") == .vip(preselectedPlan: "weekly"))
    }

    @Test func myListSegment() {
        #expect(route("shortseries://mylist?segment=continue") == .myList(segment: .continueWatching))
    }

    @Test func profileSettingsNotifications() {
        #expect(route("shortseries://profile") == .profile)
        #expect(route("shortseries://settings?section=playback") == .settings(section: "playback"))
        #expect(route("shortseries://notifications") == .notifications)
    }

    // MARK: - Universal link eşleniği (§8.2 — path'ler bire bir)

    @Test func universalSeries() {
        #expect(route("https://shortseries.app/s/srs_9f2c1a") == .series(id: SeriesID("srs_9f2c1a")))
    }

    @Test func universalEpisode() {
        #expect(
            route("https://shortseries.app/s/srs_9f2c1a/e/7")
                == .episode(seriesId: SeriesID("srs_9f2c1a"), number: 7)
        )
    }

    @Test func universalPlayDiscoverSearch() {
        #expect(route("https://shortseries.app/play/srs_9f2c1a?t=9") == .play(seriesId: SeriesID("srs_9f2c1a"), startSeconds: 9))
        #expect(route("https://shortseries.app/discover?genre=revenge") == .discover(genre: "revenge"))
        #expect(route("https://shortseries.app/search?q=midnight") == .search(query: "midnight"))
    }

    // MARK: - §8.4 çözümleme kuralları

    @Test func unknownPathIsNil() {
        #expect(route("shortseries://galaxy/brain") == nil)
        #expect(route("https://shortseries.app/totally/unknown") == nil)
    }

    @Test func foreignHostIsNil() {
        // Universal link yalnız shortseries.app host'unda çözülür.
        #expect(route("https://evil.example.com/s/srs_9f2c1a") == nil)
    }

    @Test func invalidSeriesIDIsDropped() {
        // §8.4 kural 4: ID format regex geçmeyen değer düşürülür (injection savunması).
        #expect(route("shortseries://series/DROP%20TABLE") == nil)
        #expect(route("shortseries://series/xx_short") == nil) // prefix 3 harf değil
        #expect(route("shortseries://series/abc_ab") == nil) // gövde < 6
    }

    @Test func validIDShapeAccepted() {
        #expect(DeepLinkResolver.isValidContentID("srs_9f2c1a"))
        #expect(DeepLinkResolver.isValidContentID("epi_ABCdef123456"))
        #expect(!DeepLinkResolver.isValidContentID("sr_9f2c1a"))
        #expect(!DeepLinkResolver.isValidContentID("srs_@@@@@@"))
    }

    @Test func episodeNumberMustBePositiveInt() {
        #expect(route("shortseries://series/srs_9f2c1a/episode/0") == nil)
        #expect(route("shortseries://series/srs_9f2c1a/episode/abc") == nil)
    }

    // MARK: - Round-trip: universal link üretimi (paylaşım, §8.1.1)

    @Test func universalLinkGenerationRoundTrips() {
        let cases: [DeepLinkRoute] = [
            .home,
            .series(id: SeriesID("srs_9f2c1a")),
            .episode(seriesId: SeriesID("srs_9f2c1a"), number: 12),
            .play(seriesId: SeriesID("srs_9f2c1a"), startSeconds: 30),
            .discover(genre: "romance"),
            .search(query: "ceo romance"),
            .rewards(anchor: .checkin),
            .coinStore(offer: "launch"),
            .vip(preselectedPlan: "weekly"),
            .myList(segment: .favorites),
            .profile,
            .settings(section: "playback"),
            .notifications
        ]
        for expected in cases {
            let url = DeepLinkResolver.universalLink(for: expected)
            #expect(DeepLinkResolver.route(from: url) == expected, "round-trip failed for \(expected)")
        }
    }

    @Test func shareLinkUsesShortSeriesAppDomain() {
        let url = DeepLinkResolver.shareLink(forSeries: SeriesID("srs_9f2c1a"))
        #expect(url.absoluteString == "https://shortseries.app/s/srs_9f2c1a")
    }

    @Test func customSchemeGenerationRoundTrips() {
        let url = DeepLinkResolver.customScheme(for: .episode(seriesId: SeriesID("srs_9f2c1a"), number: 3))
        #expect(url.scheme == "shortseries")
        #expect(DeepLinkResolver.route(from: url) == .episode(seriesId: SeriesID("srs_9f2c1a"), number: 3))
    }
}
