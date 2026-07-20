import Foundation

/// Favori (Listem) kaydının çevrimdışı senkron durumu (05 §3.2 `FavoriteEntity.syncState`).
public enum FavoriteSyncState: Int, Sendable, Equatable, CaseIterable {
    case synced = 0
    case pendingAdd = 1
    case pendingRemove = 2
}

/// Favori kaydının taşıma-bağımsız değer tipi.
public struct FavoriteRecord: Sendable, Equatable {
    public let seriesID: SeriesID
    public let addedAt: Date

    public init(seriesID: SeriesID, addedAt: Date) {
        self.seriesID = seriesID
        self.addedAt = addedAt
    }
}

/// Sunucuyla senkronlanmayı bekleyen favori işlemi (çevrimdışı kuyruk hook'u — 05 §3.3).
public struct PendingFavoriteSync: Sendable, Equatable {
    public let seriesID: SeriesID
    public let state: FavoriteSyncState

    public init(seriesID: SeriesID, state: FavoriteSyncState) {
        self.seriesID = seriesID
        self.state = state
    }
}

/// Favoriler (Listem) deposunun feature'lara bakan yüzeyi (03 §9). 05 §3.3 optimistic
/// toggle + çevrimdışı kuyruk kalıbını modeller: yerel yazma anında, sunucu senkronu
/// arka planda (`PUT/DELETE /me/favorites/{seriesId}`). `LibraryKit` yalnız bu protokolü
/// görür. (03 mermaid'inde `MyListRepository` kısaltmasıyla anılan yüzeyin kanonik adı;
/// entity adı 05 §3.2 birebir `FavoriteEntity`.)
public protocol FavoritesRepository: Sendable {
    /// Görünür favori mi (yalnız `pendingRemove` OLMAYAN kayıtlar favori sayılır).
    func isFavorite(_ seriesID: SeriesID) async throws -> Bool

    /// Görünür favoriler, en son eklenen önce (`addedAt` azalan); `pendingRemove` hariç.
    func favorites() async throws -> [FavoriteRecord]

    /// Optimistic ekleme: yerel kayıt `pendingAdd` (senkronsuz yeni) olarak yazılır.
    /// `pendingRemove`'daki bir kayıt tekrar eklenirse `pendingAdd`'e döner.
    func addFavorite(_ seriesID: SeriesID, at date: Date) async throws

    /// Optimistic çıkarma: hiç senkronlanmamış (`pendingAdd`) kayıt doğrudan silinir;
    /// aksi halde `pendingRemove` işaretlenir (sunucu DELETE'i beklenir).
    func removeFavorite(_ seriesID: SeriesID) async throws

    /// Optimistic ÇOKLU çıkarma (Listem çoklu silme, 02 §4.12): verilen dizilerin HEPSİ TEK
    /// serileştirilmiş yerel yazmada işlenir — her kayıt için `removeFavorite` ile AYNI semantik
    /// (`pendingAdd` → doğrudan sil, aksi halde `pendingRemove`), ama N ayrı `save()` yerine tek
    /// `save()`. Boş küme no-op. Varsayılan uygulama tek tek `removeFavorite`'a düşer (geri
    /// uyumluluk); SwiftData store tek yazmaya indirger.
    func removeFavorites(_ seriesIDs: Set<SeriesID>) async throws

    /// Görünür favori durumunu ATOMİK ters çevirir ve yeni durumu döndürür. Oku→değiştir→yaz
    /// tek bir aktör-izole adımda yürür (askı noktası YOK); böylece eşzamanlı iki toggle bayat
    /// okuyup net-tek etki üretemez (TOCTOU koruması). `add`/`removeFavorite` ile aynı optimistic
    /// kuyruk semantiğini uygular.
    func toggleFavorite(_ seriesID: SeriesID, at date: Date) async throws -> Bool

    /// Sunucuya gönderilecek bekleyen işlemler (`pendingAdd` / `pendingRemove`).
    func pendingSync() async throws -> [PendingFavoriteSync]

    /// Sunucu `PUT` onayı: `pendingAdd` kaydı `synced` olur.
    func confirmAdd(_ seriesID: SeriesID) async throws

    /// Sunucu `DELETE` onayı: `pendingRemove` kaydı kalıcı silinir.
    func confirmRemoval(_ seriesID: SeriesID) async throws

    /// TÜM favori kayıtlarını (synced + pendingAdd + pendingRemove) siler. Hesap DEĞİŞİMİNDE
    /// (misafir→mevcut hesaba geçiş, 05 §3.3) yerel store SIFIRLANIR: yeni hesap önceki misafirin
    /// favorilerini GÖRMEZ ve bekleyen işlemler yeni hesaba SIZMAZ. Boş store'da no-op'tur
    /// (idempotent). SessionState mutasyonuna DOKUNMAZ — yalnız yerel veriyi sıfırlar.
    func deleteAll() async throws
}

public extension FavoritesRepository {
    /// Geri uyumlu varsayılan: batch kaldırmayı desteklemeyen konformanslar için tek tek
    /// `removeFavorite`'a düşer. Somut SwiftData store bunu TEK `save()`'e indirgeyerek override
    /// eder (03 §9). Boş kümede döngü hiç dönmez → no-op.
    func removeFavorites(_ seriesIDs: Set<SeriesID>) async throws {
        for seriesID in seriesIDs {
            try await removeFavorite(seriesID)
        }
    }
}
