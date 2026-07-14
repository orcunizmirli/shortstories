import AppFoundation

/// IAP ürün sınıfı (05 §4.6 `kind`): consumable = coin paketi, subscription = VIP.
public enum PurchaseKind: String, Sendable, Equatable {
    case consumable
    case subscription
}

/// `POST /iap/verify` coin yanıtındaki `granted` bloğu (05 §4.6). İstemci bonus HESAPLAMAZ;
/// sunucu ne verdiyse odur (`firstPurchaseBonusApplied` ilk yükleme 2x uygulandı mı).
public struct GrantedCoins: Sendable, Equatable, Decodable {
    public let coins: Int
    public let bonusCoins: Int
    public let firstPurchaseBonusApplied: Bool

    public init(coins: Int, bonusCoins: Int, firstPurchaseBonusApplied: Bool) {
        self.coins = coins
        self.bonusCoins = bonusCoins
        self.firstPurchaseBonusApplied = firstPurchaseBonusApplied
    }
}

/// `POST /iap/verify` sunucu-kararlı sonucu (05 §4.6). Ağ hataları `throws AppError` ile yüzer;
/// bu enum yalnız sunucunun döndüğü iş sonucunu taşır.
public enum VerifyOutcome: Sendable, Equatable {
    /// Coin paketi kredilendi (200).
    case coinsCredited(granted: GrantedCoins, wallet: WalletSnapshot, transaction: CoinTransaction?)
    /// VIP entitlement güncellendi (200).
    case subscriptionUpdated(SubscriptionStatus)
    /// 409 RECEIPT_ALREADY_PROCESSED (05 §10.2): başarı say, transaction finish edilir.
    /// Snapshot zarftan alınamadığında `nil` gelir → çağıran `refresh()` ile mutabık kalır.
    case alreadyProcessed(wallet: WalletSnapshot?, subscription: SubscriptionStatus?)
    /// 422 RECEIPT_INVALID (05 §4.6): transaction finish EDİLMEZ, destek akışına yönlendirilir.
    case invalidReceipt
}

/// Satın alma orkestrasyonunun (PurchaseCoordinator) kullanıcı-görünür sonucu (SS-090/091).
public enum PurchaseFlowResult: Sendable, Equatable {
    /// Satın alma + backend doğrulama + finish tamamlandı. `transactionID` App Store işlem
    /// kimliğidir (08 §3.4 `coin_purchase_success`/`subscription_success` zorunlu `transaction_id`):
    /// gelir atıfı/iade-chargeback mutabakatı ve replay dedupe için istemci↔server join anahtarı.
    case completed(transactionID: String)
    /// Backend doğrulaması gecikti (ağ/5xx): "coin'ler birazdan yüklenecek" durumu;
    /// transaction unfinished bırakıldı ve otomatik yeniden denenecek (06 §4.3).
    case verificationPending
    /// Ask to Buy / SCA — onay bekleniyor (06 §4.9).
    case pending
    /// Kullanıcı iptal etti (sessiz; hata gösterilmez, 06 §7.5).
    case cancelled
    /// Sahte/doğrulanamayan receipt (422): destek akışı (06 §4.6).
    case invalidReceipt
    case failed(AppError)
}
