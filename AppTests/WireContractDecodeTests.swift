import AppFoundation
import Foundation
import LibraryKit
import RewardsKit
import XCTest
@testable import ShortSeriesApp

/// docs/05 SÖZLEŞME ZARFLARININ decode/encode kilidi (SS wire-contract review). Her test, 05'teki
/// ÖRNEK JSON'ı adaptör wire-DTO'suna decode/encode eder: yanlış (eski) DTO'da RED, düzeltmede GREEN.
/// Bu testler veri/coin kaybı bug'larını (yanlış zarf anahtarı / eksik alan / çökme) regresyona karşı
/// sabitler. Ağ KURULMAZ — yalnız `JSONDecoder/Encoder.shortSeriesDefault()` sınır dönüşümü doğrulanır.
final class WireContractDecodeTests: XCTestCase {
    private let decoder = JSONDecoder.shortSeriesDefault()
    private let encoder = JSONEncoder.shortSeriesDefault()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - #1 POST /playback/progress istek gövdesi zarfı: `entries` (05 §4.4)

    func testProgressUploadBodyUsesEntriesKey() throws {
        let record = WatchProgressRecord(
            episodeID: EpisodeID("ep_5410be"),
            seriesID: SeriesID("srs_9f2c1a"),
            positionSec: 61.4,
            durationSec: 92,
            completed: false,
            watchedAt: Date(timeIntervalSince1970: 1000)
        )
        let body = ProgressUploadRequestBody(entries: [WatchProgressWire(record: record)])
        let json = try String(decoding: encoder.encode(body), as: UTF8.self)
        // Sözleşme zarf anahtarı `entries`; eski `items` sunucuca sessizce yok sayılırdı (ilerleme kaybı).
        XCTAssertTrue(json.contains("\"entries\""), "istek gövdesi `entries` zarfı taşımalı: \(json)")
        XCTAssertFalse(json.contains("\"items\""), "eski `items` anahtarı kalmamalı: \(json)")
        XCTAssertTrue(json.contains("\"episodeId\":\"ep_5410be\""))
    }

    // MARK: - #2 GET /me/history?cursor= yanıt zarfı: `{ items, nextCursor }` (05 §7.1)

    func testHistoryListDecodesItemsAndNextCursor() throws {
        let json = """
        { "items": [
            { "episodeId": "ep_5410be", "seriesId": "srs_9f2c1a", "positionSec": 61.4,
              "durationSec": 92.0, "completed": false, "watchedAt": "2026-07-11T09:31:02Z" }
          ], "nextCursor": "eyJvZmZzZXQiOiIxMCJ9", "ttlSec": 300 }
        """
        let wire = try decode(HistoryListWire.self, json)
        XCTAssertEqual(wire.items.count, 1)
        XCTAssertEqual(wire.items.first?.record.episodeID, EpisodeID("ep_5410be"))
        XCTAssertEqual(wire.nextCursor, "eyJvZmZzZXQiOiIxMCJ9")
    }

