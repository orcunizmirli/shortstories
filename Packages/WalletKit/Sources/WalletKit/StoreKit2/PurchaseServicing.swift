import Foundation

/// StoreKit 2 satın alma sonucunun taşıma-bağımsız özeti (06 §4.3). `.success` içindeki
/// transaction cihazda imza-doğrulanmıştır ama GÜVEN KAYNAĞI DEĞİLDİR — asıl doğrulama
/// backend `POST /iap/verify`'dedir (06 §4.5).
public enum PurchaseResult: Sendable, Equatable {
    case success(VerifiedTransaction)
    case userCancelled
    case pending
}

/// StoreKit 2 satın alma / transaction portu (SS-090). Canlı implementasyon
/// `StoreKitPurchaseService`; testler fake port ile başarı/iptal/pending ve
/// unfinished/updates senaryolarını StoreKit config dosyası OLMADAN kurar.
///
/// **Kritik kural (06 §4.1):** consumable transaction yalnız backend kredi ettikten SONRA
/// `finish()` edilir. Bu yüzden `purchase()` finish ETMEZ; orkestrasyon (PurchaseCoordinator)
/// doğrulama başarısında `finish(transactionID:)` çağırır.
public protocol PurchaseServicing: Sendable {
    /// - Parameter appAccountToken: backend userId'den türetilmiş UUID (transaction'ı hesaba bağlar).
    func purchase(productID: String, appAccountToken: UUID) async throws -> PurchaseResult

    /// Backend onayından SONRA çağrılır: transaction'ı sonlandırır (bir daha teslim edilmez).
    func finish(transactionID: UInt64) async

    /// Önceki oturumlardan kalan bitirilmemiş transaction'lar (uygulama açılışında drenaj).
    func unfinishedTransactions() async -> [VerifiedTransaction]

    /// Canlı güncellemeler: yenileme, iade, Ask to Buy onayı, App Store kaynaklı işlemler.
    func transactionUpdates() -> AsyncStream<VerifiedTransaction>

    /// `Transaction.currentEntitlements` — VIP durumunun yerel iyimser ipucu (06 §4.5).
    func currentEntitlements() async -> [VerifiedTransaction]

    /// `AppStore.sync()` — yalnız kullanıcı "Satın Alımları Geri Yükle" dediğinde (06 §4.6).
    func sync() async throws
}
