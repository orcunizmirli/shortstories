import Foundation

/// İzleme ilerlemesi kaydının taşıma-bağımsız değer tipi (05 §2.11 `WatchProgress`'in
/// yerel karşılığı). `ContentKit.WatchProgress` domain modeli AppFoundation'a bağımlı
/// olamayacağı için (R1/R3) repository yüzeyi bu AppFoundation-yerel tipi taşır;
/// `LibraryKit` iki tip arasında eşler.
public struct WatchProgressRecord: Sendable, Equatable {
    public let episodeID: EpisodeID
    public let seriesID: SeriesID
    public let positionSec: Double
    public let durationSec: Double
    public let completed: Bool
    /// Son izleme anı; çakışma çözümü last-write-wins (05 §3.3 — en yeni `watchedAt` kazanır).
    public let watchedAt: Date

    public init(
        episodeID: EpisodeID,
        seriesID: SeriesID,
        positionSec: Double,
        durationSec: Double,
        completed: Bool,
        watchedAt: Date
    ) {
        self.episodeID = episodeID
        self.seriesID = seriesID
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.completed = completed
        self.watchedAt = watchedAt
    }

    /// İlerleme yüzdesi [0, 1] (05 §2.11: `positionSec / durationSec`). `durationSec <= 0`
    /// iken 0 döner (sıfıra bölme koruması).
    public var progressFraction: Double {
        guard durationSec > 0 else { return 0 }
        return min(1, max(0, positionSec / durationSec))
    }
}

/// İzleme geçmişi + "kaldığı yer" deposunun feature'lara bakan yüzeyi (03 §9, §6.2).
/// Somut uygulama `AppFoundation/Storage/Persistence` içinde SwiftData'ya dayanır;
/// `LibraryKit` (SS-120/SS-122) yalnız bu protokolü görür — `ModelContext`'e dokunmaz.
///
/// Tüm metotlar `async`: gerçek uygulama yazmaları arka plan context'inde, actor'a
/// hapsedilmiş yürütür (03 §7.3, §9 — ana thread'e I/O sokulmaz).
public protocol WatchHistoryRepository: Sendable {
    /// "Kaldığı yer"i kaydeder (upsert). Kayıt `pendingUpload` olarak işaretlenir
    /// (çevrimdışı kuyruk). Aynı bölüm için mevcut kaydın `watchedAt`'i daha yeniyse
    /// yazma yok sayılır (last-write-wins — 05 §3.3).
    func saveProgress(_ progress: WatchProgressRecord) async throws

    /// Sunucudan gelen birleşik geçmişi yerel tabloya yazar (senkron; `pendingUpload`
    /// İŞARETLENMEZ). Var olan yerel `pendingUpload` kaydı daha yeniyse korunur.
    func mergeServerProgress(_ records: [WatchProgressRecord]) async throws

    /// Belirli bölümün kayıtlı ilerlemesi; yoksa `nil`.
    func progress(forEpisode episodeID: EpisodeID) async throws -> WatchProgressRecord?

    /// Bir dizinin tüm bölüm ilerlemeleri (bölüm sırası çağırana kalmış).
    func progress(forSeries seriesID: SeriesID) async throws -> [WatchProgressRecord]

    /// Bir dizinin EN GÜNCEL ilerleme kaydı (`watchedAt` en yeni); hiç izlenmediyse `nil`.
    /// Hedefli sorgu: `seriesId` predikatı + `SortDescriptor(watchedAt, .reverse)` + `fetchLimit
    /// 1`. Tüm dizi kayıtlarını çekip bellekte `.max` etmez (bulgu #11) — DiziDetay "İzlemeye
    /// Başla / Devam Et" CTA'sı (SS-081) yalnız bu tek kaydı ister.
    func latestProgress(forSeries seriesID: SeriesID) async throws -> WatchProgressRecord?

    /// "Devam Et" listesi: tamamlanmamış kayıtlar, en son izlenen önce (`watchedAt` azalan).
    /// `limit <= 0` tümünü döndürür.
    func continueWatching(limit: Int) async throws -> [WatchProgressRecord]

    /// Sunucuya yüklenmeyi bekleyen kayıtlar (`syncState == pendingUpload`) — batch upload
    /// hook'u (05 §3.3, `POST /playback/progress`).
    func pendingUploads() async throws -> [WatchProgressRecord]

    /// Upload başarılı olunca YÜKLENEN kayıtları `synced` işaretler. Yalnız `episodeID` değil
    /// yüklenen anlık görüntünün tamamı (özellikle `watchedAt`) taşınır: upload'ın `await`'i
    /// sırasında araya giren daha yeni bir yerel yazma (reentrancy) `watchedAt`'i ilerlettiyse
    /// o kayıt `pendingUpload` KALIR (bir sonraki tur yükler) — böylece henüz sunucuya gitmemiş
    /// bir yazma yanlışlıkla `synced` işaretlenip kaybolmaz (05 §3.3 last-write-wins, simetrik guard).
    func markSynced(uploaded records: [WatchProgressRecord]) async throws

    /// TÜM izleme-geçmişi kayıtlarını (synced + pendingUpload) siler. Hesap DEĞİŞİMİNDE (misafir→
    /// mevcut hesaba geçiş, 05 §3.3) yerel store SIFIRLANIR: yeni hesap önceki misafirin geçmişini
    /// GÖRMEZ ve sonraki senkron misafir pendingUpload'larını yeni hesaba YÜKLEMEZ. Boş store'da
    /// no-op'tur (idempotent). SessionState mutasyonuna DOKUNMAZ — yalnız yerel veriyi sıfırlar.
    func deleteAll() async throws
}
