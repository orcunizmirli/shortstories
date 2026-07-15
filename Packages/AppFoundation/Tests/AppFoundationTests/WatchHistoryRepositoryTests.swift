import Foundation
import Testing
@testable import AppFoundation

struct WatchHistoryRepositoryTests {
    private func makeRepo() throws -> any WatchHistoryRepository {
        try PersistenceStore(inMemory: true).makeWatchHistoryRepository()
    }

    private func record(
        _ episode: String,
        series: String = "s-1",
        position: Double = 10,
        duration: Double = 100,
        completed: Bool = false,
        at seconds: TimeInterval
    ) -> WatchProgressRecord {
        WatchProgressRecord(
            episodeID: EpisodeID(episode),
            seriesID: SeriesID(series),
            positionSec: position,
            durationSec: duration,
            completed: completed,
            watchedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test func saveThenReadRoundTrips() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", position: 42, duration: 120, at: 500))

        let read = try await repo.progress(forEpisode: EpisodeID("ep-1"))
        #expect(read?.episodeID == EpisodeID("ep-1"))
        #expect(read?.positionSec == 42)
        #expect(read?.durationSec == 120)
        #expect(read?.progressFraction == 42.0 / 120.0)
    }

    @Test func missingEpisodeReturnsNil() async throws {
        let repo = try makeRepo()
        let read = try await repo.progress(forEpisode: EpisodeID("nope"))
        #expect(read == nil)
    }

    @Test func saveIsUpsertWithLastWriteWins() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", position: 10, at: 1000))
        // Daha yeni yazma kazanır.
        try await repo.saveProgress(record("ep-1", position: 55, at: 2000))
        // Eski yazma yok sayılır (watchedAt daha eski).
        try await repo.saveProgress(record("ep-1", position: 5, at: 500))

        let read = try await repo.progress(forEpisode: EpisodeID("ep-1"))
        #expect(read?.positionSec == 55)

        // Tek kayıt kalmalı (upsert).
        let all = try await repo.progress(forSeries: SeriesID("s-1"))
        #expect(all.count == 1)
    }

