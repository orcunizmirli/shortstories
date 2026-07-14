import AppFoundation

/// Cüzdan/IAP backend portu (SS-091/092/095). Canlı implementasyon `WalletRemoteClient`
/// (AppFoundation `APIClientProtocol` üzerinden); testler fake port ile sunucu-kararlı
/// sonuçları (insufficient/priceChanged/alreadyProcessed…) doğrudan üretir.
///
/// İş sonuçları (insufficientCoins, priceChanged, alreadyProcessed, invalidReceipt) tipli
/// enum'larla döner; ağ/taşıma hataları `throws AppError` ile yüzer (03 §10.1).
public protocol WalletRemoting: Sendable {
    /// `GET /wallet` — otoritatif bakiye snapshot'ı (05 §4.5).
    func fetchWallet() async throws -> WalletSnapshot

    /// `GET /subscription` — VIP durumu (05 §4.1 #17).
    func fetchSubscription() async throws -> SubscriptionStatus

    /// `GET /wallet/packages` — CoinMagazasi paket kataloğu (05 §4.5).
    func fetchPackages() async throws -> CoinPackageCatalog

    /// `POST /wallet/unlock` — idempotent kilit açma (05 §4.5). `idempotencyKey` kullanıcı niyeti
    /// anında üretilir ve retry'larda aynen tekrar kullanılır; yeni niyet = yeni anahtar.
    func unlock(episodeID: EpisodeID, expectedPrice: Int, idempotencyKey: String) async throws -> UnlockOutcome

    /// `POST /iap/verify` — StoreKit transaction JWS doğrulama + kredi (05 §4.6). Idempotent
    /// (`transactionId` türevli anahtar); aynı JWS iki kez → tek kredi.
    func verifyPurchase(
        productID: String,
        jws: String,
        kind: PurchaseKind,
        idempotencyKey: String
    ) async throws -> VerifyOutcome
}
