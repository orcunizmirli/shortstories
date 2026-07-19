import AppFoundation
import Foundation
import Observation

/// CoinMagazasi giriş kaynağı (08 §3.4 `coin_store_view.source`).
public enum CoinShopSource: String, Sendable, Equatable {
    case unlockSheet = "unlock_sheet"
    case profil
    case odulMerkezi = "odul_merkezi"
    case deeplink
}

/// Katalog + ürün yükleme durumu (06 §7.4). Boş sonuç (hiç eşleşen ürün) → `failed` (retry).
public enum ShopLoadPhase: Equatable, Sendable {
    case loading
    case loaded
    case failed
}

/// CoinMagazasi intent sözleşmesi — App koordinatörü bağlar.
@MainActor
public protocol CoinShopDelegate: AnyObject {
    /// Satın alma + backend kredi tamam. `UnlockSheet`'ten gelindiyse koordinatör otomatik geri
    /// döner (06 §6.3); Profil'den gelindiyse ekranda kalınır — karar koordinatörün.
    func coinShopDidCompletePurchase()
    /// Kullanıcı mağazayı kapattı.
    func coinShopRequestsDismiss()
}

/// CoinMagazasi ekran modeli (SS-094). @Observable/@MainActor. Katalog+StoreKit birleştirme
/// (StorefrontMerge), satın alma durum makinesi (StorePurchasePhase) ve bakiye kredi
/// animasyonu için canlı bakiye yayını. Fiyatlar StoreKit `displayPrice`'tan (USD hardcode YOK).
@MainActor
@Observable
public final class CoinShopModel {
    // MARK: - Durum (Observable)

    public private(set) var loadPhase: ShopLoadPhase = .loading
    public private(set) var items: [CoinShopItem] = []
    public private(set) var balance: CoinBalance = .zero
    public private(set) var earnedExpiringSoon: ExpiryNotice?
    /// Sunucu-otoriter earned lotları (06 §2.5); açılışta snapshot'tan seed edilir. Yaklaşan-vade
    /// uyarısı bunlardan türetilir (istemci bakiye HESAPLAMAZ). Sunucu `earnedBuckets` gönderene
    /// dek (05 §2.5 WIRE TODO) boş kalır → uyarı tekil `earnedExpiringSoon` bandına düşer.
    public private(set) var earnedBuckets: [EarnedCoinBucket] = []
    public private(set) var firstTopUpEligible = false
    public private(set) var purchasePhase: StorePurchasePhase = .idle

    /// Yaklaşan-vade uyarısının saf sunum türevi (SS-115 D1). View doğrudan çizer; uygun vade
    /// yoksa `nil` (bant çizilmez). `now` enjekte → deterministik "N gün".
    public var earnedExpiryWarning: EarnedExpiryWarning? {
        EarnedExpiryWarning.resolve(buckets: earnedBuckets, notice: earnedExpiringSoon, now: now())
    }

    // MARK: - Bağımlılıklar

    private let source: CoinShopSource
    private let loader: any StorefrontLoading
    private let wallet: any WalletGateway
    private let purchasing: any WalletPurchasing
    private let analytics: any AnalyticsTracking
    private let now: @Sendable () -> Date
    private weak var delegate: (any CoinShopDelegate)?

    private var priceByProductID: [String: Decimal] = [:]
    private var observationTask: Task<Void, Never>?
    private var started = false
    /// Sheet kapandı — `begin()` bir await'te askıdayken `onDisappear` gelirse gözlem görevinin
    /// await SONRASI kurulup asla iptal edilmemesini (kalıcı sızıntı) engeller.
    private var isDisposed = false

    public init(
        source: CoinShopSource,
        loader: any StorefrontLoading,
        wallet: any WalletGateway,
        purchasing: any WalletPurchasing,
        analytics: any AnalyticsTracking,
        delegate: (any CoinShopDelegate)?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.loader = loader
        self.wallet = wallet
        self.purchasing = purchasing
        self.analytics = analytics
        self.delegate = delegate
        self.now = now
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        Task { await begin() }
    }

    public func onDisappear() {
        isDisposed = true
        observationTask?.cancel()
        observationTask = nil
    }

    /// Bakiye seed + `coin_store_view` analitiği + canlı bakiye gözlemi + katalog yükleme.
    /// Testler doğrudan `await` eder.
    func begin() async {
        guard !started else { return }
        started = true
        let snapshot = await wallet.currentSnapshot()
        // Await sırasında sheet kapandıysa gözlem kurma (kalıcı sızıntı olmasın).
        guard !isDisposed else { return }
        balance = snapshot.balance
        earnedExpiringSoon = snapshot.earnedExpiringSoon
        earnedBuckets = snapshot.earnedBuckets
        trackStoreView()
        startObserving()
        await load()
    }

    private func startObserving() {
        guard !isDisposed, observationTask == nil else { return }
        // Akış görev DIŞINDA yakalanır; görev `self`'i yalnız ZAYIF tutar ve her turda güçlüye
        // terfi ettirip iterasyon sonunda bırakır → askıda `for await` self'i tutmaz (retain-cycle
        // yok). Model dealloc olursa (onDisappear atlansa bile) sonraki emisyonda döngü kırılır.
        let updates = wallet.balanceUpdates()
        observationTask = Task { [weak self] in
            for await incoming in updates {
                guard let self else { break }
                balance = incoming
            }
        }
    }

