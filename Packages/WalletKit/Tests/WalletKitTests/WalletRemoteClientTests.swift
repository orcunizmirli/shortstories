import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import WalletKit

/// Canlı cüzdan/IAP istemcisi (SS-095): AppFoundation'ın tipli-zenginleştirilmiş `AppError`
/// hatalarını sunucu-kararlı `UnlockOutcome`/`VerifyOutcome`'a çevirir. Kabul: canlı yol
/// shortfall/currentPrice'ı GERÇEK değerle taşır (nil DEĞİL); gövde kodsuzsa ham-status fallback.
struct WalletRemoteClientTests {
    private func makeClient() -> (WalletRemoteClient, MockAPIClient) {
        let api = MockAPIClient()
        return (WalletRemoteClient(client: api), api)
    }

    // MARK: - unlock canlı-yol eşlemesi (05 §4.5)

    @Test func insufficientCoinsShortfalliGercekDegerleTasir() async throws {
        let (client, api) = makeClient()
        api.stub("/wallet/unlock", throwing: .wallet(.insufficientCoins(shortfall: 30)))

        let outcome = try await client.unlock(
            episodeID: EpisodeID("ep_9"), expectedPrice: 60, idempotencyKey: "k1"
        )

        #expect(outcome == .insufficientCoins(shortfall: 30, wallet: nil))
    }

    @Test func priceChangedCurrentPriceiGercekDegerleTasir() async throws {
        let (client, api) = makeClient()
        api.stub("/wallet/unlock", throwing: .wallet(.priceChanged(currentPrice: 75)))

        let outcome = try await client.unlock(
            episodeID: EpisodeID("ep_9"), expectedPrice: 60, idempotencyKey: "k1"
        )

        #expect(outcome == .priceChanged(currentPrice: 75))
    }

    @Test func hamDortYuzIkiFallbackNilShortfall() async throws {
        // Gövde kodsuz ham 402 → geriye-uyum fallback; shortfall bilinmez.
        let (client, api) = makeClient()
        api.stub("/wallet/unlock", throwing: .network(.server(status: 402)))

        let outcome = try await client.unlock(
            episodeID: EpisodeID("ep_9"), expectedPrice: 60, idempotencyKey: "k1"
        )

        #expect(outcome == .insufficientCoins(shortfall: nil, wallet: nil))
    }

    @Test func eslenmeyenHataTipliOlarakYuzer() async {
        // Ağ/taşıma hatası (offline) iş sonucuna çevrilmez; tipli olarak YÜZER (03 §10.1).
        let (client, api) = makeClient()
        api.stub("/wallet/unlock", throwing: .network(.offline))

        await #expect(throws: AppError.network(.offline)) {
            _ = try await client.unlock(episodeID: EpisodeID("ep_9"), expectedPrice: 60, idempotencyKey: "k1")
        }
    }

    // MARK: - verify canlı-yol eşlemesi (05 §4.6)

    @Test func receiptAlreadyProcessedAlreadyProcessedaEslenir() async throws {
        let (client, api) = makeClient()
        api.stub("/iap/verify", throwing: .wallet(.receiptAlreadyProcessed(originalTransactionID: "txn_1")))

        let outcome = try await client.verifyPurchase(
            productID: "com.shortseries.coins.tier1", jws: "jws", kind: .consumable, idempotencyKey: "k1"
        )

        #expect(outcome == .alreadyProcessed(wallet: nil, subscription: nil))
    }

    @Test func receiptInvalidInvalidReceiptaEslenir() async throws {
        // TİPLİ 422 RECEIPT_INVALID → terminal .invalidReceipt (kredi asla gelmez; çağıran finish eder).
        let (client, api) = makeClient()
        api.stub("/iap/verify", throwing: .wallet(.receiptInvalid))

        let outcome = try await client.verifyPurchase(
            productID: "com.shortseries.coins.tier1", jws: "jws", kind: .consumable, idempotencyKey: "k1"
        )

        #expect(outcome == .invalidReceipt)
    }

    // MARK: - Para-güvenliği: belirsiz HTTP → başarı SENTEZLENMEZ (unfinished KALIR)

    @Test func hamDortYuzDokuzBasariSentezlemezTipliYuzer() async {
        // PARA KAYBI koruması: tanınmayan/çıplak 409 (RECEIPT_ALREADY_PROCESSED DEĞİL) başarı
        // SAYILMAZ. Eski davranış .alreadyProcessed'a eşliyordu → koordinatör kredi yazılmadan
        // finish ediyordu → kullanıcı ödedi coin yok. Doğru: THROW → pendingRetry, unfinished KALIR.
        let (client, api) = makeClient()
        api.stub("/iap/verify", throwing: .network(.server(status: 409)))

        await #expect(throws: AppError.network(.server(status: 409))) {
            _ = try await client.verifyPurchase(
                productID: "com.shortseries.coins.tier1", jws: "jws", kind: .consumable, idempotencyKey: "k1"
            )
        }
    }

    @Test func hamDortYuzYirmiIkiTerminalDegilPendingRetryYuzer() async {
        // PARA/DÖNGÜ koruması: çıplak/tanınmayan 422 (RECEIPT_INVALID tipli DEĞİL) TERMİNAL sayılmaz —
        // geçici olabilir → THROW (pendingRetry). Yalnız TİPLİ RECEIPT_INVALID terminaldir.
        let (client, api) = makeClient()
        api.stub("/iap/verify", throwing: .network(.server(status: 422)))

        await #expect(throws: AppError.network(.server(status: 422))) {
            _ = try await client.verifyPurchase(
                productID: "com.shortseries.coins.tier1", jws: "jws", kind: .consumable, idempotencyKey: "k1"
            )
        }
    }

    @Test func grantedAmaWalletYokAlreadyProcessedaEslenir() async throws {
        // PARA/DÖNGÜ koruması: 2xx + granted VAR ama wallet snapshot yok. Backend krediyi TAAHHÜT
        // etti (granted); snapshot ayrı gelebilir. Eski davranış receiptValidationFailed atıp
        // pendingRetry döngüsüne sokuyordu (her açılış re-verify, asla kredilenmez). Doğru:
        // .alreadyProcessed → çağıran refresh() ile otoriter bakiyeyi çeker + finish (döngü kırılır).
        let (client, api) = makeClient()
        let json = Data("""
        { "granted": { "coins": 1200, "bonusCoins": 0, "firstPurchaseBonusApplied": false } }
        """.utf8)
        api.stub("/iap/verify", with: .success(json))

        let outcome = try await client.verifyPurchase(
            productID: "com.shortseries.coins.tier3", jws: "jws", kind: .consumable, idempotencyKey: "k1"
        )

        #expect(outcome == .alreadyProcessed(wallet: nil, subscription: nil))
    }

    @Test func bosIkiYuzGovdeBelirsizPendingRetryYuzer() async {
        // Belirsizlikte parayı koru: boş/bozuk 2xx (granted de wallet de subscription da yok) →
        // kredi kesin DEĞİL → receiptValidationFailed atılır (pendingRetry, unfinished kalır).
        let (client, api) = makeClient()
        api.stub("/iap/verify", with: .success(Data("{}".utf8)))

        await #expect(throws: AppError.wallet(.receiptValidationFailed)) {
            _ = try await client.verifyPurchase(
                productID: "com.shortseries.coins.tier1", jws: "jws", kind: .consumable, idempotencyKey: "k1"
            )
        }
    }
}
