import AppFoundation
import ContentKit
import Foundation
@testable import DiscoverKit

/// Programlanabilir `SearchServicing` fake'i + çağrı spy'ı.
final class SpySearch: SearchServicing, @unchecked Sendable {
    private let lock = NSLock()

    private var suggestByQuery: [String: [SearchSuggestion]] = [:]
    private var suggestDefault: [SearchSuggestion] = []
    private var searchPages: [String?: Result<Page<Series>, AppError>] = [:]
    private var searchDefault: Result<Page<Series>, AppError> = .success(Page(items: [], nextCursor: nil, ttlSec: nil))
    private var popularResult: Result<[String], AppError> = .success([])

    private(set) var suggestQueries: [String] = []
    private(set) var searchCalls: [(query: String, cursor: String?)] = []
    private(set) var popularCallCount = 0

    // MARK: - Programlama

    func setSuggest(_ suggestions: [SearchSuggestion], for query: String? = nil) {
        lock.withLock {
            if let query {
                suggestByQuery[query] = suggestions
            } else {
                suggestDefault = suggestions
            }
        }
    }

    func setSearch(_ result: Result<Page<Series>, AppError>, cursor: String? = nil, isDefault: Bool = false) {
        lock.withLock {
            if isDefault {
                searchDefault = result
            } else {
                searchPages[cursor] = result
            }
        }
    }

    func setPopular(_ result: Result<[String], AppError>) {
        lock.withLock { popularResult = result }
    }

    // MARK: - SearchServicing

    func suggest(query: String) async throws -> [SearchSuggestion] {
        lock.withLock {
            suggestQueries.append(query)
            return suggestByQuery[query] ?? suggestDefault
        }
    }

    func search(query: String, cursor: String?) async throws -> Page<Series> {
        try lock.withLock {
            searchCalls.append((query, cursor))
            return try (searchPages[cursor] ?? searchDefault).get()
        }
    }

    func popular() async throws -> [String] {
        try lock.withLock {
            popularCallCount += 1
            return try popularResult.get()
        }
    }
}

/// Bellek-içi son aramalar deposu (§4.11 semantiği: en yeni önce, dedup, max 10).
final class FakeRecentStore: RecentSearchStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String]

    init(_ items: [String] = []) {
        self.items = items
    }

    func load() -> [String] {
        lock.withLock { items }
    }

    func add(_ query: String) {
        let normalized = SearchInputMachine.normalize(query)
        guard !normalized.isEmpty else { return }
        lock.withLock {
            items.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
            items.insert(normalized, at: 0)
            items = Array(items.prefix(maxRecentSearches))
        }
    }

    func remove(_ query: String) {
        lock.withLock { items.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame } }
    }

    func clear() {
        lock.withLock { items = [] }
    }
}

@MainActor
final class AramaDelegateSpy: AramaDelegate {
    var selectedSeries: [SeriesID] = []
    var dismissed = 0

    func aramaDidSelectSeries(_ seriesID: SeriesID) {
        selectedSeries.append(seriesID)
    }

    func aramaRequestsDismiss() {
        dismissed += 1
    }
}
