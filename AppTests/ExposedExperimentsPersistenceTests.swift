import AnalyticsKit
import AppFoundation
import AppFoundationTestSupport
import XCTest
@testable import ShortSeriesApp

/// SS-024 / 08 §7.3 (audit LOW `previouslyExposed` persist): exposure geçmişi OTURUMLAR ARASI kalıcı
/// olmalı → DÖNEN kullanıcı için `ab_exposure.first_exposure` yanlışça `true` DÜŞMEZ (aksi halde her
/// soğuk açılış "ilk maruz kalma" sayılır → win-back/funnel KPI kalıcı ŞİŞER). App katmanı
/// `UserDefaultsExposedExperimentsStore` sağlar: launch'ta `load()` → `previouslyExposed` tohumu,
/// scenePhase-background'da `merge(client.exposedExperimentKeys)` ile birikimli persist.
/// Bu hedef CI'da KOŞMAZ (App target CI dışı); simctl doğrulamasında koşar.
final class ExposedExperimentsPersistenceTests: XCTestCase {
    private let suiteName = "test.analytics.exposed_experiments"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeStore() -> UserDefaultsExposedExperimentsStore {
        UserDefaultsExposedExperimentsStore(defaults: UserDefaults(suiteName: suiteName)!)
    }

    // MARK: - Store birimi: yokluk → boş küme; merge birikimli + boş-merge no-op.

    func testAbsentLoadsEmptyAndMergeAccumulates() {
        let store = makeStore()
        XCTAssertEqual(store.load(), []) // hiç yazılmadı → boş (ilk açılış)
        store.merge(["a"])
        XCTAssertEqual(store.load(), ["a"])
        store.merge(["b", "c"])
        XCTAssertEqual(store.load(), ["a", "b", "c"]) // birikimli birleşim
        store.merge([]) // boş merge yazma yapmaz, mevcut küme korunur
        XCTAssertEqual(store.load(), ["a", "b", "c"])
    }

    // MARK: - Gerçek bug: dönen kullanıcı OTURUMLAR ARASI first_exposure=false almalı.

    func testReturningUserIsNotFirstExposureAcrossSessions() {
        let experiment = Experiment(
            key: "paywall_layout", salt: "s", status: .running,
            trafficBasisPoints: 10000, variants: [ExperimentVariant(id: "B", weight: 1)]
        )
        let catalog = ExperimentCatalog(experiments: [experiment])

        // Oturum 1: ilk maruz kalış → first_exposure=true; ardından scenePhase-bg persist.
        let store1 = makeStore()
        let analytics1 = MockAnalytics()
        let client1 = ExperimentClient(
            catalog: catalog, analytics: analytics1, userID: "device-1", previouslyExposed: store1.load()
        )
        _ = client1.variant(for: "paywall_layout")
        XCTAssertEqual(analytics1.events.first?.parameters["first_exposure"], .bool(true))
        store1.merge(client1.exposedExperimentKeys) // scenePhase == .background

        // Oturum 2: aynı cihaz, YENİ client tohumu store'dan → first_exposure=false (dönen kullanıcı).
        let store2 = makeStore()
        XCTAssertEqual(store2.load(), ["paywall_layout"]) // persist edildi
        let analytics2 = MockAnalytics()
        let client2 = ExperimentClient(
            catalog: catalog, analytics: analytics2, userID: "device-1", previouslyExposed: store2.load()
        )
        _ = client2.variant(for: "paywall_layout")
        XCTAssertEqual(analytics2.events.first?.parameters["first_exposure"], .bool(false))
    }
}
