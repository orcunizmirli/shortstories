import AppFoundation
import Foundation
import Testing
@testable import LibraryKit

@Suite("ContinueWatchingService (SS-122: tek kaynak + senkron)")
struct ContinueWatchingServiceTests {
    private func makeRepo() throws -> any WatchHistoryRepository {
        try PersistenceStore(inMemory: true).makeWatchHistoryRepository()
    }

    private func makeService(
        repo: any WatchHistoryRepository,
        remoting: FakeWatchProgressRemoting = FakeWatchProgressRemoting()
    ) -> ContinueWatchingService {
        ContinueWatchingService(repository: repo, remoting: remoting)
    }

    @Test func recordThenReadRoundTrips() async throws {
        let service = try makeService(repo: makeRepo())
        try await service.recordProgress(
            episodeID: EpisodeID("e-1"),
            seriesID: SeriesID("s-1"),
            positionSec: 42,
            durationSec: 120,
            completed: false,
            at: Date(timeIntervalSince1970: 500)
        )

        let read = try await service.progress(forEpisode: EpisodeID("e-1"))
        #expect(read?.positionSec == 42)
        #expect(read?.progressFraction == 42.0 / 120.0)
        // Optimistik yerel yazma kuyruğa girdi.
        #expect(try await service.pendingUploadCount() == 1)
    }

    @Test func latestProgressForSeriesPicksMostRecent() async throws {
        let service = try makeService(repo: makeRepo())
        try await service.recordProgress(Fixtures.progress(episode: "e-1", series: "s-1", at: 1000))
        try await service.recordProgress(Fixtures.progress(episode: "e-2", series: "s-1", at: 3000))
        try await service.recordProgress(Fixtures.progress(episode: "e-3", series: "s-1", at: 2000))

        let latest = try await service.latestProgress(forSeries: SeriesID("s-1"))
        #expect(latest?.episodeID == EpisodeID("e-2"))
    }

    @Test func latestProgressNilWhenNeverWatched() async throws {
        let service = try makeService(repo: makeRepo())
        #expect(try await service.latestProgress(forSeries: SeriesID("s-x")) == nil)
    }

    @Test func continueWatchingExcludesCompletedNewestFirst() async throws {
        let service = try makeService(repo: makeRepo())
        try await service.recordProgress(Fixtures.progress(episode: "e-old", at: 1000))
        try await service.recordProgress(Fixtures.progress(episode: "e-new", at: 3000))
        try await service.recordProgress(Fixtures.progress(episode: "e-done", completed: true, at: 9000))

        let list = try await service.continueWatching()
        #expect(list.map(\.episodeID) == [EpisodeID("e-new"), EpisodeID("e-old")])
    }

    @Test func synchronizeUploadsPendingThenMarksSynced() async throws {
        let repo = try makeRepo()
        let remoting = FakeWatchProgressRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.recordProgress(Fixtures.progress(episode: "e-1", at: 1000))
        try await service.recordProgress(Fixtures.progress(episode: "e-2", at: 2000))

        try await service.synchronize()

        #expect(Set(remoting.uploadedEpisodeIDs) == [EpisodeID("e-1"), EpisodeID("e-2")])
        #expect(try await service.pendingUploadCount() == 0)
    }

    @Test func synchronizeMergesServerProgress() async throws {
        let repo = try makeRepo()
        let remoting = FakeWatchProgressRemoting(server: [
            Fixtures.progress(episode: "e-server", series: "s-2", position: 80, at: 5000)
        ])
        let service = makeService(repo: repo, remoting: remoting)

        try await service.synchronize()

        let read = try await service.progress(forEpisode: EpisodeID("e-server"))
        #expect(read?.positionSec == 80)
        // Sunucudan gelen kayıt pending İŞARETLENMEZ.
        #expect(try await service.pendingUploadCount() == 0)
    }

    /// WP-F1-G bulgu #1 (davranışsal): upload'ın `await`'i sırasında araya giren daha yeni bir
    /// yerel yazma (reentrancy) kaybolmamalı. Kırık markSynced yüklenen ESKİ anlık görüntüye
    /// kördür → t2'yi synced işaretler → t2 hiç yüklenmez ve merge onu sunucunun t1'iyle ezer.
    @Test func synchronizeDoesNotLoseWriteThatRacesUpload() async throws {
        let repo = try makeRepo()
        // Sunucu hâlâ ESKİ t1'i tutuyor (yüklenen buydu); kırık yol merge'de bunu geri döndürür.
        let remoting = FakeWatchProgressRemoting(server: [
            Fixtures.progress(episode: "e-1", series: "s-1", position: 10, at: 1000)
        ])
        let service = makeService(repo: repo, remoting: remoting)
        // t1: pendingUpload.
        try await service.recordProgress(Fixtures.progress(episode: "e-1", series: "s-1", position: 10, at: 1000))
        // Upload uçarken (await) reentrant daha yeni yazma t2 araya girer.
        remoting.setOnUpload { _ in
            try? await service.recordProgress(
                Fixtures.progress(episode: "e-1", series: "s-1", position: 99, at: 2000)
            )
        }

        try await service.synchronize()

        // t2 kaybolmamalı: yerel değer 99 kalmalı ve hâlâ pendingUpload (sonraki tur yükler).
        let read = try await service.progress(forEpisode: EpisodeID("e-1"))
        #expect(read?.positionSec == 99)
        #expect(try await service.pendingUploadCount() == 1)
    }

    /// App-integration hunt #4 (coalescing): bir senkron uçarken gelen İKİNCİ `synchronize()` (ör. hesap-switch
    /// refetch'i görünür Listem sync'iyle çakışınca) DÜŞMEMELİ — aksi halde B'nin pull'u atlanır (bayat veri).
    /// `needsResync` ile mevcut tur bir kez daha koşar → `fetchServerProgress` İKİ kez çağrılır (fix'siz: 1).
    @Test func synchronizeCoalescesOverlappingCallInsteadOfDropping() async throws {
        let repo = try makeRepo()
        let remoting = FakeWatchProgressRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.recordProgress(Fixtures.progress(episode: "e-1", at: 1000)) // pending → upload çalışır

        // A'nın upload'ı uçarken (deterministik askı noktası) B'nin synchronize'ı gelir (reentrant).
        remoting.setOnUpload { _ in
            try? await service.synchronize() // B: isSyncing=true → coalescing (needsResync), erken döner
        }

        try await service.synchronize() // A

        // Coalescing: A ikinci turu koşar → fetch 2 kez. Fix'siz (guard düşürür): B kaybolur → fetch 1 kez.
        #expect(remoting.fetchServerProgressCallCount == 2)
    }

    @Test func offlineKeepsPendingAndDoesNotThrow() async throws {
        let repo = try makeRepo()
        let remoting = FakeWatchProgressRemoting(uploadError: .network(.offline))
        let service = makeService(repo: repo, remoting: remoting)
        try await service.recordProgress(Fixtures.progress(episode: "e-1", at: 1000))

        try await service.synchronize()

        #expect(remoting.uploadedBatches.isEmpty)
        #expect(try await service.pendingUploadCount() == 1)
    }
}
