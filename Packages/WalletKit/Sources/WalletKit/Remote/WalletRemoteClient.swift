import AppFoundation

/// Canlı cüzdan/IAP backend istemcisi (SS-091/095): AppFoundation `APIClientProtocol` üzerinden
/// endpoint'leri çağırır ve HTTP sonuçlarını tipli `UnlockOutcome`/`VerifyOutcome`'a çevirir.
///
/// Zenginleştirme (05 §10.3): HTTP kodu + `error.code` → `AppError` eşlemesi YALNIZ AppFoundation
/// API katmanındadır. `mapFailure` artık 402 INSUFFICIENT_COINS → `.wallet(.insufficientCoins(
/// shortfall:))`, 409 PRICE_CHANGED → `.wallet(.priceChanged(currentPrice:))`, 409
/// RECEIPT_ALREADY_PROCESSED → `.wallet(.receiptAlreadyProcessed(...))`, 422 RECEIPT_INVALID →
/// `.wallet(.receiptInvalid)` üretir ve `details`'i tipli taşır. Bu istemci canlı yolda bu tipli
/// değerleri (shortfall/currentPrice) GERÇEK değerle eşler; gövde kodsuz gelirse ham
/// `.network(.server(status:))` fallback'i korunur (shortfall/currentPrice `nil`).
public struct WalletRemoteClient: WalletRemoting {
    private let client: any APIClientProtocol

    public init(client: any APIClientProtocol) {
        self.client = client
    }

    public func fetchWallet() async throws -> WalletSnapshot {
        try await client.send(WalletBalanceEndpoint())
    }

    public func fetchSubscription() async throws -> SubscriptionStatus {
        try await client.send(SubscriptionEndpoint())
    }

    public func fetchPackages() async throws -> CoinPackageCatalog {
        try await client.send(WalletPackagesEndpoint())
    }

    public func unlock(
        episodeID: EpisodeID,
        expectedPrice: Int,
        idempotencyKey: String
    ) async throws -> UnlockOutcome {
        do {
            let wire = try await client.send(
                UnlockEndpoint(episodeID: episodeID, expectedPrice: expectedPrice, key: idempotencyKey)
            )
            return .unlocked(record: wire.unlock, wallet: wire.wallet, transactions: wire.transactions)
        } catch let error as AppError {
            switch error {
            case let .wallet(.insufficientCoins(shortfall)):
                // Canlı yol: tipli shortfall GERÇEK değerle taşınır (05 §4.5).
                return .insufficientCoins(shortfall: shortfall, wallet: nil)
            case .network(.server(status: 402)):
                // Geriye-uyum: gövdede kod yoksa ham 402; shortfall bilinmez.
                return .insufficientCoins(shortfall: nil, wallet: nil)
            case let .wallet(.priceChanged(currentPrice)):
                return .priceChanged(currentPrice: currentPrice)
            case .network(.server(status: 409)):
                return .priceChanged(currentPrice: nil)
            default:
                throw error
            }
        }
    }

    public func verifyPurchase(
        productID: String,
        jws: String,
        kind: PurchaseKind,
        idempotencyKey: String
    ) async throws -> VerifyOutcome {
        do {
            let wire = try await client.send(
                VerifyEndpoint(productID: productID, jws: jws, kind: kind, key: idempotencyKey)
            )
            if let subscription = wire.subscription {
                return .subscriptionUpdated(subscription)
            }
            if let granted = wire.granted, let wallet = wire.wallet {
                return .coinsCredited(granted: granted, wallet: wallet, transaction: wire.transaction)
            }
            if wire.granted != nil {
                // 2xx + `granted` VAR ama `wallet` snapshot yok: backend krediyi TAAHHÜT etti; snapshot
                // ayrı gelebilir. `.alreadyProcessed` semantiğiyle çağıran otoriter bakiyeyi refresh eder
                // ve transaction'ı finish eder (kredi kesin → re-verify döngüsü kırılır, kayıp yok).
                return .alreadyProcessed(wallet: nil, subscription: nil)
            }
            // Hiçbir beklenen alan yok (boş/bozuk 2xx): kredi KESİN DEĞİL → belirsizlikte parayı koru →
            // doğrulama başarısız olarak yüzer (çağıran pendingRetry, unfinished KALIR).
            throw AppError.wallet(.receiptValidationFailed)
        } catch let error as AppError {
            switch error {
            case .wallet(.receiptAlreadyProcessed):
                // TİPLİ 409 RECEIPT_ALREADY_PROCESSED (idempotent tekrar): başarı say. Snapshot zarftan
                // gelmez → çağıran refresh eder + finish. YALNIZ bu tipli kod başarıya eşlenir.
                return .alreadyProcessed(wallet: nil, subscription: nil)
            case .wallet(.receiptInvalid):
                // TİPLİ 422 RECEIPT_INVALID: makbuz gerçekten geçersiz → TERMİNAL (kredi asla gelmez).
                // Çağıran transaction'ı finish eder (sonsuz re-verify döngüsü kırılır, kredi yok).
                return .invalidReceipt
            default:
                // Tanınmayan/çıplak 409 · 422 (ve diğer HTTP) BAŞARI SENTEZLEMEZ. Belirsizlikte parayı
                // koru: tipli olarak YÜZER → koordinatör pendingRetry, transaction unfinished KALIR.
                throw error
            }
        }
    }
}
