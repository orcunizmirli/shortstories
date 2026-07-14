import AppFoundation
import ContentKit
import Foundation
@testable import DiscoverKit

/// Deterministic suspension primitive for concurrency/race tests.
///
/// A caller does `await gate.wait(label)` to arrive at `label` and suspend until the test
/// calls `gate.open(label)`. The test can synchronise with in-flight callers via
/// `await gate.arrivals(label, n)` which returns once at least `n` callers have arrived at
/// `label`. Continuations are always resumed OUTSIDE the lock so a resumed task can never
/// re-enter the lock synchronously.
final class CallGate: @unchecked Sendable {
    private struct ArrivalWaiter {
        let label: String
        let threshold: Int
        let cont: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var openLabels: Set<String> = []
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var arrived: [String: Int] = [:]
    private var arrivalWaiters: [ArrivalWaiter] = []

    /// Arrive at `label` and suspend until it is opened.
    func wait(_ label: String) async {
        let (arrivalConts, alreadyOpen): ([CheckedContinuation<Void, Never>], Bool) = lock.withLock {
            arrived[label, default: 0] += 1
            let count = arrived[label] ?? 0
            let ready = arrivalWaiters.filter { $0.label == label && $0.threshold <= count }
            arrivalWaiters.removeAll { $0.label == label && $0.threshold <= count }
            return (ready.map(\.cont), openLabels.contains(label))
        }
        arrivalConts.forEach { $0.resume() }
        if alreadyOpen {
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let openNow: Bool = lock.withLock {
                if openLabels.contains(label) {
                    return true
                }
                waiters[label, default: []].append(cont)
                return false
            }
            if openNow {
                cont.resume()
            }
        }
    }

    /// Release every current and future caller waiting on `label`.
    func open(_ label: String) {
        let conts: [CheckedContinuation<Void, Never>] = lock.withLock {
            openLabels.insert(label)
            let waiting = waiters[label] ?? []
            waiters[label] = nil
            return waiting
        }
        conts.forEach { $0.resume() }
    }

    /// Await until at least `threshold` callers have arrived at `label`.
    func arrivals(_ label: String, _ threshold: Int = 1) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let ready: Bool = lock.withLock {
                if arrived[label, default: 0] >= threshold {
                    return true
                }
                arrivalWaiters.append(ArrivalWaiter(label: label, threshold: threshold, cont: cont))
                return false
            }
            if ready {
                cont.resume()
            }
        }
    }
}

/// Reference box for capturing a signal from a `@Sendable` closure (e.g. an Observation
/// `onChange` callback) without tripping Swift 6's captured-var concurrency check.
final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}

/// `SearchServicing` fake whose `search` calls can be gated per (query, cursor) key so a
/// superseded query can be held suspended while a newer one completes.
final class GatedSearch: SearchServicing, @unchecked Sendable {
    let gate = CallGate()
    private let lock = NSLock()
    private var results: [String: Result<Page<Series>, AppError>] = [:]
    private let gatedKeys: Set<String>
    private(set) var searchCalls: [(query: String, cursor: String?)] = []

    /// `gatedKeys` uses the "query|cursor" form (cursor omitted → "query|").
    init(gatedKeys: Set<String> = []) {
        self.gatedKeys = gatedKeys
    }

    static func key(_ query: String, _ cursor: String?) -> String {
        "\(query)|\(cursor ?? "")"
    }

    func setResult(_ result: Result<Page<Series>, AppError>, query: String, cursor: String? = nil) {
        lock.withLock { results[Self.key(query, cursor)] = result }
    }

    func suggest(query: String) async throws -> [SearchSuggestion] {
        []
    }

    func popular() async throws -> [String] {
        []
    }

    func search(query: String, cursor: String?) async throws -> Page<Series> {
        let key = Self.key(query, cursor)
        lock.withLock { searchCalls.append((query, cursor)) }
        if gatedKeys.contains(key) {
            await gate.wait(key)
        }
        return try lock.withLock {
            try (results[key] ?? .success(Page(items: [], nextCursor: nil, ttlSec: nil))).get()
        }
    }
}

/// `CatalogServicing` fake whose `discover()` calls suspend on a per-call-index gate, so
/// two concurrent revalidations can be completed in a controlled order. Only `discover`
/// is exercised; the other endpoints are unused here.
final class GatedCatalog: CatalogServicing, @unchecked Sendable {
    let gate = CallGate()
    private let lock = NSLock()
    private let discoverResults: [Result<DiscoverContent, AppError>]
    private var discoverIndex = 0

    init(discoverResults: [Result<DiscoverContent, AppError>]) {
        self.discoverResults = discoverResults
    }

    func discover() async throws -> DiscoverContent {
        let index: Int = lock.withLock { let current = discoverIndex; discoverIndex += 1; return current }
        await gate.wait("\(index)")
        return try lock.withLock { try discoverResults[index].get() }
    }

    func seriesDetail(id: SeriesID) async throws -> Series {
        throw AppError.unexpected(underlying: "GatedCatalog.seriesDetail unused")
    }

    func episodes(seriesId: SeriesID, cursor: String?) async throws -> Page<Episode> {
        throw AppError.unexpected(underlying: "GatedCatalog.episodes unused")
    }

    func collectionPage(id: String, cursor: String?) async throws -> Page<Series> {
        throw AppError.unexpected(underlying: "GatedCatalog.collectionPage unused")
    }
}

/// `FavoritesGateway` fake that gates selected `setFavorite` calls (by call index, default the
/// first) so an in-flight toggle can be held while a second toggle is attempted.
final class GatedFavorites: FavoritesGateway, @unchecked Sendable {
    let gate = CallGate()
    private let lock = NSLock()
    private var favorites: Set<SeriesID>
    private var callIndex = 0
    private let gatedCalls: Set<Int>
    private(set) var setCalls: [(isFavorite: Bool, seriesID: SeriesID)] = []

    init(favorites: Set<SeriesID> = [], gatedCalls: Set<Int> = [0]) {
        self.favorites = favorites
        self.gatedCalls = gatedCalls
    }

    var setCallCount: Int {
        lock.withLock { setCalls.count }
    }

    func isFavorite(_ seriesID: SeriesID) async -> Bool {
        lock.withLock { favorites.contains(seriesID) }
    }

    func setFavorite(_ isFavorite: Bool, seriesID: SeriesID) async throws {
        let index: Int = lock.withLock {
            setCalls.append((isFavorite, seriesID))
            let current = callIndex
            callIndex += 1
            return current
        }
        if gatedCalls.contains(index) {
            await gate.wait("\(index)")
        }
        lock.withLock {
            if isFavorite {
                favorites.insert(seriesID)
            } else {
                favorites.remove(seriesID)
            }
        }
    }
}
