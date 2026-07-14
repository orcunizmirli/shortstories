import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

@Suite("SearchAPI")
struct SearchAPITests {
    private func data(_ json: String) -> Result<Data, AppError> {
        .success(Data(json.utf8))
    }

    @Test func suggestMapsSeriesAndQueryTypes() async throws {
        let client = MockAPIClient()
        client.stub("/search/suggest", with: data("""
        { "suggestions": [
            { "text": "midnight heir", "type": "series", "seriesId": "srs_9f2c1a" },
            { "text": "midnight", "type": "query", "seriesId": null },
            { "text": "future", "type": "brandnew", "seriesId": null }
        ] }
        """))
        let api = SearchAPI(client: client)

        let suggestions = try await api.suggest(query: "mid")

        #expect(suggestions.count == 3)
        #expect(suggestions[0].kind == .series)
        #expect(suggestions[0].seriesID == SeriesID("srs_9f2c1a"))
        #expect(suggestions[1].kind == .query)
        // Bilinmeyen tip → sorgu önerisi (ileri uyumluluk).
        #expect(suggestions[2].kind == .query)
    }

    @Test func searchDecodesSeriesFromBareStringIDsAndMapsCursor() async throws {
        let client = MockAPIClient()
        client.stub("/search", with: data("""
        { "results": [ {
            "id": "srs_9f2c1a", "title": "Midnight", "synopsis": "s",
            "coverURL": "https://cdn.example.com/c.jpg", "bannerURL": null,
            "genres": [ { "id": "romance", "name": "Romance", "iconURL": null } ],
            "tags": [],
            "episodeCount": 60, "releasedEpisodeCount": 60, "freeEpisodeCount": 5,
            "releaseState": "completed", "nextEpisodeAt": null,
            "stats": { "viewCount": 10, "favoriteCount": 2, "trendingRank": null },
            "localeInfo": { "audioLanguage": "en", "subtitleLanguages": ["en"] },
            "updatedAt": "2023-11-14T00:00:00Z"
        } ], "nextCursor": "c2" }
        """))
        let api = SearchAPI(client: client)

        let page = try await api.search(query: "midnight", cursor: nil)

        #expect(page.items.count == 1)
        #expect(page.items[0].id == SeriesID("srs_9f2c1a"))
        #expect(page.items[0].genres.first?.id == "romance")
        #expect(page.nextCursor == "c2")
        #expect(!page.isLastPage)
    }

    @Test func popularReturnsQueries() async throws {
        let client = MockAPIClient()
        client.stub("/search/popular", with: data("""
        { "queries": ["ceo romance", "revenge"] }
        """))
        let api = SearchAPI(client: client)

        let popular = try await api.popular()

        #expect(popular == ["ceo romance", "revenge"])
    }

    @Test func searchSendsQueryAndCursorParameters() async throws {
        let client = MockAPIClient()
        client.stub("/search", with: data("{ \"results\": [], \"nextCursor\": null }"))
        let api = SearchAPI(client: client)

        _ = try await api.search(query: "midnight", cursor: "c5")

        let endpoint = client.receivedEndpoints.first { $0.path == "/search" }
        let names = endpoint?.query.map(\.name) ?? []
        #expect(names.contains("q"))
        #expect(names.contains("cursor"))
    }
}