    // MARK: - Yükleme (06 §7.4)

    public func load() async {
        loadPhase = .loading
        do {
            async let catalogTask = loader.fetchPackages()
            async let productsTask = loader.loadProducts(ids: ShortSeriesProduct.coinTiers)
            let (catalog, products) = try await (catalogTask, productsTask)
            priceByProductID = Dictionary(products.map { ($0.id, $0.price) }, uniquingKeysWith: { first, _ in first })
            let merged = StorefrontMerge.coinShop(catalog: catalog, products: products)
            items = merged
            firstTopUpEligible = catalog.firstTopUpEligible
            // Boş liste (ör. StoreKit'te hiç eşleşen ürün) → hata durumu + retry (06 §7.4).
            loadPhase = merged.isEmpty ? .failed : .loaded
        } catch {
            loadPhase = .failed
        }
    }

    public func retry() async {
        await load()
    }

    // MARK: - Satın alma (06 §4.1 / §7.4)

    public func purchase(_ item: CoinShopItem) async {
        // Çift dokunuş/çift satın alma koruması (06 §7.5): uçuşta VEYA Ask-to-Buy onayı beklerken
        // (pending) yeni satın alma başlatılmaz — pending penceresinde ikinci onaylanan işlem çift
        // kredi/ücret yaratır.
        guard !purchasePhase.preventsNewPurchase else { return }
        purchasePhase = .purchasing(productID: item.productId)
        trackPurchaseStart(item)

        let result = await purchasing.purchase(productID: item.productId)
        purchasePhase = StorePurchasePhase.resolve(result, productID: item.productId)

        switch result {
        case let .completed(transactionID):
            // Kredi WalletStore snapshot'ıyla yazıldı → otoritatif tazele. `balance_after` bu
            // otoritatif okumadan alınır (canlı yayının sırasına bağlı @Observable'dan DEĞİL).
            let credited = await wallet.currentBalance()
            balance = credited
            trackPurchaseSuccess(item, balanceAfter: credited.totalCoins, transactionID: transactionID)
            delegate?.coinShopDidCompletePurchase()
        case .cancelled:
            analytics.track("coin_purchase_cancel", parameters: ["product_id": .string(item.productId)])
        case let .failed(error):
            trackPurchaseFail(item, error: error, stage: "storekit")
        case .invalidReceipt:
            trackPurchaseFail(item, error: .wallet(.receiptInvalid), stage: "verification")
        case .pending, .verificationPending:
            break // bilgi durumu — hata/başarı değil (06 §4.9)
        }
    }

    /// Toast/alert kapatılınca geçici fazı sıfırla (idle'a dön).
    public func acknowledgeTransientPhase() {
        switch purchasePhase {
        case .success, .failed, .invalidReceipt, .pending, .verificationPending:
            purchasePhase = .idle
        case .idle, .purchasing:
            break
        }
    }

    // MARK: - Restore (06 §11.3)

    public func restore() async {
        analytics.track("restore_tapped", parameters: ["source": .string(source.rawValue)])
        try? await purchasing.restore()
    }

    public func dismiss() {
        delegate?.coinShopRequestsDismiss()
    }

    // MARK: - Analitik

    private func trackStoreView() {
        analytics.track(
            "coin_store_view",
            parameters: [
                "source": .string(source.rawValue),
                "coin_balance": .int(balance.totalCoins)
            ]
        )
    }

    private func trackPurchaseStart(_ item: CoinShopItem) {
        var parameters: [String: AnalyticsValue] = [
            "product_id": .string(item.productId),
            "coin_amount": .int(item.package.baseCoins),
            "bonus_coin_amount": .int(item.package.bonusCoins),
            "is_first_purchase_offer": .bool(item.firstTopUpEligible)
        ]
        if let price = priceByProductID[item.productId] {
            parameters["price_usd"] = .double(price.doubleValue)
        }
        analytics.track("coin_purchase_start", parameters: parameters)
    }

    private func trackPurchaseSuccess(_ item: CoinShopItem, balanceAfter: Int, transactionID: String) {
        // 08 §3.4 satır 201: `transaction_id` zorunlu — gelir atıfı/iade-chargeback mutabakatı ve
        // replay dedupe için App Store işlemine join anahtarı.
        var parameters: [String: AnalyticsValue] = [
            "product_id": .string(item.productId),
            "coin_amount": .int(item.package.baseCoins),
            "bonus_coin_amount": .int(item.package.bonusCoins),
            "balance_after": .int(balanceAfter),
            "transaction_id": .string(transactionID)
        ]
        if let price = priceByProductID[item.productId] {
            parameters["price_usd"] = .double(price.doubleValue)
        }
        analytics.track("coin_purchase_success", parameters: parameters)
    }

    private func trackPurchaseFail(_ item: CoinShopItem, error: AppError, stage: String) {
        let (domain, code) = AnalyticsMapping.domainCode(error)
        analytics.track(
            "coin_purchase_fail",
            parameters: [
                "product_id": .string(item.productId),
                "error_domain": .string(domain),
                "error_code": .string(code),
                "stage": .string(stage)
            ]
        )
    }
}

private extension Decimal {
    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
