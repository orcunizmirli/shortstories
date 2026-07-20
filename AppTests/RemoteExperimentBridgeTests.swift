import AnalyticsKit
import AppFoundation
import Foundation
import XCTest
@testable import ShortSeriesApp

/// SS-024 — A/B UZLAŞMASI + atama→exposure zinciri (docs/08 §7 + 05 §4.10; 09 M2). `RemoteExperimentBridge`
/// NEUTRAL `RemoteConfig.experiments` ([key, variant] = server-OTORİTER atama) → `AnalyticsKit`
/// deney grafiği köprüsünü doğrular: server atama `serverAssignments` override ile KAZANIR (bucketing
/// atlanır) ve `ExperimentClient` atanan varyantı çözüp `ab_exposure`'ı BASE tracker'a atar. Bu hedef
/// CI'da KOŞMAZ (App target CI dışı); simctl doğrulamasında koşar.
final class RemoteExperimentBridgeTests: XCTestCase {
    // MARK: - 09 M2: gerçek deney (paywall_layout) atama→exposure zinciri uçtan uca

    func testAssignmentToExposureChainEndToEnd() {
        let analytics = ExperimentSpyAnalytics()
        let bridge = RemoteExperimentBridge(assignments: [
            RemoteExperimentAssignment(key: "paywall_layout", variant: "B")
        ])
        let client = bridge.makeExperimentClient(analytics: analytics, userID: "device-1")

        // Atama: server-otoriter varyant B döner (bucketing DEĞİL — override kazanır).
        XCTAssertEqual(client.variant(for: "paywall_layout")?.id, "B")

        // Exposure: BASE tracker'a TAM 1 kez `ab_exposure` (exp_key + variant + first_exposure).
        let exposures = analytics.events.filter { $0.name == "ab_exposure" }
        XCTAssertEqual(exposures.count, 1)
        XCTAssertEqual(exposures.first?.parameters["exp_key"], .string("paywall_layout"))
        XCTAssertEqual(exposures.first?.parameters["variant"], .string("B"))
        XCTAssertEqual(exposures.first?.parameters["first_exposure"], .bool(true))

        // `ab_variants` ortak boyutu maruz kalınan atamayı taşır (diğer event'lere düşer, §7.3).
        XCTAssertEqual(client.abVariantsParameter(), "paywall_layout:B")
    }

    // MARK: - Server atama otoriter: köprü sentez katalog + override üretir

    func testBridgeSynthesizesCatalogAndServerAssignments() {
        let bridge = RemoteExperimentBridge(assignments: [
            RemoteExperimentAssignment(key: "paywall_layout", variant: "B"),
            RemoteExperimentAssignment(key: "checkin_curve", variant: "v1")
        ])

        XCTAssertEqual(bridge.serverAssignments, ["paywall_layout": "B", "checkin_curve": "v1"])
        // Her atama → tek-varyantlı, `.running`, %100 trafikli minimal tanım.
        let paywall = bridge.catalogExperiments.first { $0.key == "paywall_layout" }
        XCTAssertEqual(paywall?.status, .running)
        XCTAssertEqual(paywall?.trafficBasisPoints, 10000)
        XCTAssertEqual(paywall?.variants.map(\.id), ["B"])
    }

    // MARK: - Boş atama (offline ilk açılış / config yok) → pasif kontrol, exposure yok

    func testEmptyAssignmentsYieldControlAndNoExposure() {
        let analytics = ExperimentSpyAnalytics()
        let bridge = RemoteExperimentBridge(assignments: [])
        let client = bridge.makeExperimentClient(analytics: analytics, userID: "device-1")

        XCTAssertNil(client.variant(for: "paywall_layout"), "boş katalog → atama pasif (kontrol)")
        XCTAssertTrue(analytics.events.isEmpty, "atama yoksa exposure atılmaz")
        XCTAssertEqual(client.abVariantsParameter(), "", "maruz kalınan atama yok → boş boyut")
    }

    // MARK: - Exposure oturum başına idempotent (§7.3): tekrar okuma yeni event atmaz

    func testExposureIsIdempotentAcrossRepeatedReads() {
        let analytics = ExperimentSpyAnalytics()
        let bridge = RemoteExperimentBridge(assignments: [
            RemoteExperimentAssignment(key: "paywall_layout", variant: "A")
        ])
        let client = bridge.makeExperimentClient(analytics: analytics, userID: "device-1")

        _ = client.variant(for: "paywall_layout")
        _ = client.variant(for: "paywall_layout")
        _ = client.variant(for: "paywall_layout")

        XCTAssertEqual(analytics.events.filter { $0.name == "ab_exposure" }.count, 1)
    }

    // MARK: - Katalogda olmayan anahtar → nil (kontrol), exposure yok

    func testUnknownExperimentKeyReturnsNilWithoutExposure() {
        let analytics = ExperimentSpyAnalytics()
        let bridge = RemoteExperimentBridge(assignments: [
            RemoteExperimentAssignment(key: "paywall_layout", variant: "B")
        ])
        let client = bridge.makeExperimentClient(analytics: analytics, userID: "device-1")

        XCTAssertNil(client.variant(for: "does_not_exist"))
        XCTAssertTrue(analytics.events.isEmpty)
    }

    // MARK: - `previouslyExposed` tohumu → first_exposure=false (08 §7.3)

    func testPreviouslyExposedSeedsFirstExposureFalse() {
        let analytics = ExperimentSpyAnalytics()
        let bridge = RemoteExperimentBridge(assignments: [
            RemoteExperimentAssignment(key: "paywall_layout", variant: "B")
        ])
        let client = bridge.makeExperimentClient(
            analytics: analytics,
            userID: "device-1",
            previouslyExposed: ["paywall_layout"]
        )

        _ = client.variant(for: "paywall_layout")
        let exposure = analytics.events.first { $0.name == "ab_exposure" }
        XCTAssertEqual(exposure?.parameters["first_exposure"], .bool(false))
    }
}

// MARK: - Fake

private final class ExperimentSpyAnalytics: AnalyticsTracking, @unchecked Sendable {
    struct Event: Equatable {
        let name: String
        let parameters: [String: AnalyticsValue]
    }

    private let lock = NSLock()
    private var recorded: [Event] = []

    var events: [Event] {
        lock.withLock { recorded }
    }

    func track(_ name: String, parameters: [String: AnalyticsValue]) {
        lock.withLock { recorded.append(Event(name: name, parameters: parameters)) }
    }
}