    @Test func saveMarksPendingUpload() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", at: 1000))
        let pending = try await repo.pendingUploads()
        #expect(pending.map(\.episodeID) == [EpisodeID("ep-1")])
    }

    @Test func markSyncedClearsPending() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", at: 1000))
        try await repo.saveProgress(record("ep-2", at: 1100))
        try await repo.markSynced(uploaded: [record("ep-1", at: 1000)])

        let pending = try await repo.pendingUploads()
        #expect(pending.map(\.episodeID) == [EpisodeID("ep-2")])
    }

    /// WP-F1-G bulgu #1: markSynced watchedAt-körü veri kaybı (store-katmanı guard'ı).
    /// upload'ın `await`'i sırasında araya giren daha yeni bir yerel yazma (watchedAt ilerledi),
    /// yüklenen ESKİ anlık görüntüyle `markSynced` çağrılınca yanlışlıkla `synced` işaretlenmemeli;
    /// aksi halde o yazma hiç yüklenmez ve sonraki merge onu sunucunun eskisiyle ezer.
    @Test func markSyncedSkipsEntityNewerThanUploadedSnapshot() async throws {
        let repo = try makeRepo()
        // Yerel kayıt t2'ye ilerledi (upload uçarken gelen reentrant yazma).
        try await repo.saveProgress(record("ep-1", position: 99, at: 2000))
        // Yüklenen anlık görüntü ESKİ t1'di → guard: t2 daha yeni, synced YAPMA.
        try await repo.markSynced(uploaded: [record("ep-1", position: 10, at: 1000)])

        // t2 hâlâ pendingUpload olmalı (bir sonraki tur yükler) ve değeri korunmalı.
        #expect(try await repo.pendingUploads().map(\.episodeID) == [EpisodeID("ep-1")])
        #expect(try await repo.progress(forEpisode: EpisodeID("ep-1"))?.positionSec == 99)
    }

    /// Yüklenen anlık görüntü kaydın GÜNCEL hâliyse (watchedAt aynı) normalde synced yapılır.
    @Test func markSyncedClearsWhenUploadedSnapshotIsCurrent() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", position: 42, at: 1000))
        try await repo.markSynced(uploaded: [record("ep-1", position: 42, at: 1000)])
        #expect(try await repo.pendingUploads().isEmpty)
    }

    @Test func mergeServerProgressDoesNotMarkPending() async throws {
        let repo = try makeRepo()
        try await repo.mergeServerProgress([record("ep-1", position: 30, at: 2000)])
        let pending = try await repo.pendingUploads()
        #expect(pending.isEmpty)
        let read = try await repo.progress(forEpisode: EpisodeID("ep-1"))
        #expect(read?.positionSec == 30)
    }

    @Test func mergeKeepsNewerLocalPendingRecord() async throws {
        let repo = try makeRepo()
        // Yerel pendingUpload, sunucudan daha yeni.
        try await repo.saveProgress(record("ep-1", position: 90, at: 5000))
        // Sunucu birleşik listesi daha eski → yerel korunur.
        try await repo.mergeServerProgress([record("ep-1", position: 20, at: 1000)])

        let read = try await repo.progress(forEpisode: EpisodeID("ep-1"))
        #expect(read?.positionSec == 90)
        // Yerel hâlâ pendingUpload olmalı.
        let pending = try await repo.pendingUploads()
        #expect(pending.map(\.episodeID) == [EpisodeID("ep-1")])
    }

    @Test func mergeOverwritesOlderLocalRecord() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", position: 20, at: 1000))
        // Sunucu daha yeni → yerel ezilir ve synced olur.
        try await repo.mergeServerProgress([record("ep-1", position: 88, at: 9000)])

        let read = try await repo.progress(forEpisode: EpisodeID("ep-1"))
        #expect(read?.positionSec == 88)
        let pending = try await repo.pendingUploads()
        #expect(pending.isEmpty)
    }

    @Test func continueWatchingExcludesCompletedAndSortsByRecency() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-old", at: 1000))
        try await repo.saveProgress(record("ep-new", at: 3000))
        try await repo.saveProgress(record("ep-mid", at: 2000))
        try await repo.saveProgress(record("ep-done", completed: true, at: 9000))

        let list = try await repo.continueWatching(limit: 0)
        #expect(list.map(\.episodeID) == [EpisodeID("ep-new"), EpisodeID("ep-mid"), EpisodeID("ep-old")])
    }

    @Test func continueWatchingRespectsLimit() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", at: 1000))
        try await repo.saveProgress(record("ep-2", at: 2000))
        try await repo.saveProgress(record("ep-3", at: 3000))

        let list = try await repo.continueWatching(limit: 2)
        #expect(list.map(\.episodeID) == [EpisodeID("ep-3"), EpisodeID("ep-2")])
    }

    @Test func progressForSeriesReturnsOnlyMatchingSeries() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("ep-1", series: "s-1", at: 1000))
        try await repo.saveProgress(record("ep-2", series: "s-2", at: 1100))
        try await repo.saveProgress(record("ep-3", series: "s-1", at: 1200))

        let list = try await repo.progress(forSeries: SeriesID("s-1"))
        #expect(Set(list.map(\.episodeID)) == [EpisodeID("ep-1"), EpisodeID("ep-3")])
    }

    /// WP-F1-G bulgu #11: bir dizinin EN GÜNCEL kaydı hedefli sorgu ile döner (seriesId
    /// predikatı + watchedAt azalan + fetchLimit 1) — tüm kayıtları çekip `.max` etmez. Yalnız
    /// hedef diziyi süzer (başka dizinin daha yeni kaydı sonucu KİRLETMEZ) ve tamamlanmış
    /// bölümleri de kapsar (DiziDetay "Devam Et" CTA'sı için en güncel her hâlde).
    @Test func latestProgressForSeriesReturnsMostRecentViaTargetedQuery() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("e-1", series: "s-1", at: 1000))
        try await repo.saveProgress(record("e-2", series: "s-1", at: 3000))
        try await repo.saveProgress(record("e-3", series: "s-1", at: 2000))
        // Başka diziden daha yeni bir kayıt hedef sonucu etkilememeli.
        try await repo.saveProgress(record("e-other", series: "s-2", at: 9000))

        let latest = try await repo.latestProgress(forSeries: SeriesID("s-1"))
        #expect(latest?.episodeID == EpisodeID("e-2"))
        #expect(latest?.watchedAt == Date(timeIntervalSince1970: 3000))
    }

    @Test func latestProgressForSeriesNilWhenNeverWatched() async throws {
        let repo = try makeRepo()
        try await repo.saveProgress(record("e-1", series: "s-1", at: 1000))
        #expect(try await repo.latestProgress(forSeries: SeriesID("s-none")) == nil)
    }
}
