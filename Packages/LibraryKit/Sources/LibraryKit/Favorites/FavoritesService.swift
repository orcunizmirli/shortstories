import AppFoundation
import Foundation

/// Favoriler (Listem) tek kaynak servisi (SS-121). Feed overlay (SS-063), DiziDetay (SS-081) ve
/// Listem (SS-120) bu servisi tüketir — optimistik yerel yazma (SwiftData, `FavoritesRepository`)
/// + çevrimdışı kuyruk + sunucu senkron. `import SwiftData` YOK: yalnız AppFoundation repository
/// protokolü + backend portu görülür.
///
/// Actor: `synchronize()` içinde kuyruk boşaltma tek-uçuşlu (aktör reentrancy guard'ı) —
/// örtüşen senkronlar aynı `PUT/DELETE`'i iki kez göndermez, onaylar yarışmaz. Reentrancy
/// (await askı noktalarında) şöyle ele alınır: (1) işlem-başına hata izolasyonu → tek bir
/// kalıcı hata kuyruğu bloklamaz; (2) uçuştaki bir eklemenin araya girip silinmesi telafi
/// DELETE'i üretir → silme niyeti kaybolmaz; (3) `needsResync` dirty bayrağı → snapshot'tan
/// sonra gelen işlemler aynı çağrıda boşaltılır (kuyruk açlığı yok).
public actor FavoritesService {
    private let repository: any FavoritesRepository
    private let remoting: any FavoritesRemoting
    private let logger: (any Logging)?
    private var isSyncing = false
    /// Sürmekte olan tur bitince bir tur daha koşulması gerektiğini işaretler (bulgu #4):
    /// senkron sürerken gelen yerel yazma / örtüşen `synchronize` çağrısı bunu set eder.
    private var needsResync = false
    /// PUT'u ŞU AN uçuşta olan eklemeler (reentrancy penceresi). Bu pencerede araya giren
    /// bir kaldırma, sunucuda hayalet favori bırakır → telafi DELETE gerekir (bulgu #3).
    private var inFlightAdds: Set<SeriesID> = []
    /// PUT'u uçarken kaldırılan eklemeler: sunucu artık favoriyi tutuyor, DELETE ile temizlenmeli.
    private var compensatingDeletes: Set<SeriesID> = []

    public init(
        repository: any FavoritesRepository,
        remoting: any FavoritesRemoting,
        logger: (any Logging)? = nil
    ) {
        self.repository = repository
        self.remoting = remoting
        self.logger = logger
    }

    // MARK: - Okuma

    /// Görünür favori mi (`pendingRemove` hariç — repository sözleşmesi).
    public func isFavorite(_ seriesID: SeriesID) async throws -> Bool {
        try await repository.isFavorite(seriesID)
    }

    /// Görünür favoriler, en son eklenen önce (`addedAt` azalan).
    public func favorites() async throws -> [FavoriteRecord] {
        try await repository.favorites()
    }

    // MARK: - Optimistik yazma (anında yerel; kuyruk repository'de birikir)

    /// Favori ekle/çıkar. Yerel yazma anında görünür; sunucu senkronu `synchronize()`'a bırakılır.
    public func setFavorite(_ isFavorite: Bool, seriesID: SeriesID, at date: Date = Date()) async throws {
        if isFavorite {
            try await repository.addFavorite(seriesID, at: date)
            noteLocalAdd(seriesID)
        } else {
            try await repository.removeFavorite(seriesID)
            noteLocalRemoval(seriesID)
        }
    }

    /// Mevcut durumu ters çevirir; yeni durumu döndürür (feed/DiziDetay kalp toggle'ı). Oku→yaz
    /// repository'de ATOMİK yürür (askı noktasız tek adım) — eşzamanlı iki toggle bayat okuyup
    /// net-tek etki üretemez (bulgu #5 TOCTOU koruması).
    @discardableResult
    public func toggleFavorite(_ seriesID: SeriesID, at date: Date = Date()) async throws -> Bool {
        let next = try await repository.toggleFavorite(seriesID, at: date)
        if next {
            noteLocalAdd(seriesID)
        } else {
            noteLocalRemoval(seriesID)
        }
        return next
    }

    /// Yeni bir yerel EKLEME kaydedildiğinde: aynı diziye ait bekleyen telafi DELETE'i iptal et
    /// (kullanıcı yeniden ekledi) ve bir sonraki tur için dirty işaretle.
    private func noteLocalAdd(_ seriesID: SeriesID) {
        compensatingDeletes.remove(seriesID)
        needsResync = true
    }

    /// Yeni bir yerel KALDIRMA kaydedildiğinde: eğer eklemenin PUT'u ŞU AN uçuştaysa repository
    /// yerel `pendingAdd`'i sildi ama sunucu favoriyi tutacak → telafi DELETE gerekir. Her hâlde
    /// bir sonraki tur için dirty işaretle.
    private func noteLocalRemoval(_ seriesID: SeriesID) {
        if inFlightAdds.contains(seriesID) {
            compensatingDeletes.insert(seriesID)
        }
        needsResync = true
    }

    // MARK: - Çevrimdışı kuyruk senkronu

    /// Sunucuya gönderilmeyi bekleyen işlem sayısı (retry planlama / test kancası).
    public func pendingSyncCount() async throws -> Int {
        try await repository.pendingSync().count
    }

    /// Çevrimdışı kuyruğu boşaltır: her `pendingAdd`/`pendingRemove` için sunucu çağrısı + onay.
    /// Tek-uçuşlu (zaten sürüyorsa dirty işaretleyip erken döner → mevcut tur bir daha koşar).
    /// İşlem-başına hata izolasyonu: `AppError.network(.offline)` tüm turu erteler (ağ yok),
    /// diğer (kalıcı) hatalar YALNIZ o işlemi atlar (pending bırakır) ve sıradakine geçer.
    public func synchronize() async throws {
        guard !isSyncing else {
            // Coalescing (bulgu #4): sürmekte olan tura "bir tur daha koş" de; snapshot'tan
            // sonra eklenen işlemler açlıkta kalmaz.
            needsResync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        repeat {
            needsResync = false
            try await drainQueueOnce()
            await flushCompensatingDeletes()
        } while needsResync
    }

    /// Kuyruğun güncel anlık görüntüsünü bir kez boşaltır. Offline'da kalanları denemeden erken
    /// çıkar (ağ yok); diğer hatada o işlemi atlayıp devam eder (head-of-line blocking yok).
    private func drainQueueOnce() async throws {
        let pending = try await repository.pendingSync()
        for operation in FavoriteSyncQueue.operations(for: pending) {
            let outcome: OperationOutcome = switch operation {
            case let .put(seriesID):
                await syncAdd(seriesID)
            case let .delete(seriesID):
                await syncRemove(seriesID)
            }
            if outcome == .offline {
                return // ağ yok: kalan işlemler kuyrukta kalır, bağlantı dönünce yeniden denenir
            }
            // .confirmed / .skipped → sıradaki işleme devam
        }
    }

    private enum OperationOutcome {
        case confirmed
        case skipped
        case offline
    }

    private func syncAdd(_ seriesID: SeriesID) async -> OperationOutcome {
        inFlightAdds.insert(seriesID)
        defer { inFlightAdds.remove(seriesID) }
        do {
            try await remoting.putFavorite(seriesID)
        } catch let error as AppError where error == .network(.offline) {
            return .offline
        } catch {
            logger?.error("favorites sync: PUT başarısız, pending bırakıldı")
            return .skipped
        }
        // Koşullu onay: kayıt hâlâ pendingAdd ise synced yapılır. PUT uçarken araya giren bir
        // kaldırma kaydı sildiyse `confirmAdd` no-op'tur (idempotent); silme niyeti aşağıdaki
        // telafi DELETE ile korunur.
        do {
            try await repository.confirmAdd(seriesID)
        } catch {
            logger?.error("favorites sync: confirmAdd başarısız")
            return .skipped
        }
        return .confirmed
    }

    private func syncRemove(_ seriesID: SeriesID) async -> OperationOutcome {
        do {
            try await remoting.deleteFavorite(seriesID)
        } catch let error as AppError where error == .network(.offline) {
            return .offline
        } catch {
            logger?.error("favorites sync: DELETE başarısız, pending bırakıldı")
            return .skipped
        }
        do {
            try await repository.confirmRemoval(seriesID)
        } catch {
            logger?.error("favorites sync: confirmRemoval başarısız")
            return .skipped
        }
        return .confirmed
    }

    /// Uçuştaki bir eklemenin araya girip silinmesiyle sunucuda kalan hayalet favorileri temizler
    /// (bulgu #3). Offline'da erken çıkar; diğer hatada kaydı bir sonraki tura bırakır.
    private func flushCompensatingDeletes() async {
        // Anlık görüntü üzerinde yürü: `await` sırasında araya giren yeniden-ekleme seti
        // değiştirebilir; yeni girişler `needsResync` ile sonraki turda ele alınır.
        for seriesID in Array(compensatingDeletes) {
            do {
                try await remoting.deleteFavorite(seriesID)
                compensatingDeletes.remove(seriesID)
            } catch let error as AppError where error == .network(.offline) {
                return
            } catch {
                logger?.error("favorites sync: telafi DELETE başarısız, sonraki tura bırakıldı")
            }
        }
    }
}
