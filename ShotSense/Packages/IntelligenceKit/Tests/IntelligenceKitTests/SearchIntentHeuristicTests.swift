import ShotCore
import Testing
@testable import IntelligenceKit

@Suite("SearchIntentHeuristic")
struct SearchIntentHeuristicTests {
    @Test("Kategori sorgudan çıkarılır")
    func extractsCategory() {
        #expect(SearchIntentHeuristic.parse("fiş").category == .receipt)
        #expect(SearchIntentHeuristic.parse("wifi şifresi").category == .wifi)
    }

    @Test("Göreli tarih aralığı çıkarılır")
    func extractsDateRange() {
        #expect(SearchIntentHeuristic.parse("geçen ay aldığım fişler").dateRange == .last30Days)
        #expect(SearchIntentHeuristic.parse("bu yıl").dateRange == .thisYear)
    }

    @Test("Alt tutar sınırı çıkarılır")
    func extractsMinimumAmount() {
        let intent = SearchIntentHeuristic.parse("500 TL üstü fişler")
        #expect(intent.minAmount == 500)
        #expect(intent.maxAmount == nil)
        #expect(intent.category == .receipt)
    }

    @Test("Üst tutar sınırı çıkarılır")
    func extractsMaximumAmount() {
        let intent = SearchIntentHeuristic.parse("100 TL altında ürünler")
        #expect(intent.maxAmount == 100)
        #expect(intent.minAmount == nil)
    }

    @Test("Yön belirtilmemiş tutar sınır üretmez")
    func amountWithoutDirectionIsIgnored() {
        // "250 TL kulaklık" bir filtre değil, arama terimidir.
        let intent = SearchIntentHeuristic.parse("250 TL kulaklık")
        #expect(intent.minAmount == nil)
        #expect(intent.maxAmount == nil)
    }

    @Test("Filtreye çevrilen kelimeler serbest metinden düşer")
    func consumedTermsLeaveFreeText() {
        // Aksi hâlde "fiş" hem filtre hem arama terimi olur ve sıralamayı bozar.
        let intent = SearchIntentHeuristic.parse("geçen ay kulaklık fişi")
        #expect(!intent.freeText.contains("fis"))
        #expect(!intent.freeText.contains("gecen ay"))
        #expect(intent.freeText.contains("kulaklik"))
    }

    @Test("Filtre bulunmayan sorgu düz metin kalır")
    func plainQueryStaysPlain() {
        let intent = SearchIntentHeuristic.parse("kulaklık")
        #expect(!intent.hasFilters)
    }

    @Test("Boş sorgu düz niyete döner")
    func emptyQuery() {
        #expect(!SearchIntentHeuristic.parse("").hasFilters)
    }
}
