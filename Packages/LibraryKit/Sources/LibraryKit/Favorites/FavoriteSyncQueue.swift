import AppFoundation

/// Çevrimdışı favori kuyruğundan türetilen tek bir sunucu işlemi (05 §3.3
/// `PUT/DELETE /me/favorites/{seriesId}`).
public enum FavoriteSyncOperation: Equatable, Sendable {
    /// `pendingAdd` → `PUT` (favoriye ekle).
    case put(SeriesID)
    /// `pendingRemove` → `DELETE` (favoriden çıkar).
    case delete(SeriesID)
}

/// Çevrimdışı favori senkron kuyruğunun SAF planlayıcısı (SS-121). `FavoritesRepository`'nin
/// tuttuğu bekleyen kayıtları (`pendingAdd`/`pendingRemove`) sunucu işlemlerine çevirir;
/// `synced` kayıtlar (senkron gereksiz) elenir. `FavoritesService.synchronize()` bu planı
/// yürütür — ağ/onay yan etkileri buradan izole test edilir.
public enum FavoriteSyncQueue {
    public static func operations(for pending: [PendingFavoriteSync]) -> [FavoriteSyncOperation] {
        pending.compactMap { entry in
            switch entry.state {
            case .pendingAdd: .put(entry.seriesID)
            case .pendingRemove: .delete(entry.seriesID)
            case .synced: nil
            }
        }
    }
}
