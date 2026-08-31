import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

/// AramaModel öneri-fazı dayanıklılık (DiscoverKit bug-hunt): yeni sorgu bayat önerileri hemen temizler,
/// boş öneri blank ekran yerine browse fallback'ine döner.
@MainActor
@Suite("AramaModel öneri dayanıklılık")
struct AramaModelSuggestTests {
    private func makeModel(search: SpySearch) -> AramaModel {
        AramaModel(
            search: search,
            recentStore: FakeRecentStore(),
            analytics: MockAnalytics(),
            delegate: nil,
            source: .kesfet,
            initialQuery: nil,
            debounceInterval: .zero
        )
    }

    @Test func yeniSorguBayatOnerileriHemenTemizler() async {
        // #5: "mid" önerileri gösterilirken kullanıcı "midn" yazınca scheduleSuggest bayat "mid" önerilerini
        // HEMEN (debounce+ağ'dan ÖNCE) temizlemeli — yeni metinle eski sorgunun önerileri gösterilmesin.
        let search = SpySearch()
        search.setSuggest([SearchSuggestion(text: "midnight", kind: .query, seriesID: nil)], for: "mid")
        search.setSuggest([SearchSuggestion(text: "midnite", kind: .query, seriesID: nil)], for: "midn")
        let model = makeModel(search: search)
        model.queryChanged("mid")
        await model.pendingWork()
        #expect(model.suggestions.count == 1) // "mid" önerileri geldi

        model.queryChanged("midn")
        #expect(model.suggestions.isEmpty) // bayat "mid" önerileri debounce/ağ beklemeden temizlendi

        await model.pendingWork()
        #expect(model.suggestions.map(\.text) == ["midnite"]) // yeni sorgunun önerileri geldi
    }

    @Test func bosOneriBrowseFallbackineDoner() async {
        // #6: 2+ karakterli sorgu için suggest [] dönerse `.suggesting`de BLANK ekran yerine browse (son+popüler)
        // fallback'e dönmeli (öneri yokluğu ≠ sonuç yokluğu; kullanıcı submit ile tam sonuç arayabilir).
        let search = SpySearch()
        search.setSuggest([], for: "xyz")
        let model = makeModel(search: search)

        model.queryChanged("xyz")
        await model.pendingWork()

        #expect(model.phase == .browsing) // blank .suggesting DEĞİL
        #expect(model.suggestions.isEmpty)
    }
}
