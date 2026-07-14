import AppFoundation

// WalletKit Endpoint tanımları (03 §8.1: Endpoint feature'da yaşar; taşıma AppFoundation'da).
// Path'ler /v1 öneki İÇERMEZ (baseURL sahibi). Para etkili POST'lar Idempotency-Key taşır ve
// böylece otomatik-retry için idempotent olur (03 §8.3, 05 §9).

/// `GET /wallet` (05 §4.5 #13).
struct WalletBalanceEndpoint: Endpoint {
    typealias Response = WalletSnapshot

    var path: String {
        "/wallet"
    }

    var method: HTTPMethod {
        .get
    }
}

/// `GET /subscription` (05 §4.1 #17).
struct SubscriptionEndpoint: Endpoint {
    typealias Response = SubscriptionStatus

    var path: String {
        "/subscription"
    }

    var method: HTTPMethod {
        .get
    }
}

/// `GET /wallet/packages` (05 §4.5 #32): stale-while-revalidate (bonus kademeleri değişebilir).
struct WalletPackagesEndpoint: Endpoint {
    typealias Response = CoinPackageCatalog

    var path: String {
        "/wallet/packages"
    }

    var method: HTTPMethod {
        .get
    }

    var cachePolicy: APICachePolicy {
        .staleWhileRevalidate
    }
}

/// `POST /wallet/unlock` (05 §4.5 #15) — Idempotency-Key zorunlu.
struct UnlockEndpoint: Endpoint {
    typealias Response = UnlockResponseWire

    struct RequestBody: Encodable, Sendable {
        let episodeId: String
        let expectedPrice: Int
    }

    let episodeID: EpisodeID
    let expectedPrice: Int
    let key: String

    var path: String {
        "/wallet/unlock"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        RequestBody(episodeId: episodeID.rawValue, expectedPrice: expectedPrice)
    }

    var idempotencyKey: String? {
        key
    }

    /// Cüzdan/satın alma ucu (03 §8.3 + RetryPolicy tablosu): OTOMATİK retry YOK. 5xx/timeout'ta
    /// taşıma katmanı POST'u tekrar ETMEZ — kurtarma kullanıcı-tetikli yeniden denemedir. Idempotency-Key
    /// varlığında bile sıkı-döngü retry çift-harcama yarış penceresini açardı; `.never` onu kapatır.
    var retryPolicy: RetryPolicy {
        .never
    }
}

/// `POST /iap/verify` (05 §4.6 #16) — Idempotency-Key zorunlu (transactionId türevi).
struct VerifyEndpoint: Endpoint {
    typealias Response = VerifyResponseWire

    struct RequestBody: Encodable, Sendable {
        let productId: String
        let jwsTransaction: String
        let kind: String
    }

    let productID: String
    let jws: String
    let kind: PurchaseKind
    let key: String

    var path: String {
        "/iap/verify"
    }

    var method: HTTPMethod {
        .post
    }

    var body: (any Encodable)? {
        RequestBody(productId: productID, jwsTransaction: jws, kind: kind.rawValue)
    }

    var idempotencyKey: String? {
        key
    }

    /// Cüzdan/satın alma ucu (03 §8.3 + RetryPolicy tablosu): OTOMATİK retry YOK. Doğrulama 5xx/timeout'ta
    /// başarısızsa taşıma katmanı POST'u tekrar ETMEZ; transaction unfinished kalır ve StoreKit unfinished
    /// kuyruğundan (retryUnfinished / next-launch) yeniden denenir. `.never` çift-kredi yarış penceresini daraltır.
    var retryPolicy: RetryPolicy {
        .never
    }
}

// MARK: - Wire yanıt zarfları

/// `POST /wallet/unlock` 200 zarfı (05 §4.5). `playback` bloğu (hızlı başlatma) PlayerKit'in
/// alanıdır; cüzdan çekirdeği onu görmezden gelir (opsiyonel, decode edilmez).
struct UnlockResponseWire: Decodable, Sendable {
    let unlock: UnlockRecord
    let wallet: WalletSnapshot
    let transactions: [CoinTransaction]

    private enum CodingKeys: String, CodingKey {
        case unlock
        case wallet
        case transactions
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unlock = try container.decode(UnlockRecord.self, forKey: .unlock)
        wallet = try container.decode(WalletSnapshot.self, forKey: .wallet)
        transactions = try container.decodeIfPresent([CoinTransaction].self, forKey: .transactions) ?? []
    }
}

/// `POST /iap/verify` 200 zarfı (05 §4.6): coin ise `granted`+`wallet`(+`transaction`),
/// abonelik ise `subscription`.
struct VerifyResponseWire: Decodable, Sendable {
    let granted: GrantedCoins?
    let wallet: WalletSnapshot?
    let transaction: CoinTransaction?
    let subscription: SubscriptionStatus?
}
