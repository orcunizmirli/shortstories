import Foundation

/// StoreKit `Transaction`'ın (cihazda imza-doğrulanmış) taşıma-bağımsız değer temsili.
/// `jws` = `jwsRepresentation` — backend'e `POST /iap/verify` ile gönderilecek imzalı yük.
/// StoreKit tiplerini port sınırından geçirmemek için kullanılır (R6).
public struct VerifiedTransaction: Sendable, Equatable {
    public let id: UInt64
    public let originalID: UInt64
    public let productID: String
    public let jws: String
    public let kind: PurchaseKind
    public let purchaseDate: Date
    public let expirationDate: Date?
    /// İade/revoke ise dolu (06 §4.4): backend V2 ile zaten bilir, istemci refresh + finish eder.
    public let revocationDate: Date?
    public let isUpgraded: Bool
    public let appAccountToken: UUID?
    public let ownershipType: OwnershipType

    public init(
        id: UInt64,
        originalID: UInt64,
        productID: String,
        jws: String,
        kind: PurchaseKind,
        purchaseDate: Date,
        expirationDate: Date?,
        revocationDate: Date?,
        isUpgraded: Bool,
        appAccountToken: UUID?,
        ownershipType: OwnershipType
    ) {
        self.id = id
        self.originalID = originalID
        self.productID = productID
        self.jws = jws
        self.kind = kind
        self.purchaseDate = purchaseDate
        self.expirationDate = expirationDate
        self.revocationDate = revocationDate
        self.isUpgraded = isUpgraded
        self.appAccountToken = appAccountToken
        self.ownershipType = ownershipType
    }

    /// Idempotency anahtarı (05 §4.6 önerisi): `iap-<originalTransactionId>-<transactionId>`.
    public var idempotencyKey: String {
        "iap-\(originalID)-\(id)"
    }

    /// Aile paylaşımı KAPALI (06 §4.7): bu görülürse savunmacı olarak reddedilir.
    public var isFamilyShared: Bool {
        ownershipType == .familyShared
    }
}

public enum OwnershipType: String, Sendable, Equatable {
    case purchased
    case familyShared
}
