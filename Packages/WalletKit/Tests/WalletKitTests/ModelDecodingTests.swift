import AppFoundation
import Foundation
import Testing
@testable import WalletKit

/// Wire decode testleri (05 §2.5-2.8, §4.5-4.6). Canlı `APIClient` ile aynı decoder kullanılır
/// (fractional ISO 8601 tarih stratejisi — JSONCoding).
struct ModelDecodingTests {
    private let decoder = JSONDecoder.shortSeriesDefault()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    @Test func walletSnapshotDecode() throws {
        let json = """
        { "purchasedCoins": 120, "earnedCoins": 45,
          "earnedExpiringSoon": { "amount": 30, "expiresAt": "2026-07-14T00:00:00Z" },
          "firstTopUpEligible": false,
          "updatedAt": "2026-07-11T09:00:00Z", "version": 118 }
        """
        let snapshot = try decode(WalletSnapshot.self, json)

        #expect(snapshot.balance == CoinBalance(purchasedCoins: 120, earnedCoins: 45))
        #expect(snapshot.balance.totalCoins == 165)
        #expect(snapshot.earnedExpiringSoon?.amount == 30)
        #expect(!snapshot.firstTopUpEligible)
        #expect(snapshot.version == 118)
    }

    @Test func walletSnapshotEarnedExpiringSoonOpsiyonel() throws {
        let json = """
        { "purchasedCoins": 0, "earnedCoins": 0, "firstTopUpEligible": true,
          "updatedAt": "2026-07-11T09:00:00.500Z", "version": 1 }
        """
        let snapshot = try decode(WalletSnapshot.self, json)

        #expect(snapshot.earnedExpiringSoon == nil)
        #expect(snapshot.earnedBuckets.isEmpty) // alan yoksa boş (WIRE TODO: sunucu henüz göndermiyor)
        #expect(snapshot.firstTopUpEligible)
    }

    @Test func walletSnapshotEarnedBucketsDecode() throws {
        // İleriye-dönük sözleşme (05 §2.5 WIRE TODO): sunucu çok-lotlu earnedBuckets gönderirse decode.
        let json = """
        { "purchasedCoins": 120, "earnedCoins": 55, "firstTopUpEligible": false,
          "earnedBuckets": [
            { "amount": 30, "expiresAt": "2026-07-14T00:00:00Z" },
            { "amount": 25, "expiresAt": "2026-07-20T00:00:00Z" }
          ],
          "updatedAt": "2026-07-11T09:00:00Z", "version": 130 }
        """
        let snapshot = try decode(WalletSnapshot.self, json)

        #expect(snapshot.earnedBuckets.count == 2)
        #expect(snapshot.earnedBuckets[0].amount == 30)
        #expect(snapshot.earnedBuckets[1].amount == 25)
        // Türetilen yaklaşan-vade (7 gün eşiği, now = grant öncesi): yalnız ilk lot pencerede.
        let now = Date(timeIntervalSince1970: 1_783_728_000) // 2026-07-11 00:00 UTC
        let notice = EarnedCoinExpiryPlanner.upcomingExpiry(buckets: snapshot.earnedBuckets, now: now)
        #expect(notice?.coins == 30)
    }

    @Test func unlockResponseDecodeIkiLedgerSatiri() throws {
        // 05 §4.5: earned+purchased karışık düşüş → iki transaction satırı.
        let json = """
        { "unlock": { "id": "ulk_3c9d10", "episodeId": "ep_5410be", "seriesId": "srs_9f2c1a",
            "method": "coins", "coinsSpent": 60, "unlockedAt": "2026-07-11T09:32:00Z" },
          "wallet": { "purchasedCoins": 105, "earnedCoins": 0, "firstTopUpEligible": false,
            "updatedAt": "2026-07-11T09:32:00Z", "version": 119 },
          "transactions": [
            { "id": "txn_901", "type": "episodeUnlock", "amount": -45, "bucket": "earned",
              "balanceAfter": 120, "refId": "ep_5410be", "note": null, "createdAt": "2026-07-11T09:32:00Z" },
            { "id": "txn_902", "type": "episodeUnlock", "amount": -15, "bucket": "purchased",
              "balanceAfter": 105, "refId": "ep_5410be", "note": null, "createdAt": "2026-07-11T09:32:00Z" }
          ],
          "playback": { "episodeId": "ep_5410be", "playbackURL": "https://x", "expiresAt": "2026-07-11T12:00:00Z", "drm": null }
        }
        """
        let wire = try decode(UnlockResponseWire.self, json)

        #expect(wire.unlock.episodeID == EpisodeID("ep_5410be"))
        #expect(wire.unlock.seriesID == SeriesID("srs_9f2c1a"))
        #expect(wire.unlock.method == .coins)
        #expect(wire.wallet.version == 119)
        #expect(wire.transactions.count == 2)
        #expect(wire.transactions[0].bucket == .earned)
        #expect(wire.transactions[1].bucket == .purchased)
        #expect(wire.transactions[0].amount == -45)
    }

