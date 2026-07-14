import AppFoundation

/// UI dilimi (UnlockSheet/CoinMagazasi/VIPAbonelik) ile çekirdek `WalletStore` actor'ü
/// arasındaki dar okuma+kilit-açma portu (SS-093/094/096). Ekran modelleri somut actor'e
/// değil bu protokole bağlanır — testler fake ile koşar, App kompozisyonu `WalletStore`'u
/// bağlar. Actor-izole senkron metotlar `async` gereksinimleri karşılar (cross-actor erişim
/// örtük async'tir); bu yüzden `WalletStore` ek kod olmadan uyum sağlar.
public protocol WalletGateway: Sendable {
    /// Anlık toplam/kese bakiyesi (05 §2.5). Doğruluk kaynağı sunucudur; bu iyimser UI ipucudur.
    func currentBalance() async -> CoinBalance

    /// Otoritatif cüzdan snapshot'ı (earned son-kullanma bandı, ilk-yükleme uygunluğu için).
    func currentSnapshot() async -> WalletSnapshot

    /// VIP durumu (yönetim modu + günlük bonus gösterimi için).
    func subscriptionStatus() async -> SubscriptionStatus

    /// Bir bölümün açık olup olmadığı (kartın kilitli görünüp görünmeyeceği).
    func isEpisodeUnlocked(_ episodeID: EpisodeID) async -> Bool

    /// Coin ile kilit açma (SS-095): optimistic entitlement + server-otoritatif mutabakat.
    func unlock(episodeID: EpisodeID, expectedPrice: Int) async -> UnlockResult

    /// Bakiye değişim yayını (current-value replay; sheet açıkken canlı güncelleme).
    func balanceUpdates() -> AsyncStream<CoinBalance>

    /// Entitlement değişim yayını (başka cihazdan VIP aktifleşirse sheet kendini kapatır).
    func entitlementUpdates() -> AsyncStream<EntitlementSnapshot>
}

extension WalletStore: WalletGateway {}

/// UI dilimi ile `PurchaseCoordinator` actor'ü arasındaki dar satın-alma+restore portu
/// (SS-090/091). StoreKit tipleri portun ARDINDA kalır (public imzada StoreKit yok, R6);
/// UI yalnız taşıma-bağımsız `PurchaseFlowResult` görür.
public protocol WalletPurchasing: Sendable {
    /// Consumable coin / VIP aboneliği satın alır → backend doğrulama → kredi.
    func purchase(productID: String) async -> PurchaseFlowResult

    /// "Satın Alımları Geri Yükle" (App Store Review zorunlu, 06 §11.3): App Store senkronu +
    /// backend snapshot tazeleme.
    func restore() async throws
}

extension PurchaseCoordinator: WalletPurchasing {}

/// CoinMagazasi/VIPAbonelik'in katalog + StoreKit ürünlerini yüklemek için kullandığı port.
/// `WalletRemoting.fetchPackages` + `ProductProviding.loadProducts`'ı tek yüzeyde toplar;
/// App bunu somut istemcilere bağlar, testler fake ile besler.
public protocol StorefrontLoading: Sendable {
    /// `GET /wallet/packages` — coin paket kataloğu (coin/bonus/rozet + ilk-yükleme uygunluğu).
    func fetchPackages() async throws -> CoinPackageCatalog

    /// `Product.products(for:)` — yerelleştirilmiş fiyatlı StoreKit ürünleri (eksik ID atlanır).
    func loadProducts(ids: [String]) async throws -> [StoreProduct]
}

/// Backend + StoreKit portlarını birleştiren canlı adaptör (App kompozisyonu bunu kullanır).
public struct StorefrontLoader: StorefrontLoading {
    private let remote: any WalletRemoting
    private let products: any ProductProviding

    public init(remote: any WalletRemoting, products: any ProductProviding) {
        self.remote = remote
        self.products = products
    }

    public func fetchPackages() async throws -> CoinPackageCatalog {
        try await remote.fetchPackages()
    }

    public func loadProducts(ids: [String]) async throws -> [StoreProduct] {
        try await products.loadProducts(ids: ids)
    }
}
