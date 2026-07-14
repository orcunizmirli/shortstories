import AppFoundation
import Testing
@testable import WalletKit

/// Satın alma durum makinesi (06 §7.4 / §4.9): PurchaseFlowResult → faz eşlemesi.
struct StorePurchasePhaseTests {
    private let pid = "com.shortseries.coins.tier3"

    @Test func completedBasari() {
        #expect(StorePurchasePhase.resolve(.completed(transactionID: "txn_1"), productID: pid) == .success(productID: pid))
    }

    @Test func iptalSessizceIdle() {
        // 06 §7.5: userCancelled hata göstermez → idle.
        #expect(StorePurchasePhase.resolve(.cancelled, productID: pid) == .idle)
    }

    @Test func pendingAskToBuy() {
        #expect(StorePurchasePhase.resolve(.pending, productID: pid) == .pending(productID: pid))
    }

    @Test func verificationPendingGecikenKredi() {
        #expect(StorePurchasePhase.resolve(.verificationPending, productID: pid) == .verificationPending(productID: pid))
    }

    @Test func invalidReceiptDestekAkisi() {
        #expect(StorePurchasePhase.resolve(.invalidReceipt, productID: pid) == .invalidReceipt(productID: pid))
    }

    @Test func failedHata() {
        #expect(StorePurchasePhase.resolve(.failed(.network(.offline)), productID: pid) == .failed(productID: pid))
    }

    @Test func purchasingBayraklari() {
        let phase = StorePurchasePhase.purchasing(productID: pid)
        #expect(phase.isPurchasing)
        #expect(phase.inFlightProductID == pid)
        #expect(phase.creditedProductID == nil)
        #expect(!StorePurchasePhase.idle.isPurchasing)
    }

    @Test func successCreditedProductID() {
        #expect(StorePurchasePhase.success(productID: pid).creditedProductID == pid)
        #expect(!StorePurchasePhase.success(productID: pid).isPurchasing)
    }

    // MARK: - Çift satın alma koruması (06 §7.5): pending penceresi de kapsanır

    @Test func preventsNewPurchaseUcustaVePendingKapsar() {
        #expect(StorePurchasePhase.purchasing(productID: pid).preventsNewPurchase)
        #expect(StorePurchasePhase.pending(productID: pid).preventsNewPurchase)
        #expect(!StorePurchasePhase.idle.preventsNewPurchase)
        #expect(!StorePurchasePhase.success(productID: pid).preventsNewPurchase)
        #expect(!StorePurchasePhase.verificationPending(productID: pid).preventsNewPurchase)
        #expect(!StorePurchasePhase.failed(productID: pid).preventsNewPurchase)
        #expect(!StorePurchasePhase.invalidReceipt(productID: pid).preventsNewPurchase)
    }

    // MARK: - Banner davranışı (06 §4.6): terminal hata/destek KALICI, geçici bilgi auto-dismiss

    @Test func bannerIdleVeUcustaYok() {
        #expect(StorePurchasePhase.idle.banner == nil)
        #expect(StorePurchasePhase.purchasing(productID: pid).banner == nil)
    }

    @Test func bannerBasariVeVerificationAutoDismiss() {
        #expect(StorePurchasePhase.success(productID: pid).banner?.autoDismisses == true)
        #expect(StorePurchasePhase.verificationPending(productID: pid).banner?.autoDismisses == true)
    }

    @Test func bannerPendingFailedInvalidReceiptKalici() {
        #expect(StorePurchasePhase.pending(productID: pid).banner?.autoDismisses == false)
        #expect(StorePurchasePhase.failed(productID: pid).banner?.autoDismisses == false)
        let invalid = StorePurchasePhase.invalidReceipt(productID: pid).banner
        #expect(invalid?.autoDismisses == false)
        #expect(invalid?.requiresSupport == true)
        #expect(invalid?.tone == .danger)
    }
}
