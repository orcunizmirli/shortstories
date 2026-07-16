import XCTest
@testable import ShortSeriesApp

/// SS-143 — push atıf event sözleşmesi (08 §3.6). `push_open` istemci-tarafı emit edilir → registry'de
/// KAYITLI olmalı (aksi halde `AppAnalyticsTracker` DEBUG'da her push'ta assertionFailure). `push_received`
/// istemciden GÖNDERİLMEZ (teslimat backend'de APNs yanıtından loglanır — 08 §3.6 Not) → registry'de yok.
final class PushAnalyticsContractTests: XCTestCase {
    func testPushOpenIsRegistered() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("push_open"), .valid)
    }

    func testPushOpenIsWellFormed() {
        XCTAssertTrue(AnalyticsEventRegistry.isWellFormed("push_open"))
    }

    /// `push_received` istemci event'i DEĞİL (08 §3.6 Not): registry'ye eklenmez, emit edilmez.
    func testPushReceivedIsNotAClientEvent() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("push_received"), .unregistered)
    }
}
