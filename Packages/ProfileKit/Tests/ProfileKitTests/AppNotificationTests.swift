import AppFoundation
import Foundation
import Testing
@testable import ProfileKit

@Suite("SS-144 AppNotification (wire decode + rota ayrımı)")
struct AppNotificationTests {
    private func decode(_ json: String) throws -> AppNotification {
        try JSONDecoder.shortSeriesDefault().decode(AppNotification.self, from: Data(json.utf8))
    }

    /// Test JSON'larındaki sabit zaman damgası (2026-07-11T09:31:02Z) — el-hesabı epoch yerine.
    private func canonicalDate(millis: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 11
        comps.hour = 9
        comps.minute = 31
        comps.second = 2
        comps.nanosecond = millis * 1_000_000
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: comps)!
    }

    // MARK: - Wire decode (camelCase birincil, 05 §1.7)

    @Test func decodesCamelCaseWireItem() throws {
        let notification = try decode(#"""
        {
          "id": "n_1",
          "type": "new_episode",
          "title": "Yeni bölüm",
          "body": "3. bölüm yayında",
          "createdAt": "2026-07-11T09:31:02.123Z",
          "route": "series/s1/episode/3",
          "isRead": false
        }
        """#)
        #expect(notification.id == NotificationID("n_1"))
        #expect(notification.type == .newEpisode)
        #expect(notification.title == "Yeni bölüm")
        #expect(notification.body == "3. bölüm yayında")
        #expect(notification.route == "series/s1/episode/3")
        #expect(notification.isRead == false)
        // ISO 8601 fractional saniye shortSeriesDefault ile okundu (float tolerans).
        let expected = canonicalDate(millis: 123)
        #expect(abs(notification.createdAt.timeIntervalSince1970 - expected.timeIntervalSince1970) < 0.001)
    }

    @Test func decodesNonFractionalDate() throws {
        let notification = try decode(#"""
        { "id": "n", "type": "reward", "title": "t", "body": "b",
          "createdAt": "2026-07-11T09:31:02Z", "route": "rewards", "isRead": true }
        """#)
        #expect(notification.createdAt == canonicalDate())
        #expect(notification.isRead == true)
    }

    // MARK: - Tip hizası + savunmacı bilinmeyen

    @Test func decodesAllKnownTypesAlignedWithPushTypes() throws {
        let cases: [(String, NotificationType)] = [
            ("new_episode", .newEpisode),
            ("continue", .continueWatching),
            ("coin_reward", .coinReward),
            ("recommendation", .recommendation),
            ("reward", .reward),
            ("campaign", .campaign)
        ]
        for (raw, type) in cases {
            let json = #"""
            { "id": "x", "type": "\#(raw)", "title": "t", "body": "b",
              "createdAt": "2026-07-11T09:31:02Z", "route": "r", "isRead": false }
            """#
            let decoded = try decode(json)
            #expect(decoded.type == type)
        }
    }

    @Test func unknownServerTypeFallsBackDefensivelyAndPreservesItem() throws {
        let notification = try decode(#"""
        { "id": "n_9", "type": "flash_sale_2027", "title": "t", "body": "b",
          "createdAt": "2026-07-11T09:31:02Z", "route": "store/coins", "isRead": false }
        """#)
        // Öğe DÜŞÜRÜLMEZ (PushPayload'ın nil gate'inden ayrışır); jenerik `.unknown` tipiyle korunur.
        #expect(notification.type == .unknown)
        #expect(notification.route == "store/coins")
    }

    // MARK: - Rota ayrımı (App fallback işareti, §8.4)

    @Test func hasRouteTrueForNonEmptyRoute() {
        #expect(NotificationFactory.make(id: "a", route: "series/s1").hasRoute)
    }

    @Test func hasRouteFalseForEmptyOrWhitespaceRoute() {
        #expect(NotificationFactory.make(id: "a", route: "").hasRoute == false)
        #expect(NotificationFactory.make(id: "b", route: "   \n").hasRoute == false)
    }

    // MARK: - withRead değer semantiği

    @Test func withReadReturnsCopyLeavingOriginalUntouched() {
        let original = NotificationFactory.make(id: "a", isRead: false)
        let read = original.withRead(true)
        #expect(read.isRead == true)
        #expect(original.isRead == false)
        #expect(read.id == original.id)
    }
}
