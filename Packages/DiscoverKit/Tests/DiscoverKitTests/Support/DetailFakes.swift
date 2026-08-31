import AppFoundation
import ContentKit
import Foundation
@testable import DiscoverKit

final class FakeHistory: WatchHistoryReading, @unchecked Sendable {
    private let lock = NSLock()
    private var progress: WatchProgress?

    init(progress: WatchProgress? = nil) {
        self.progress = progress
    }

    func setProgress(_ progress: WatchProgress?) {
        lock.withLock { self.progress = progress }
    }

    func latestProgress(forSeries seriesID: SeriesID) async -> WatchProgress? {
        lock.withLock { progress }
    }
}

final class FakeFavorites: FavoritesGateway, @unchecked Sendable {
    private let lock = NSLock()
    private var favorites: Set<SeriesID>
    private var failOnSet: Bool

    init(favorites: Set<SeriesID> = [], failOnSet: Bool = false) {
        self.favorites = favorites
        self.failOnSet = failOnSet
    }

    private(set) var setCalls: [(isFavorite: Bool, seriesID: SeriesID)] = []

    func setFailOnSet(_ fail: Bool) {
        lock.withLock { failOnSet = fail }
    }

    func isFavorite(_ seriesID: SeriesID) async -> Bool {
        lock.withLock { favorites.contains(seriesID) }
    }

    func setFavorite(_ isFavorite: Bool, seriesID: SeriesID) async throws {
        try lock.withLock {
            setCalls.append((isFavorite, seriesID))
            if failOnSet {
                throw AppError.network(.timeout)
            }
            if isFavorite {
                favorites.insert(seriesID)
            } else {
                favorites.remove(seriesID)
            }
        }
    }
}

/// VIP / açılmış bölüm entitlement fake'i (AppFoundation `EntitlementChecking`).
final class FakeEntitlements: EntitlementChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var unlocked: Set<EpisodeID>
    private var isVIP: Bool

    init(unlocked: Set<EpisodeID> = [], isVIP: Bool = false) {
        self.unlocked = unlocked
        self.isVIP = isVIP
    }

    func hasAccess(to episodeID: EpisodeID) async -> Bool {
        lock.withLock { isVIP || unlocked.contains(episodeID) }
    }

    /// Test: çalışma anında bir bölüme erişim ver (unlock/satın-alma simülasyonu — #2 gözlem testi).
    func grant(_ episodeID: EpisodeID) {
        lock.withLock { _ = unlocked.insert(episodeID) }
    }
}

/// Entitlement-değişim sinyali fake'i (#2): `emit()` ile manuel tetiklenir; model gözlemcisi her emisyonda
/// erişimi yeniden türetir. AsyncStream buffer'ı `.unbounded` (varsayılan) → emit yayıldıysa asla düşmez.
final class ManualEntitlementChanges: EntitlementChangeObserving, @unchecked Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream<Void>.makeStream()
    }

    func entitlementChanges() -> AsyncStream<Void> {
        stream
    }

    func emit() {
        continuation.yield(())
    }
}

/// `isFavorite()` çağrısını bir kapı ardında bloklar (#2 yarış testi): load()'un favorites-await'inde
/// askıya alıp o pencerede (recompute bitti, loadState hâlâ .loading) entitlement sinyali enjekte etmeyi
/// sağlar. `waitUntilEntered()` load'un kapıya vardığını, `release()` devam etmesini bekletir.
final class GateFavorites: FavoritesGateway, @unchecked Sendable {
    private let entered: AsyncStream<Void>
    private let enteredCont: AsyncStream<Void>.Continuation
    private let gate: AsyncStream<Void>
    private let gateCont: AsyncStream<Void>.Continuation

    init() {
        (entered, enteredCont) = AsyncStream<Void>.makeStream()
        (gate, gateCont) = AsyncStream<Void>.makeStream()
    }

    func isFavorite(_: SeriesID) async -> Bool {
        enteredCont.yield(())
        var iterator = gate.makeAsyncIterator()
        _ = await iterator.next()
        return false
    }

    func setFavorite(_: Bool, seriesID _: SeriesID) async throws {}

    /// load() favorites-await'ine (kapı içine) ulaşana dek bekler.
    func waitUntilEntered() async {
        var iterator = entered.makeAsyncIterator()
        _ = await iterator.next()
    }

    func release() {
        gateCont.yield(())
    }
}

@MainActor
final class DiziDetayDelegateSpy: DiziDetayDelegate {
    struct Started: Equatable {
        let seriesID: SeriesID
        let episodeNumber: Int
        let position: Double
    }

    var started: [Started] = []
    var unlockIntents: [LockedEpisodeIntent] = []
    var sharedURLs: [URL] = []
    var discoverGenres: [String] = []
    var discoverRootRequested = 0

    func diziDetayStartWatching(seriesID: SeriesID, episodeNumber: Int, startPositionSec: Double) {
        started.append(Started(seriesID: seriesID, episodeNumber: episodeNumber, position: startPositionSec))
    }

    func diziDetayRequestsUnlock(_ intent: LockedEpisodeIntent) {
        unlockIntents.append(intent)
    }

    func diziDetayShare(_ url: URL) {
        sharedURLs.append(url)
    }

    func diziDetayRequestsDiscover(genre: String) {
        discoverGenres.append(genre)
    }

    func diziDetayRequestsDiscoverRoot() {
        discoverRootRequested += 1
    }
}
