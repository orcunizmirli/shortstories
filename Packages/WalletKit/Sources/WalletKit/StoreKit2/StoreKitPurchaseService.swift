import AppFoundation
import Foundation
import StoreKit

/// Canlı StoreKit 2 satın alma / transaction servisi (SS-090/091). `product.purchase()`,
/// `Transaction.updates`/`.unfinished`/`.currentEntitlements`, `AppStore.sync()` burada hapsolur
/// (R6). Ham `Transaction`'lar `finish()` için `id` ile saklanır; consumable yalnız backend
/// onayından SONRA finish edilir (06 §4.1) — bu servis finish'i çağıranın kararına bırakır.
public actor StoreKitPurchaseService: PurchaseServicing {
    private let products: StoreKitProductService
    /// `finish(transactionID:)` için tutulan ham, imza-doğrulanmış transaction'lar.
    private var pending: [UInt64: Transaction] = [:]

    public init(products: StoreKitProductService) {
        self.products = products
    }

    public func purchase(productID: String, appAccountToken: UUID) async throws -> PurchaseResult {
        guard let product = try await resolveProduct(productID) else {
            throw AppError.wallet(.purchaseFailed(.unknown))
        }
        let result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        switch result {
        case let .success(verification):
            guard case let .verified(transaction) = verification else {
                throw AppError.wallet(.receiptValidationFailed)
            }
            pending[transaction.id] = transaction
            return .success(VerifiedTransaction(transaction, jws: verification.jwsRepresentation))
        case .userCancelled:
            return .userCancelled
        case .pending:
            return .pending
        @unknown default:
            throw AppError.wallet(.purchaseFailed(.unknown))
        }
    }

    public func finish(transactionID: UInt64) async {
        guard let transaction = pending[transactionID] else { return }
        await transaction.finish()
        pending[transactionID] = nil
    }

    public func unfinishedTransactions() async -> [VerifiedTransaction] {
        var result: [VerifiedTransaction] = []
        for await verification in Transaction.unfinished {
            if let verified = ingest(verification) {
                result.append(verified)
            }
        }
        return result
    }

    public nonisolated func transactionUpdates() -> AsyncStream<VerifiedTransaction> {
        AsyncStream { continuation in
            let task = Task {
                for await verification in Transaction.updates {
                    if let verified = await self.ingestAsync(verification) {
                        continuation.yield(verified)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func currentEntitlements() async -> [VerifiedTransaction] {
        var result: [VerifiedTransaction] = []
        for await verification in Transaction.currentEntitlements {
            guard case let .verified(transaction) = verification else { continue }
            result.append(VerifiedTransaction(transaction, jws: verification.jwsRepresentation))
        }
        return result
    }

    public func sync() async throws {
        try await AppStore.sync()
    }

    // MARK: - Yardımcılar

    private func resolveProduct(_ productID: String) async throws -> Product? {
        if let cached = await products.rawProduct(id: productID) {
            return cached
        }
        _ = try await products.loadProducts(ids: [productID])
        return await products.rawProduct(id: productID)
    }

    /// `.verified` transaction'ı ham olarak saklar (finish için) ve değer temsilini döner.
    private func ingest(_ verification: VerificationResult<Transaction>) -> VerifiedTransaction? {
        guard case let .verified(transaction) = verification else { return nil }
        pending[transaction.id] = transaction
        return VerifiedTransaction(transaction, jws: verification.jwsRepresentation)
    }

    private func ingestAsync(_ verification: VerificationResult<Transaction>) async -> VerifiedTransaction? {
        ingest(verification)
    }
}

extension VerifiedTransaction {
    init(_ transaction: Transaction, jws: String) {
        let kind: PurchaseKind = transaction.productType == .autoRenewable ? .subscription : .consumable
        let ownership: OwnershipType = transaction.ownershipType == .familyShared ? .familyShared : .purchased
        self.init(
            id: transaction.id,
            originalID: transaction.originalID,
            productID: transaction.productID,
            jws: jws,
            kind: kind,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isUpgraded: transaction.isUpgraded,
            appAccountToken: transaction.appAccountToken,
            ownershipType: ownership
        )
    }
}
