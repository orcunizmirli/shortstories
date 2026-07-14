/// Kilitli bölüm erişim portu (03 §4 R8): feature'lar arası tüketilen protokol —
/// evi `AppFoundation/SharedDomain` kavramıdır (bu pakette `SharedTypes/` dizini).
/// Tüketici `PlayerKit`'tir, canlı uygulama `WalletKit`'tedir, bağlama
/// ShortSeriesApp DI kompozisyonundadır — PlayerKit WalletKit'i import etmeden
/// entitlement'a bağlanır (R2 korunur).
///
/// Kullanım (04 §9.1): `isLockedForCurrentUser = access.kind == .locked &&
/// !entitlements.hasAccess(episodeID)`; oynatma yetkisinin doğruluk kaynağı yine
/// sunucudur (`POST /playback/authorize`), bu port yalnız istemci ön-kontrolüdür.
public protocol EntitlementChecking: Sendable {
    /// Kullanıcının bölüme erişimi var mı (VIP / daha önce açılmış)?
    func hasAccess(to episodeID: EpisodeID) async -> Bool
}