    func testHistoryListTreatsNullAndAbsentCursorAsLastPage() throws {
        let nullCursor = try decode(HistoryListWire.self, #"{ "items": [], "nextCursor": null }"#)
        XCTAssertNil(nullCursor.nextCursor, "nextCursor:null → son sayfa")
        let absentCursor = try decode(HistoryListWire.self, #"{ "items": [] }"#)
        XCTAssertNil(absentCursor.nextCursor, "nextCursor yoksa → son sayfa (çökme yok)")
    }

    // MARK: - #3 GET /missions yanıt zarfı: `missions` (05 satır 941)

    func testMissionListDecodesMissionsKey() throws {
        let json = """
        { "missions": [
            { "id": "m1", "kind": "watchMinutes", "title": "10 dk izle", "rewardCoins": 20,
              "target": 10, "progress": 4, "state": "inProgress", "resetPolicy": "daily", "expiresAt": null }
          ] }
        """
        let wire = try decode(MissionListWire.self, json)
        XCTAssertEqual(wire.missions.count, 1)
        XCTAssertEqual(wire.missions.first?.task.id, "m1")
        XCTAssertEqual(wire.missions.first?.task.kind, .watchMinutes)
    }

    // MARK: - #4 checkin/claim 200 zarfı: reward{coins,bucket,expiresAt} + checkin + wallet (05 satır 930-936)

    func testCheckInClaimResultDerivesBalanceFromWalletAndMapsBucket() throws {
        let json = """
        {
          "reward": { "coins": 30, "bucket": "earned", "expiresAt": "2026-08-10T00:00:00Z" },
          "checkin": { "cycleDay": 3, "todayClaimed": true, "todayReward": 30,
                       "schedule": [ { "day": 1, "coins": 10, "claimed": true } ],
                       "streakDays": 3, "streakBonusAt": 7, "streakBonusCoins": 100 },
          "wallet": { "purchasedCoins": 105, "earnedCoins": 30, "earnedExpiringSoon": null,
                      "firstTopUpEligible": false, "updatedAt": "2026-07-11T09:00:00Z", "version": 125 }
        }
        """
        let result = try decode(CheckInClaimResultWire.self, json).result
        XCTAssertEqual(result.reward.coins, 30)
        // `earned` bucket düzenli ödül → isStreakBonus false (05'te reward.bucket daima "earned").
        XCTAssertFalse(result.reward.isStreakBonus)
        XCTAssertEqual(result.reward.expiresAt, isoDate("2026-08-10T00:00:00Z"))
        XCTAssertEqual(result.checkin.cycleDay, 3)
        XCTAssertTrue(result.checkin.todayClaimed)
        // Server-otoriter bakiye: wallet(purchased 105 + earned 30) = 135; üst-seviye coinBalance YOK.
        XCTAssertEqual(result.coinBalance, 135)
    }

    func testClaimedRewardMapsStreakBonusBucketToTrue() throws {
        // Sunucu ileride streak bonusunu ayrı bucket ile işaretlerse doğru eşlenmeli (ileri-uyum).
        let wire = try decode(
            ClaimedRewardWire.self,
            #"{ "coins": 100, "bucket": "streakBonus", "expiresAt": null }"#
        )
        XCTAssertTrue(wire.reward.isStreakBonus)
        XCTAssertEqual(wire.reward.coins, 100)
    }

    func testClaimedRewardMissingBucketDoesNotCrash() throws {
        // `bucket` opsiyonel: eksik/tanınmayan değer decode'u çökertmez (05 §1 kural 10).
        let wire = try decode(ClaimedRewardWire.self, #"{ "coins": 15, "expiresAt": null }"#)
        XCTAssertFalse(wire.reward.isStreakBonus)
        XCTAssertEqual(wire.reward.coins, 15)
    }

    // MARK: - #4 mission/claim 200 zarfı: reward + mission + wallet (05 satır 941 "aynı kalıp")

    func testMissionClaimResultDerivesBalanceFromWallet() throws {
        let json = """
        {
          "reward": { "coins": 20, "bucket": "earned", "expiresAt": null },
          "mission": { "id": "m1", "kind": "watchMinutes", "title": "10 dk izle", "rewardCoins": 20,
                       "target": 10, "progress": 10, "state": "claimed", "resetPolicy": "daily", "expiresAt": null },
          "wallet": { "purchasedCoins": 50, "earnedCoins": 70, "version": 42 }
        }
        """
        let result = try decode(MissionClaimResultWire.self, json).result
        XCTAssertEqual(result.reward.coins, 20)
        XCTAssertFalse(result.reward.isStreakBonus)
        XCTAssertEqual(result.task.id, "m1")
        XCTAssertEqual(result.task.state, .claimed)
        XCTAssertEqual(result.coinBalance, 120) // 50 + 70
    }

    // MARK: - #6 EmptyResponse: geçerli JSON gövdeyi içerik-okumadan başarılı kabul eder

    func testEmptyResponseAcceptsEmptyObjectAndIgnoredBody() throws {
        // `{}` (favorites) ve `{ merged: [...] }` (progress upload 200) — ikisi de içerik okumadan geçer.
        XCTAssertNoThrow(try decode(EmptyResponse.self, "{}"))
        XCTAssertNoThrow(try decode(
            EmptyResponse.self,
            #"{ "merged": [ { "episodeId": "ep_1", "positionSec": 1.0 } ] }"#
        ))
    }

    // MARK: - #5 TimezoneInterceptor: X-Timezone header HER isteğe (05 §2.9)

    func testTimezoneInterceptorAddsHeaderToEveryRequest() async throws {
        let interceptor = TimezoneInterceptor(timeZoneID: { "America/New_York" })
        let request = try URLRequest(url: XCTUnwrap(URL(string: "https://api.shortseries.app/v1/me/history")))
        // GET okuma bağlamı (requiresAuth) farketmez — header yine eklenir.
        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))
        XCTAssertEqual(adapted.value(forHTTPHeaderField: "X-Timezone"), "America/New_York")
    }

    // MARK: - Fixtures

    private func isoDate(_ raw: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)!
    }
}
