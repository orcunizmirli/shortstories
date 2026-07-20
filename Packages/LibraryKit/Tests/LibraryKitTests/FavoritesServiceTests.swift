import AppFoundation
import Foundation
import Testing
@testable import LibraryKit

@Suite("FavoritesService (SS-121: optimistik + çevrimdışı kuyruk senkron)")
struct FavoritesServiceTests {
    private func makeRepo() throws -> any FavoritesRepository {
        try PersistenceStore(inMemory: true).makeFavoritesRepository()
    }

    private func makeService(
        repo: any FavoritesRepository,
        remoting: FakeFavoritesRemoting = FakeFavoritesRemoting()
    ) -> FavoritesService {
        FavoritesService(repository: repo, remoting: remoting)
    }

    @Test func addIsOptimisticLocalAndReadable() async throws {
        let service = try makeService(repo: makeRepo())
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))

        #expect(try await service.isFavorite(SeriesID("s-1")))
        #expect(try await service.favorites().map(\.seriesID) == [SeriesID("s-1")])
        // Ekleme kuyruğa yazıldı (henüz senkron edilmedi).
        #expect(try await service.pendingSyncCount() == 1)
    }

    @Test func toggleReturnsNewState() async throws {
        let service = try makeService(repo: makeRepo())
        let on = try await service.toggleFavorite(SeriesID("s-1"))
        #expect(on)
        let off = try await service.toggleFavorite(SeriesID("s-1"))
        #expect(off == false)
        #expect(try await service.isFavorite(SeriesID("s-1")) == false)
    }

    @Test func synchronizeSendsPendingAddThenConfirms() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))

        try await service.synchronize()

        #expect(remoting.putCalls == [SeriesID("s-1")])
        // Onaylandı → kuyruk boş, favori synced kaldı.
        #expect(try await service.pendingSyncCount() == 0)
        #expect(try await service.isFavorite(SeriesID("s-1")))
    }

    @Test func synchronizeSendsPendingRemoveThenDeletes() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        // Önce ekle + senkron (synced), sonra çıkar (pendingRemove).
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await service.synchronize()
        try await service.setFavorite(false, seriesID: SeriesID("s-1"))

        #expect(try await service.pendingSyncCount() == 1)
        try await service.synchronize()

        #expect(remoting.deleteCalls == [SeriesID("s-1")])
        #expect(try await service.pendingSyncCount() == 0)
        #expect(try await service.favorites().isEmpty)
    }

    @Test func offlineKeepsQueueAndDoesNotThrow() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting(error: .network(.offline))
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))

        // Çevrimdışı: sessizce ertelenir (throw yok), kuyruk korunur.
        try await service.synchronize()

        #expect(remoting.putCalls.isEmpty)
        #expect(try await service.pendingSyncCount() == 1)
        #expect(try await service.isFavorite(SeriesID("s-1")))
    }

    @Test func queueDrainsAfterConnectivityReturns() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting(error: .network(.offline))
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await service.synchronize() // offline, kuyrukta kalır

        remoting.setError(nil) // bağlantı döndü
        try await service.synchronize()

        #expect(remoting.putCalls == [SeriesID("s-1")])
        #expect(try await service.pendingSyncCount() == 0)
    }

    // MARK: - WP-F1-G sync yarışları (veri-kaybı / açlık regresyonları)

    /// Bulgu #2: offline-DIŞI kalıcı hata (404) tüm döngüyü bloklamamalı. Hatalı işlem pending
    /// bırakılır ve SONRAKİ işlemlere devam edilir (head-of-line blocking + kuyruk açlığı yok).
    @Test func nonOfflineErrorIsIsolatedAndDoesNotBlockRestOfQueue() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-blocked"), at: Date(timeIntervalSince1970: 1000))
        try await service.setFavorite(true, seriesID: SeriesID("s-ok"), at: Date(timeIntervalSince1970: 2000))
        remoting.setError(for: SeriesID("s-blocked"), .content(.notFound))

        // Kalıcı hata dışarı sızmamalı ve ikinci işlem yine de gönderilmeli.
        try await service.synchronize()

        #expect(remoting.putCalls == [SeriesID("s-ok")])
        #expect(try await service.isFavorite(SeriesID("s-ok")))
        // s-blocked hâlâ kuyrukta (pending), s-ok senkronlandı → açlık yok.
        let pending = try await repo.pendingSync()
        #expect(pending.map(\.seriesID) == [SeriesID("s-blocked")])
        #expect(pending.map(\.state) == [.pendingAdd])
    }

    /// Bulgu #3: PUT uçarken araya giren removeFavorite silme niyetini kaybetmemeli. Bayat
    /// pending ile PUT gider, reentrant remove yerel pendingAdd'i siler → sunucuda hayalet
    /// favori kalır. Telafi DELETE üretilerek niyet korunmalı.
    @Test func removalDuringInFlightAddIssuesCompensatingDelete() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        remoting.setOnPut { series in
            if series == SeriesID("s-1") {
                try? await service.setFavorite(false, seriesID: SeriesID("s-1"))
            }
        }

        try await service.synchronize()

        // PUT sonrası hayaleti temizleyen telafi DELETE gitmiş olmalı.
        #expect(remoting.putCalls == [SeriesID("s-1")])
        #expect(remoting.deleteCalls == [SeriesID("s-1")])
        #expect(try await service.isFavorite(SeriesID("s-1")) == false)
        #expect(try await service.pendingSyncCount() == 0)
    }

    /// Bulgu #4: senkron sürerken snapshot'tan SONRA eklenen işlem AYNI çağrıda gönderilmeli
    /// (dirty/needsResync retry); yeni tetikleme beklemeden kuyruk açlığı olmamalı.
    @Test func favoriteAddedDuringSyncIsFlushedInSameCall() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        remoting.setOnPut { series in
            if series == SeriesID("s-1") {
                try? await service.setFavorite(true, seriesID: SeriesID("s-2"), at: Date(timeIntervalSince1970: 2000))
            }
        }

        try await service.synchronize()

        #expect(Set(remoting.putCalls) == [SeriesID("s-1"), SeriesID("s-2")])
        #expect(try await service.pendingSyncCount() == 0)
    }

    // MARK: - Batch kaldırma (WP-F1-G ertelenen opt: N kaldırma → tek serileştirilmiş yazma)

    /// N favori TEK batch repository çağrısıyla (tekil `removeFavorite` HİÇ çağrılmadan) optimistik
    /// kaldırılır; hepsi görünmez olur ve `pendingRemove` olarak kuyruğa girer.
    @Test func removeFavoritesRemovesAllInSingleRepositoryCall() async throws {
        let counting = try CountingFavoritesRepository(base: makeRepo())
        let service = makeService(repo: counting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await service.setFavorite(true, seriesID: SeriesID("s-2"), at: Date(timeIntervalSince1970: 2000))
        try await service.setFavorite(true, seriesID: SeriesID("s-3"), at: Date(timeIntervalSince1970: 3000))
        try await service.synchronize() // synced

        try await service.removeFavorites([SeriesID("s-1"), SeriesID("s-2"), SeriesID("s-3")])

        #expect(counting.removeFavoritesCalls == 1)
        #expect(counting.removeFavoriteCalls == 0)
        #expect(try await service.favorites().isEmpty)
        let pending = try await service.pendingSyncCount()
        #expect(pending == 3)
    }

    /// Boş küme no-op: repository'ye hiç yazma gitmez, kuyruk değişmez.
    @Test func removeFavoritesEmptySetIsNoOp() async throws {
        let counting = try CountingFavoritesRepository(base: makeRepo())
        let service = makeService(repo: counting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))

        try await service.removeFavorites([])

        #expect(counting.removeFavoritesCalls == 0)
        #expect(try await service.isFavorite(SeriesID("s-1")))
        #expect(try await service.pendingSyncCount() == 1)
    }

    /// `needsResync` doğru: batch kaldırmadan sonra `synchronize()` HER kayıt için DELETE gönderir
    /// ve kuyruğu boşaltır.
    @Test func removeFavoritesThenSyncDeletesEachOnServer() async throws {
        let remoting = FakeFavoritesRemoting()
        let service = try makeService(repo: makeRepo(), remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        try await service.setFavorite(true, seriesID: SeriesID("s-2"), at: Date(timeIntervalSince1970: 2000))
        try await service.synchronize() // synced

        try await service.removeFavorites([SeriesID("s-1"), SeriesID("s-2")])
        try await service.synchronize()

        #expect(Set(remoting.deleteCalls) == [SeriesID("s-1"), SeriesID("s-2")])
        #expect(try await service.pendingSyncCount() == 0)
        #expect(try await service.favorites().isEmpty)
    }

    /// Kısmi başarısızlık izolasyonu: batch ile kaldırılan kayıtlardan biri (kalıcı 404) senkronda
    /// başarısız olsa da DİĞERİ silinir; başarısız olan pending kalır (head-of-line blocking yok).
    @Test func removeFavoritesPartialSyncFailureIsIsolated() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-blocked"), at: Date(timeIntervalSince1970: 1000))
        try await service.setFavorite(true, seriesID: SeriesID("s-ok"), at: Date(timeIntervalSince1970: 2000))
        try await service.synchronize() // synced
        remoting.setError(for: SeriesID("s-blocked"), .content(.notFound))

        try await service.removeFavorites([SeriesID("s-blocked"), SeriesID("s-ok")])
        try await service.synchronize()

        #expect(remoting.deleteCalls == [SeriesID("s-ok")])
        // s-blocked hâlâ pendingRemove (izole), s-ok kalıcı silindi.
        let pending = try await repo.pendingSync()
        #expect(pending.map(\.seriesID) == [SeriesID("s-blocked")])
        #expect(pending.map(\.state) == [.pendingRemove])
        #expect(try await service.favorites().isEmpty)
    }

    /// Telafi deseni KORUNUR: PUT uçarken batch `removeFavorites` araya girerse silme niyeti
    /// kaybolmaz — telafi DELETE ile sunucudaki hayalet favori temizlenir (tekil remove ile aynı).
    @Test func removeFavoritesDuringInFlightAddIssuesCompensatingDelete() async throws {
        let repo = try makeRepo()
        let remoting = FakeFavoritesRemoting()
        let service = makeService(repo: repo, remoting: remoting)
        try await service.setFavorite(true, seriesID: SeriesID("s-1"), at: Date(timeIntervalSince1970: 1000))
        remoting.setOnPut { series in
            if series == SeriesID("s-1") {
                try? await service.removeFavorites([SeriesID("s-1")])
            }
        }

        try await service.synchronize()

        #expect(remoting.putCalls == [SeriesID("s-1")])
        #expect(remoting.deleteCalls == [SeriesID("s-1")])
        #expect(try await service.isFavorite(SeriesID("s-1")) == false)
        #expect(try await service.pendingSyncCount() == 0)
    }

    /// Bulgu #5: eşzamanlı iki toggle atomik olmalı (TOCTOU yok). Net-sıfır: biri açar, diğeri
    /// kapar. Kırık yol her ikisini de bayat okuyup net-tek etki (favori kalır) üretir.
    @Test func concurrentTogglesAreAtomicNetZero() async throws {
        let store = try makeRepo()
        let barrier = TestBarrier(threshold: 2)
        let repo = GatedFavoritesRepository(base: store, isFavoriteBarrier: barrier)
        let service = makeService(repo: repo)

        async let first = service.toggleFavorite(SeriesID("s-1"))
        async let second = service.toggleFavorite(SeriesID("s-1"))
        let results = try await [first, second]

        #expect(Set(results) == [true, false])
        // Son durum base store'dan doğrudan okunur (gated repo bariyerine uğramadan).
        #expect(try await store.isFavorite(SeriesID("s-1")) == false)
        #expect(try await store.pendingSync().isEmpty)
    }
}
