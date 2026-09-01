import Foundation
import Testing
@testable import ShotCore

@Suite("SearchQuery")
struct SearchQueryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private let now = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 00:00 UTC

    private func shot(
        category: ShotCategory = .receipt,
        createdAt: Date,
        amounts: [Double] = []
    ) -> Shot {
        let entities = amounts.map {
            ExtractedEntity(
                kind: .amount,
                rawValue: String($0),
                normalizedValue: String($0),
                currencyCode: "TRY",
                isGrounded: true
            )
        }
        return Shot(
            assetIdentifier: UUID().uuidString,
            createdAt: createdAt,
            status: .analyzed,
            analysis: ShotAnalysis(
                category: category,
                categoryConfidence: 0.9,
                title: "t",
                summary: "s",
                tags: [],
                entities: entities,
                analyzerKind: .heuristic
            )
        )
    }

    @Test("Son 7 gün aralığı doğru hesaplanır")
    func last7DaysInterval() throws {
        let interval = try #require(RelativeDateRange.last7Days.interval(now: now, calendar: calendar))
        #expect(interval.end == now)
        #expect(interval.duration == 7 * 24 * 3600)
    }

    @Test("Geçen yıl aralığı bu yılın başında biter")
    func lastYearEndsAtThisYearStart() throws {
        let thisYear = try #require(RelativeDateRange.thisYear.interval(now: now, calendar: calendar))
        let lastYear = try #require(RelativeDateRange.lastYear.interval(now: now, calendar: calendar))
        #expect(lastYear.end == thisYear.start)
    }

    @Test("Kategori filtresi eşleşmeyeni eler")
    func categoryFilterExcludes() {
        let query = SearchQuery.resolving(
            SearchIntent(freeText: "fiş", category: .receipt), now: now, calendar: calendar
        )
        #expect(query.matchesFilters(shot(category: .receipt, createdAt: now)))
        #expect(!query.matchesFilters(shot(category: .ticket, createdAt: now)))
    }

    @Test("Tarih filtresi aralık dışını eler")
    func dateFilterExcludesOutOfRange() throws {
        let query = SearchQuery.resolving(
            SearchIntent(freeText: "", dateRange: .last7Days), now: now, calendar: calendar
        )
        let inRange = try #require(calendar.date(byAdding: .day, value: -3, to: now))
        let outOfRange = try #require(calendar.date(byAdding: .day, value: -30, to: now))
        #expect(query.matchesFilters(shot(createdAt: inRange)))
        #expect(!query.matchesFilters(shot(createdAt: outOfRange)))
    }

    @Test("Tutar filtresi yalnız temellendirilmiş tutarlara bakar")
    func amountFilterUsesGroundedAmountsOnly() {
        let query = SearchQuery.resolving(
            SearchIntent(freeText: "", minAmount: 500), now: now, calendar: calendar
        )
        #expect(query.matchesFilters(shot(createdAt: now, amounts: [1200])))
        #expect(!query.matchesFilters(shot(createdAt: now, amounts: [120])))
        // Hiç tutar çıkarılamamış kayıt tutar filtresinde elenir.
        #expect(!query.matchesFilters(shot(createdAt: now, amounts: [])))
    }

    @Test("Filtresiz niyet hiçbir şeyi elemez")
    func plainIntentMatchesEverything() {
        let query = SearchQuery.resolving(.plain("kulaklık"), now: now, calendar: calendar)
        #expect(!query.intent.hasFilters)
        #expect(query.matchesFilters(shot(category: .product, createdAt: .distantPast)))
    }
}
