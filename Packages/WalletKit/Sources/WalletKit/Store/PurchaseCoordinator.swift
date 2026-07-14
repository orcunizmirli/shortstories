import AppFoundation
import Foundation

/// StoreKit satın alma → backend doğrulama → finish orkestrasyonu (SS-090/091). `actor`.
///
/// Kritik akış (06 §4.1): purchase → verified Transaction (JWS) → `POST /iap/verify` → backend
/// kredi → `finish()` YALNIZ backend onayından SONRA. Doğrulama başarısızsa (ağ/5xx) transaction
/// unfinished bırakılır ve yeniden denenir (retry kuyruğu = StoreKit'in unfinished mekanizması,
/// 05 §4.6). İki katmanlı idempotency: (1) client-tarafı in-flight `processing` seti aynı
/// transaction'ı eşzamanlı iki kez göndermez; (2) backend `transactionId` ile idempotenttir ve
/// mutlak snapshot döndürdüğü için `WalletStore` SET semantiğiyle çift kredi yazmaz.
public actor PurchaseCoordinator {
    private let purchases: any PurchaseServicing
    private let remote: any WalletRemoting
    private let wallet: WalletStore
    private let analytics: any AnalyticsTracking
    private let log: any Logging
    private let appAccountToken: @Sendable () -> UUID

    private var processing: Set<UInt64> = []
    private var observerTask: Task<Void, Never>?

    public init(
        purchases: any PurchaseServicing,
        remote: any WalletRemoting,
        wallet: WalletStore,
        analytics: any AnalyticsTracking,
        log: any Logging,
        appAccountToken: @escaping @Sendable () -> UUID
    ) {
        self.purchases = purchases
        self.remote = remote
        self.wallet = wallet
        self.analytics = analytics
        self.log = log
        self.appAccountToken = appAccountToken
    }

    deinit {
        observerTask?.cancel()
    }

    // MARK: - Satın alma (CoinMagazasi / VIPAbonelik)

    public func purchase(productID: String) async -> PurchaseFlowResult {
        do {
            let result = try await purchases.purchase(productID: productID, appAccountToken: appAccountToken())
            switch result {
            case let .success(transaction):
                return await process(transaction).flowResult
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            }
        } catch let error as AppError {
            return .failed(error)
        } catch {
            return .failed(.unexpected(underlying: String(describing: error)))
        }
    }

    // MARK: - Transaction gözlemcisi (app launch'ta BİR KEZ; 06 §4.4)

    /// Önce önceki oturumlardan kalan unfinished'ları drenajlar, sonra canlı `updates`'i dinler.
    public func startObservingTransactions() {
        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            guard let self else { return }
            for transaction in await purchases.unfinishedTransactions() {
                await process(transaction)
            }
            for await transaction in purchases.transactionUpdates() {
                await process(transaction)
            }
        }
    }

    /// Bekleyen (unfinished) transaction'ları yeniden işler — açık retry (ör. ağ döndüğünde).
    public func retryUnfinished() async {
        for transaction in await purchases.unfinishedTransactions() {
            await process(transaction)
        }
    }

    // MARK: - Restore (06 §4.6)

    /// "Satın Alımları Geri Yükle": App Store senkronu + backend snapshot tazeleme.
    public func restore() async throws {
        try await purchases.sync()
        await wallet.refresh()
    }

    /// Launch-time entitlement tohumu (06 §4.5): StoreKit `currentEntitlements`'tan iyimser VIP.
    public func seedEntitlementsFromStoreKit() async {
        let hasActiveSubscription = await purchases.currentEntitlements()
            .contains { $0.kind == .subscription && $0.revocationDate == nil }
        await wallet.seedEntitlementFromStoreKit(hasActiveSubscription: hasActiveSubscription)
    }

    // MARK: - Çekirdek işleme

    @discardableResult
    func process(_ transaction: VerifiedTransaction) async -> ProcessOutcome {
        // Aile paylaşımı KAPALI (06 §4.7): savunmacı reddet + finish (redelivery döngüsünü kes).
        if transaction.isFamilyShared {
            analytics.track(
                "iap_family_shared_rejected",
                parameters: ["product_id": .string(transaction.productID)]
            )
            log.error("family-shared transaction rejected (Family Sharing is OFF)")
            await purchases.finish(transactionID: transaction.id)
            return .rejected
        }

        // İade/revoke (06 §4.4): backend V2 ile zaten bilir; yerel state tazele + finish.
        if transaction.revocationDate != nil {
            await wallet.refresh()
            await purchases.finish(transactionID: transaction.id)
            return .revoked
        }

        // Client-tarafı idempotency: aynı transaction eşzamanlı iki kez gönderilmez.
        guard !processing.contains(transaction.id) else {
            return .inFlight
        }
        processing.insert(transaction.id)
        defer { processing.remove(transaction.id) }

        do {
            let outcome = try await remote.verifyPurchase(
                productID: transaction.productID,
                jws: transaction.jws,
                kind: transaction.kind,
                idempotencyKey: transaction.idempotencyKey
            )
            return await apply(outcome, transaction: transaction)
        } catch {
            // Geçici hata: finish ETME — unfinished kalır, sonraki updates/retry turunda gelir.
            log.error("iap verify failed, left unfinished: \(String(describing: error))")
            return .pendingRetry
        }
    }

    private func apply(_ outcome: VerifyOutcome, transaction: VerifiedTransaction) async -> ProcessOutcome {
        switch outcome {
        case let .coinsCredited(_, walletSnapshot, _):
            await wallet.apply(walletSnapshot: walletSnapshot)
            await purchases.finish(transactionID: transaction.id)
            analytics.track("iap_credited", parameters: ["product_id": .string(transaction.productID)])
            return .credited
        case let .subscriptionUpdated(subscription):
            await wallet.apply(subscription: subscription)
            await purchases.finish(transactionID: transaction.id)
            analytics.track("iap_subscription_updated", parameters: ["product_id": .string(transaction.productID)])
            return .credited
        case let .alreadyProcessed(walletSnapshot, subscription):
            if let walletSnapshot {
                await wallet.apply(walletSnapshot: walletSnapshot)
            }
            if let subscription {
                await wallet.apply(subscription: subscription)
            }
            if walletSnapshot == nil, subscription == nil {
                await wallet.refresh()
            }
            await purchases.finish(transactionID: transaction.id)
            return .alreadyProcessed
        case .invalidReceipt:
            // TİPLİ 422 RECEIPT_INVALID (06 §4.6): makbuz gerçekten geçersiz → TERMİNAL. Kredi asla
            // gelmeyeceği için transaction FINISH edilir (aksi halde her açılışta re-verify eden sonsuz
            // döngüye düşerdi). Kredi YAZILMAZ; kullanıcı destek akışına yönlendirilir. NOT: yalnız TİPLİ
            // RECEIPT_INVALID buraya ulaşır; çıplak/tanınmayan 422 pendingRetry olarak unfinished kalır.
            analytics.track("iap_receipt_invalid", parameters: ["product_id": .string(transaction.productID)])
            log.error("iap receipt invalid (terminal) — finished without credit, routed to support")
            await purchases.finish(transactionID: transaction.id)
            return .invalidReceipt
        }
    }

    /// Test/gözlem için: gözlemci task'i (updates stream sonlanınca) tamamlanana dek bekler.
    func awaitObserver() async {
        await observerTask?.value
    }
}

/// `process(_:)` sonucu — orkestrasyon iç durumu ve `PurchaseFlowResult`'a çevrim.
enum ProcessOutcome: Sendable, Equatable {
    case credited
    case alreadyProcessed
    case pendingRetry
    case invalidReceipt
    case revoked
    case rejected
    case inFlight

    var flowResult: PurchaseFlowResult {
        switch self {
        case .credited, .alreadyProcessed:
            .completed
        case .pendingRetry:
            .verificationPending
        case .invalidReceipt:
            .invalidReceipt
        case .revoked, .rejected, .inFlight:
            .failed(.wallet(.transactionConflict))
        }
    }
}
