import Foundation

/// Deney tanımı kataloğuna salt-okunur erişim (FeatureFlagReading kalıbı, docs/08 §7.1).
/// Tanımlar remote config'den yüklenir; client sabit deney varsaymaz.
public protocol ExperimentCatalogReading: Sendable {
    /// Anahtara göre deney tanımı; tanım yoksa `nil`.
    func experiment(for key: String) -> Experiment?
    /// Yüklü tüm deney tanımları.
    var all: [Experiment] { get }
}

/// Immutable deney kataloğu (docs/08 §7.1: oturum ortasında değişmez). Remote config
/// yükünden (`GET /config`, 05 §API) decode edilir; yoksa boş katalogla uygulama tam çalışır.
public struct ExperimentCatalog: ExperimentCatalogReading {
    private let byKey: [String: Experiment]

    public init(experiments: [Experiment]) {
        byKey = Dictionary(experiments.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func experiment(for key: String) -> Experiment? {
        byKey[key]
    }

    public var all: [Experiment] {
        Array(byKey.values)
    }

    /// Remote config yükünü (deney tanımları dizisi) decode eder — SS-024 fetch yolunun
    /// deney parçası. Bozuk/eksik yük hata fırlatır (çağıran boş katalogla devam eder).
    public static func decode(from data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> ExperimentCatalog {
        let experiments = try decoder.decode([Experiment].self, from: data)
        return ExperimentCatalog(experiments: experiments)
    }
}
