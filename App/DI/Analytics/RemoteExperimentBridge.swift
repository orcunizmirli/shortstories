import AnalyticsKit
import AppFoundation

/// SS-024 — NEUTRAL remote config deney ATAMALARINI (`[key, variant]`) `AnalyticsKit` deney grafiğine
/// bağlayan App-katmanı köprüsü. `AppFoundation` nötrdür (`AnalyticsKit` import ETMEZ, `RemoteConfig`
/// atamaları `RemoteExperimentAssignment` olarak taşır); bu köprü yalnız kompozisyon kökünde (App)
/// yaşayabilir — feature↔analytics birleştirmesi R1 istisnasıyla App'e aittir.
///
/// UZLAŞMA (docs/08 §7 + 05 §4.10 OKUNDU): `GET /config.experiments` server-OTORİTER **atama** taşır
/// (`{ key, variant }` — 05 §4.10 wire örneği `{ "key": "paywall_layout", "variant": "B" }`). Client-side
/// deterministik bucketing (08 §7.2) atamanın OFFLINE/fallback algoritmasıdır; server açık bir atama
/// verdiğinde o KAZANIR. Bu, `DeterministicExperimentAssigner.serverAssignments` override yoluyla wire
/// edilir (SS-154 mevcut API — kırılmaz): bucketing atlanır, "client atama sunucuya tabidir" (assigner
/// dokümanı). Wire yalnız `{key, variant}` taşıdığından (full tanım değil) her atama için katalogda
/// MİNİMAL bir tanım (atanan varyant, `.running`, %100 trafik) sentezlenir ki `ExperimentClient`
/// varyantı çözüp `ab_exposure`'ı BASE tracker'a atabilsin (09 M2: atama→exposure zinciri uçtan uca).
///
/// Atama yoksa (boş dizi / offline ilk açılış) katalog ve override boş → `variant(for:)` `nil` döner
/// (kontrol davranışı, exposure yok) ve uygulama tam çalışır (03 §11 config-yok toleransı).
struct RemoteExperimentBridge {
    /// Sentezlenmiş deney tanımları (`ExperimentCatalog`'a beslenir). Her atama → tek-varyantlı,
    /// `.running`, %100 trafikli minimal tanım; gerçek varyant `serverAssignments` override'ından gelir.
    let catalogExperiments: [Experiment]

    /// `experimentKey -> variantID` server atamaları — assigner'da deterministik hash'i override eder.
    let serverAssignments: [String: String]

    init(assignments: [RemoteExperimentAssignment]) {
        var experiments: [Experiment] = []
        var server: [String: String] = [:]
        for assignment in assignments {
            // Aynı anahtar tekrarlarsa son atama kazanır (katalog uniquingKeysWith:last ile uyumlu).
            server[assignment.key] = assignment.variant
            experiments.append(
                Experiment(
                    key: assignment.key,
                    // salt bucketing içindir; server override kısa devre yaptığından değeri okunmaz.
                    salt: "",
                    status: .running,
                    trafficBasisPoints: 10000,
                    variants: [ExperimentVariant(id: assignment.variant)]
                )
            )
        }
        catalogExperiments = experiments
        serverAssignments = server
    }

    /// Köprüden canlı `ExperimentClient` kurar: sentez katalog + server-atama override + stabil `userID`.
    /// `previouslyExposed` (varsa) `first_exposure`'ı doğru hesaplamak için tohumlanır (08 §7.3).
    func makeExperimentClient(
        analytics: any AnalyticsTracking,
        userID: String,
        previouslyExposed: Set<String> = []
    ) -> ExperimentClient {
        ExperimentClient(
            catalog: ExperimentCatalog(experiments: catalogExperiments),
            assigner: DeterministicExperimentAssigner(serverAssignments: serverAssignments),
            analytics: analytics,
            userID: userID,
            previouslyExposed: previouslyExposed
        )
    }
}
