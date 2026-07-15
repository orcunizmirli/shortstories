import AppFoundation
import Foundation
import Testing
@testable import LibraryKit

@Suite("MyListSegment (saf)")
struct MyListSegmentTests {
    @Test func downloadsHiddenByDefault() {
        #expect(MyListSegment.visible(downloadsEnabled: false) == [.favorites, .continueWatching])
    }

    @Test func downloadsShownWhenFlagOn() {
        #expect(MyListSegment.visible(downloadsEnabled: true) == [.favorites, .continueWatching, .downloads])
    }

    @Test func analyticsValuesAreCanonical() {
        #expect(MyListSegment.favorites.analyticsValue == "favorites")
        #expect(MyListSegment.continueWatching.analyticsValue == "continue")
        #expect(MyListSegment.downloads.analyticsValue == "downloads")
    }
}

@Suite("FavoriteSyncQueue (saf çevrimdışı kuyruk)")
struct FavoriteSyncQueueTests {
    @Test func mapsPendingAddToPutAndPendingRemoveToDelete() {
        let pending = [
            PendingFavoriteSync(seriesID: SeriesID("a"), state: .pendingAdd),
            PendingFavoriteSync(seriesID: SeriesID("b"), state: .pendingRemove)
        ]
        #expect(FavoriteSyncQueue.operations(for: pending) == [.put(SeriesID("a")), .delete(SeriesID("b"))])
    }

    @Test func syncedEntriesAreDropped() {
        let pending = [
            PendingFavoriteSync(seriesID: SeriesID("a"), state: .synced),
            PendingFavoriteSync(seriesID: SeriesID("b"), state: .pendingAdd)
        ]
        #expect(FavoriteSyncQueue.operations(for: pending) == [.put(SeriesID("b"))])
    }

    @Test func emptyQueueYieldsNoOperations() {
        #expect(FavoriteSyncQueue.operations(for: []).isEmpty)
    }
}

@Suite("RelativeDay (saf)")
struct RelativeDayTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func day(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        // swiftlint:disable:next force_unwrapping
        return formatter.date(from: iso)!
    }

    @Test func sameDayIsToday() {
        let now = day("2026-07-15T20:00:00Z")
        let earlier = day("2026-07-15T06:00:00Z")
        #expect(RelativeDay.between(earlier, and: now, calendar: calendar) == .today)
    }

    @Test func previousCalendarDayIsYesterday() {
        let now = day("2026-07-15T01:00:00Z")
        let past = day("2026-07-14T23:00:00Z")
        #expect(RelativeDay.between(past, and: now, calendar: calendar) == .yesterday)
    }

    @Test func threeDaysAgoBucket() {
        let now = day("2026-07-15T12:00:00Z")
        let past = day("2026-07-12T12:00:00Z")
        #expect(RelativeDay.between(past, and: now, calendar: calendar) == .daysAgo(3))
    }

    @Test func twoWeeksAgoBucket() {
        let now = day("2026-07-15T12:00:00Z")
        let past = day("2026-07-01T12:00:00Z")
        #expect(RelativeDay.between(past, and: now, calendar: calendar) == .weeksAgo(2))
    }

    @Test func overFourWeeksIsLongAgo() {
        let now = day("2026-07-15T12:00:00Z")
        let past = day("2026-05-15T12:00:00Z")
        #expect(RelativeDay.between(past, and: now, calendar: calendar) == .longAgo)
    }

    @Test func futureTimestampClampsToToday() {
        let now = day("2026-07-15T10:00:00Z")
        let future = day("2026-07-16T10:00:00Z")
        #expect(RelativeDay.between(future, and: now, calendar: calendar) == .today)
    }
}

@Suite("ContinueWatchingItem (saf türetim)")
struct ContinueWatchingItemTests {
    @Test func joinsRecordWithCatalogInfo() {
        let record = Fixtures.progress(episode: "e-1", series: "s-1", position: 62, duration: 100, at: 1000)
        let item = ContinueWatchingItem.make(record: record, info: Fixtures.info("s-1", title: "İntikam"), episodeNumber: 7)

        #expect(item.seriesTitle == "İntikam")
        #expect(item.episodeNumber == 7)
        #expect(item.positionSec == 62)
        #expect(item.progressPercent == 62)
        #expect(item.isAvailable)
    }

    @Test func missingCatalogInfoMarksUnavailable() {
        let record = Fixtures.progress(episode: "e-1", at: 1000)
        let item = ContinueWatchingItem.make(record: record, info: nil, episodeNumber: nil)

        #expect(item.seriesTitle.isEmpty)
        #expect(item.coverURL == nil)
        #expect(item.episodeNumber == nil)
        #expect(item.isAvailable == false)
    }

    @Test func progressPercentRoundsAndClamps() {
        let over = Fixtures.progress(episode: "e-1", position: 150, duration: 100, at: 1000)
        #expect(ContinueWatchingItem.make(record: over, info: nil, episodeNumber: nil).progressPercent == 100)

        let partial = Fixtures.progress(episode: "e-2", position: 1, duration: 3, at: 1000)
        #expect(ContinueWatchingItem.make(record: partial, info: nil, episodeNumber: nil).progressPercent == 33)
    }

    @Test func favoriteItemJoin() {
        let record = FavoriteRecord(seriesID: SeriesID("s-1"), addedAt: Date(timeIntervalSince1970: 500))
        let item = FavoriteItem.make(record: record, info: Fixtures.info("s-1", title: "CEO"))
        #expect(item.title == "CEO")
        #expect(item.isAvailable)
        #expect(item.addedAt == Date(timeIntervalSince1970: 500))
    }
}