    @Test func verifyCoinResponseDecode() throws {
        let json = """
        { "granted": { "coins": 1000, "bonusCoins": 200, "firstPurchaseBonusApplied": false },
          "wallet": { "purchasedCoins": 1205, "earnedCoins": 0, "firstTopUpEligible": false,
            "updatedAt": "2026-07-11T09:00:00Z", "version": 124 },
          "transaction": { "id": "txn_905", "type": "iapPurchase", "amount": 1200, "bucket": "purchased",
            "balanceAfter": 1205, "refId": "com.shortseries.coins.tier3", "note": null, "createdAt": "2026-07-11T09:00:00Z" } }
        """
        let wire = try decode(VerifyResponseWire.self, json)

        #expect(wire.granted?.coins == 1000)
        #expect(wire.granted?.bonusCoins == 200)
        #expect(wire.wallet?.version == 124)
        #expect(wire.transaction?.type == .iapPurchase)
        #expect(wire.subscription == nil)
    }

    @Test func verifySubscriptionResponseDecode() throws {
        let json = """
        { "subscription": { "isVIP": true, "plan": "weekly", "expiresAt": "2026-07-18T09:35:00Z",
          "willAutoRenew": true, "isInGracePeriod": false, "isInIntroOffer": true,
          "dailyBonusCoins": 50, "dailyBonusClaimedToday": false } }
        """
        let wire = try decode(VerifyResponseWire.self, json)

        #expect(wire.subscription?.isVIP == true)
        #expect(wire.subscription?.plan == .weekly)
        #expect(wire.subscription?.isInIntroOffer == true)
        #expect(wire.granted == nil)
    }

    @Test func subscriptionPlanNullIkenNil() throws {
        let json = """
        { "isVIP": false, "plan": null, "expiresAt": null, "willAutoRenew": false,
          "isInGracePeriod": false, "isInIntroOffer": false, "dailyBonusCoins": 0, "dailyBonusClaimedToday": false }
        """
        let status = try decode(SubscriptionStatus.self, json)

        #expect(!status.isVIP)
        #expect(status.plan == nil)
        #expect(!status.grantsFullAccess)
    }

    @Test func bilinmeyenBucketVeTypeUnknownaDuser() throws {
        // 05 §12 kural 4: sunucu yeni enum değeri → decode hatası YOK, .unknown.
        let json = """
        { "id": "txn_x", "type": "loyaltyReward", "amount": 5, "bucket": "promo",
          "balanceAfter": 5, "refId": null, "note": null, "createdAt": "2026-07-11T09:00:00Z" }
        """
        let txn = try decode(CoinTransaction.self, json)

        #expect(txn.type == .unknown)
        #expect(txn.bucket == .unknown)
    }

    @Test func packagesCatalogDecode() throws {
        let json = """
        { "packages": [
            { "productId": "com.shortseries.coins.tier3", "baseCoins": 1000, "bonusPercent": 20,
              "bonusCoins": 200, "firstTopUpBonusCoins": 1000, "badge": "EN POPÜLER" }
          ], "firstTopUpEligible": true, "ttlSec": 600 }
        """
        let catalog = try decode(CoinPackageCatalog.self, json)

        #expect(catalog.packages.count == 1)
        #expect(catalog.packages[0].totalCoins == 1200)
        #expect(catalog.packages[0].firstTopUpTotalCoins == 2000)
        #expect(catalog.packages[0].badge == "EN POPÜLER")
        #expect(catalog.firstTopUpEligible)
    }
}
