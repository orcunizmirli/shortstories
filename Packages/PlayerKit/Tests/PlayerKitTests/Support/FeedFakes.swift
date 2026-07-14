import AppFoundation
import ContentKit
import Foundation
@testable import PlayerKit

// MARK: - Feed fixture üreticileri

extension Fixture {
    static func series(
        id: String = "s1",
        title: String = "Test Dizisi",
        episodeCount: Int = 10
    ) -> Series {
        Series(
            id: SeriesID(id),
            title: title,
            synopsis: "Sinopsis",
            coverURL: URL(string: "https://cdn.test/covers/\(id).jpg")!,
            bannerURL: nil,
            genres: [],
            tags: [],
            episodeCount: episodeCount,
            releasedEpisodeCount: episodeCount,
            freeEpisodeCount: 5,
            releaseState: .completed,
            nextEpisodeAt: nil,
            stats: SeriesStats(viewCount: 0, favoriteCount: 0, trendingRank: nil),
            localeInfo: LocaleInfo(audioLanguage: "en", subtitleLanguages: []),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    static func feedItem(
        episode: Episode,
        series: Series = Fixture.series(),
        progress: WatchProgress? = nil
    ) -> FeedItem {
        FeedItem(
            id: "fi-\(episode.id.rawValue)",
            type: .episode,
            episode: episode,
            series: series,
            progress: progress,
            reason: nil
        )
    }

    /// 0..<count feed indeksi hizalı bölüm kartları üretir.
    static func feedItems(count: Int, lockedIndexes: Set<Int> = []) -> [FeedItem] {
        let series = Fixture.series(episodeCount: count)
        return episodes(count: count, lockedIndexes: lockedIndexes).map {
            feedItem(episode: $0, series: series)
        }
    }

    static func progress(
        for episode: Episode,
        positionSec: Double,
        completed: Bool = false
    ) -> WatchProgress {
        WatchProgress(
            episodeId: episode.id,
            seriesId: episode.seriesId,
            positionSec: positionSec,
            durationSec: Double(episode.durationSec),
            completed: completed,
            watchedAt: Date(timeIntervalSince1970: 500)
        )
    }
}

// MARK: - Kayıt tutan feed havuz sahtesi

/// `FeedPlaybackPooling` sahtesi: çağrı sırasını kaydeder, bölüm başına
/// FakeVideoPlaying'li GERÇEK PlaybackEngine üzerinden handle döner —
/// direktörün oynatma kontrolü (play/pause/seek/rate) backend'de gözlemlenir.
final class RecordingFeedPool: FeedPlaybackPooling, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case activate(EpisodeID, feedIndex: Int, resumePosition: Double?)
        case prepareNext(EpisodeID, feedIndex: Int)
        case recycle(ClosedRange<Int>)
        case drain
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var locked: Set<EpisodeID> = []
    private var delayNanoseconds: UInt64 = 0
    private var enginesByEpisode: [EpisodeID: PlaybackEngine] = [:]
    private var backendsByEpisode: [EpisodeID: FakeVideoPlaying] = [:]

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func setLocked(_ episodeIDs: Set<EpisodeID>) {
        lock.withLock { locked = episodeIDs }
    }

    func setActivateDelay(nanoseconds: UInt64) {
        lock.withLock { delayNanoseconds = nanoseconds }
    }

    func backend(for episodeID: EpisodeID) -> FakeVideoPlaying? {
        lock.withLock { backendsByEpisode[episodeID] }
    }

    func engine(for episodeID: EpisodeID) -> PlaybackEngine? {
        lock.withLock { enginesByEpisode[episodeID] }
    }

    func activate(
        _ episode: Episode,
        atFeedIndex feedIndex: Int,
        resumePosition: Double?
    ) async throws -> PlaybackHandle {
        lock.withLock {
            recorded.append(.activate(episode.id, feedIndex: feedIndex, resumePosition: resumePosition))
        }
        let delay = lock.withLock { delayNanoseconds }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        let isLocked = lock.withLock { locked.contains(episode.id) }
        if isLocked {
            throw AppError.content(.episodeLocked(EpisodeLockDetails(
                unlockPrice: episode.access.unlockPrice,
                adUnlockEligible: episode.access.adUnlockEligible,
                wallet: nil
            )))
        }
        let engine = lock.withLock { enginesByEpisode[episode.id] }
        if let engine {
            return PlaybackHandle(episodeID: episode.id, engine: engine)
        }
        let backend = FakeVideoPlaying()
        let freshEngine = PlaybackEngine(backend: backend)
        lock.withLock {
            backendsByEpisode[episode.id] = backend
            enginesByEpisode[episode.id] = freshEngine
        }
        await freshEngine.prepare(
            episodeID: episode.id,
            url: URL(string: "https://cdn.test/\(episode.id.rawValue)/master.m3u8")!,
            bufferPolicy: .active,
            resumePosition: nil
        )
        await freshEngine.play() // pendingPlay: ilk karede başlar (aktivasyon semantiği)
        return PlaybackHandle(episodeID: episode.id, engine: freshEngine)
    }

    func prepareNext(_ episode: Episode, atFeedIndex feedIndex: Int) async {
        lock.withLock { recorded.append(.prepareNext(episode.id, feedIndex: feedIndex)) }
    }

    func recycle(keeping window: ClosedRange<Int>) async {
        lock.withLock { recorded.append(.recycle(window)) }
    }

    func drain(keepPlayers _: Bool) async {
        lock.withLock { recorded.append(.drain) }
    }
}

// MARK: - Kayıt tutan prefetch sahtesi

final class RecordingFeedPrefetcher: FeedPrefetching, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case windowChanged(activeIndex: Int, episodeCount: Int, direction: ScrollDirection)
        case cancelAll
    }

    private let lock = NSLock()
    private var recorded: [Call] = []

    var calls: [Call] {
        lock.withLock { recorded }
    }

    func windowChanged(
        activeIndex: Int,
        episodes: [Episode],
        direction: ScrollDirection,
        at _: Date
    ) async {
        lock.withLock {
            recorded.append(.windowChanged(
                activeIndex: activeIndex,
                episodeCount: episodes.count,
                direction: direction
            ))
        }
    }

    func cancelAll() async {
        lock.withLock { recorded.append(.cancelAll) }
    }
}

// MARK: - Prefetch ölçüm kaydedicisi

final class RecordingPrefetchMeasurer: PrefetchMeasuring, @unchecked Sendable {
    struct Record: Equatable, Sendable {
        let episodeID: EpisodeID
        let approximateBytes: Int64
        let approximateSeconds: Double
    }

    private let lock = NSLock()
    private var recorded: [Record] = []

    var records: [Record] {
        lock.withLock { recorded }
    }

    func recordWarmupCompleted(
        episodeID: EpisodeID,
        approximateBytes: Int64,
        approximateSeconds: Double
    ) async {
        lock.withLock {
            recorded.append(Record(
                episodeID: episodeID,
                approximateBytes: approximateBytes,
                approximateSeconds: approximateSeconds
            ))
        }
    }
}
