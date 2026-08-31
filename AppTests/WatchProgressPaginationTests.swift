import AppFoundation
import AppFoundationTestSupport
import Foundation
import XCTest
@testable import ShortSeriesApp

/// App-integration hunt #2: `APIWatchProgressRemoting.fetchServerProgress` cursor-pagination'ı sunucu BOZUK
/// davranışına (değişmeyen non-empty `nextCursor`) karşı korunmalı — aynı sayfayı `maxHistoryPages`(50) kez
/// çekmek boşa round-trip'tir. Fix: cursor İLERLEMEDİYSE (`next == cursor`) döngü kırılır. App target CI dışı → yerel.
final class WatchProgressPaginationTests: XCTestCase {
    /// Stuck cursor: sunucu her istekte AYNI non-empty `nextCursor`'ı döndürür (path hep `/me/history`, cursor
    /// query'de → MockAPIClient aynı stub'ı verir) → fix cursor tekrarını görünce durur (nil-cursor + ilk tekrar
    /// = 2 istek). Fix olmadan döngü `maxHistoryPages`(50)'e dek aynı sayfayı çeker.
    func testStuckCursorStopsAfterRepeatInsteadOfMaxPages() async throws {
        let mock = MockAPIClient()
        mock.stub("/me/history", with: .success(historyPageJSON(nextCursor: "stuck")))

        _ = try await APIWatchProgressRemoting(client: mock).fetchServerProgress()

        XCTAssertEqual(mock.receivedEndpoints.count, 2, "stuck cursor: 2 istekte durmalı (fix'siz maxHistoryPages=50 tur)")
    }

    /// Normal tek sayfa (`nextCursor: null`) → tek istekte biter (fix normal sonlanmayı BOZMAZ — regresyon guard).
    func testSinglePageTerminatesInOneRequest() async throws {
        let mock = MockAPIClient()
        mock.stub("/me/history", with: .success(historyPageJSON(nextCursor: nil)))

        let records = try await APIWatchProgressRemoting(client: mock).fetchServerProgress()

        XCTAssertEqual(mock.receivedEndpoints.count, 1)
        XCTAssertEqual(records.count, 1)
    }

    /// Tek geçerli kayıt + verilen `nextCursor` (nil → JSON `null`) taşıyan `/me/history` sayfa gövdesi.
    private func historyPageJSON(nextCursor: String?) -> Data {
        let cursorJSON = nextCursor.map { "\"\($0)\"" } ?? "null"
        return Data("""
        {
          "items": [{
            "episodeId": "e1", "seriesId": "s1", "positionSec": 10,
            "durationSec": 90, "completed": false, "watchedAt": "2020-01-01T00:00:00Z"
          }],
          "nextCursor": \(cursorJSON)
        }
        """.utf8)
    }
}
