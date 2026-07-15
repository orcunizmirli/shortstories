import AppFoundation

/// Favori senkron backend portu (SS-121, 05 §3.3 `PUT/DELETE /me/favorites/{seriesId}`).
/// Canlı implementasyon App kompozisyonunda `APIClientProtocol` üzerine bağlanır; testler
/// fake port ile ağ yan etkisi olmadan kuyruk boşaltmayı doğrular.
///
/// İki uç da idempotenttir (aynı diziyi iki kez PUT/DELETE etmek güvenli); çevrimdışıyken
/// `AppError.network(.offline)` fırlatır ve kayıt kuyrukta kalır (online olunca tekrar denenir).
public protocol FavoritesRemoting: Sendable {
    func putFavorite(_ seriesID: SeriesID) async throws
    func deleteFavorite(_ seriesID: SeriesID) async throws
}
