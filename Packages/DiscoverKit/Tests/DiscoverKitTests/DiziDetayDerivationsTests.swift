import ContentKit
import Foundation
import Testing
@testable import DiscoverKit

@Suite("ContinueWatchingTarget")
struct ContinueWatchingTargetTests {
    private func episodes(_ count: Int) -> [Episode] {
        (1 ... count).map { Fixtures.episode(seriesID: "srs_abc123", index: $0) }
    }

    private func series(released: Int = 8) -> Series {
        Fixtures.series(id: "srs_abc123", episodeCount: 60, releasedEpisodeCount: released)
    }

    @Test func noHistoryStartsAtFirstEpisode() {
        let target = ContinueWatchingTarget.resolve(series: series(), episodes: episodes(8), progress: nil)
        #expect(target == ContinueWatchingTarget(kind: .start, episodeNumber: 1, startPositionSec: 0))
    }

    @Test func inProgressResumesAtSameEpisode() {
        let progress = Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 3, positionSec: 42, completed: false)
        let target = ContinueWatchingTarget.resolve(series: series(), episodes: episodes(8), progress: progress)
        #expect(target == ContinueWatchingTarget(kind: .resume, episodeNumber: 3, startPositionSec: 42))
    }

    @Test func completedAdvancesToNextEpisode() {
        let progress = Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 3, completed: true)
        let target = ContinueWatchingTarget.resolve(series: series(), episodes: episodes(8), progress: progress)
        #expect(target == ContinueWatchingTarget(kind: .resume, episodeNumber: 4, startPositionSec: 0))
    }

    @Test func completedAtLastReleasedStaysThere() {
        let progress = Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 8, completed: true)
        let target = ContinueWatchingTarget.resolve(series: series(released: 8), episodes: episodes(8), progress: progress)
        #expect(target == ContinueWatchingTarget(kind: .resume, episodeNumber: 8, startPositionSec: 0))
    }

    @Test func progressEpisodeNotLoadedFallsBackToStart() {
        let progress = Fixtures.progress(seriesID: "srs_abc123", episodeIndex: 99, completed: false)
        let target = ContinueWatchingTarget.resolve(series: series(), episodes: episodes(8), progress: progress)
        #expect(target.kind == .start)
    }
}

@Suite("EpisodeCellState")
struct EpisodeCellStateTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func published() -> Episode {
        Fixtures.episode(
            seriesID: "srs_abc123",
            index: 5,
            access: .locked,
            unlockPrice: 70,
            publishedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
    }

    @Test func unpublishedIsScheduledRegardlessOfAccess() {
        let future = Fixtures.episode(
            seriesID: "srs_abc123",
            index: 5,
            access: .free,
            publishedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let state = EpisodeCellState.resolve(episode: future, isWatched: false, isCurrent: true, isAccessible: true, now: now)
        #expect(state == .scheduled)
    }

    @Test func lockedTakesPrecedenceOverCurrent() {
        let state = EpisodeCellState.resolve(
            episode: published(),
            isWatched: false,
            isCurrent: true,
            isAccessible: false,
            now: now
        )
        #expect(state == .locked(price: 70))
    }

    @Test func currentBeforeWatched() {
        let episode = Fixtures.episode(seriesID: "srs_abc123", index: 3, access: .free)
        let state = EpisodeCellState.resolve(episode: episode, isWatched: true, isCurrent: true, isAccessible: true, now: now)
        #expect(state == .current)
    }

    @Test func watchedThenAvailable() {
        let episode = Fixtures.episode(seriesID: "srs_abc123", index: 2, access: .free)
        #expect(EpisodeCellState
            .resolve(episode: episode, isWatched: true, isCurrent: false, isAccessible: true, now: now) == .watched)
        #expect(EpisodeCellState
            .resolve(episode: episode, isWatched: false, isCurrent: false, isAccessible: true, now: now) == .available)
    }
}

@Suite("ReleaseScheduleInfo")
struct ReleaseScheduleInfoTests {
    @Test func completedSeries() {
        let series = Fixtures.series(id: "srs_abc123", releaseState: .completed)
        #expect(ReleaseScheduleInfo.resolve(series: series) == .completed)
    }

    @Test func ongoingWithDateIsScheduled() {
        let date = Date(timeIntervalSince1970: 1_609_459_200) // 2021-01-01 (Cuma, UTC)
        let series = Fixtures.series(id: "srs_abc123", releaseState: .ongoing, nextEpisodeAt: date)
        #expect(ReleaseScheduleInfo.resolve(series: series) == .ongoingScheduled(nextEpisodeAt: date))
    }

    @Test func ongoingWithoutDateIsUnknown() {
        let series = Fixtures.series(id: "srs_abc123", releaseState: .ongoing, nextEpisodeAt: nil)
        #expect(ReleaseScheduleInfo.resolve(series: series) == .ongoingUnknown)
    }

    @Test func weekdayNameForKnownFriday() {
        let date = Date(timeIntervalSince1970: 1_609_459_200) // 2021-01-01 = Friday
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        calendar.locale = Locale(identifier: "en_US")
        let info = ReleaseScheduleInfo.ongoingScheduled(nextEpisodeAt: date)
        #expect(info.newEpisodeWeekday(calendar: calendar) == "Friday")
        #expect(ReleaseScheduleInfo.completed.newEpisodeWeekday(calendar: calendar) == nil)
    }
}

@Suite("EpisodeBlocks")
struct EpisodeBlocksTests {
    @Test func noTabsWhenAtOrBelowBlockSize() {
        #expect(EpisodeBlocks.make(episodeCount: 30).isEmpty)
        #expect(EpisodeBlocks.make(episodeCount: 12).isEmpty)
    }

    @Test func twoBlocksForSixty() {
        let blocks = EpisodeBlocks.make(episodeCount: 60)
        #expect(blocks.map(\.title) == ["1-30", "31-60"])
        #expect(blocks[1].range == 31 ... 60)
    }

    @Test func partialTrailingBlock() {
        let blocks = EpisodeBlocks.make(episodeCount: 61)
        #expect(blocks.map(\.title) == ["1-30", "31-60", "61-61"])
    }
}
