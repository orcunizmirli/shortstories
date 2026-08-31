import CryptoKit
import Foundation

/// Deney atama portu. Saf + deterministik: aynı `userID` + deney her zaman aynı varyant
/// (yapışkanlık, docs/08 §7.2). Date/random YOK — girdi yalnız hash'lenir.
public protocol ExperimentAssigning: Sendable {
    /// Bu kullanıcının deneydeki varyantı; deney aktif değilse, trafiğe dahil değilse veya
    /// varyant yoksa `nil` (kontrol/varyantsız).
    func assignment(for experiment: Experiment, userID: String) -> ExperimentVariant?
}

/// Deterministik bucketing ile atama (docs/08 §7.2). Sunucu çağrısı gerektirmez, offline
/// çalışır, cihazlar arasında tutarlıdır (yalnız stabil `userID`'ye bağlı).
///
/// Server-otoriter override: backend açık bir atama verdiyse (`serverAssignments`), geçerli
/// olduğu sürece hash yerine o kullanılır — client atama sunucuya tabidir.
public struct DeterministicExperimentAssigner: ExperimentAssigning {
    /// Bucket uzayı 0..<10_000 (docs/08 §7.2). Trafik dahil-etme VE varyant seçimi bu modülüsle,
    /// AYRI hash boyutlarında hesaplanır.
    static let bucketModulus = 10000
    /// Varyant seçimi salt namespace'i — trafik dahil-etme bucket'ından İSTATİSTİKSEL BAĞIMSIZ ikinci
    /// hash boyutu üretir (ramp yalnız dahil-etmeyi etkiler, varyantı değil; docs/08 satır 400).
    private static let variantSaltNamespace = ":variant"

    private let serverAssignments: [String: String]

    /// - Parameter serverAssignments: `experimentKey -> variantID`. Sunucu bir kullanıcıyı
    ///   belirli bir varyanta sabitlemek isterse (ör. çakışma grubu çözümü, elle atama)
    ///   burada gelir ve deterministik hash'i override eder.
    public init(serverAssignments: [String: String] = [:]) {
        self.serverAssignments = serverAssignments
    }

    public func assignment(for experiment: Experiment, userID: String) -> ExperimentVariant? {
        guard experiment.isActive else { return nil }

        // Server-otoriter override: geçerli bir varyanta işaret ediyorsa hash'i atla.
        if let forced = serverOverride(for: experiment) {
            return forced
        }

        let totalWeight = experiment.totalWeight
        guard totalWeight > 0 else { return nil }

        // (1) Trafik dahil-etme: ramp YALNIZ bunu genişletir → dahil olan kullanıcı dahil KALIR.
        let inclusionBucket = Self.bucket(userID: userID, experimentKey: experiment.key, salt: experiment.salt)
        // trafficBasisPoints dışı → deneye dahil değil (0 ise guard her zaman düşer).
        guard inclusionBucket < experiment.trafficBasisPoints else { return nil }

        // (2) Varyant seçimi TRAFİK-BAĞIMSIZ ayrı hash boyutuna dayanır (docs/08 satır 400 yapışkanlık
        // invariantı): ramp (trafficBasisPoints artışı, salt sabit) MEVCUT kullanıcının varyantını
        // DEĞİŞTİRMEZ. Sabit modülüsle ölçek → dağılım tBP'den bağımsız; ayrı salt namespace → dahil-etme
        // bucket'ıyla korelasyonsuz. (Eski kod bucket'ı trafficBasisPoints'e böldüğünden ramp variant flip
        // ettiriyordu → sample-ratio-mismatch; docs/08 §7.2 satır 386 referans pseudo-kodu da bu hatayı taşıyordu.)
        let variantBucket = Self.bucket(
            userID: userID,
            experimentKey: experiment.key,
            salt: experiment.salt + Self.variantSaltNamespace
        )
        // `scaled` = variantBucket'ı [0, totalWeight) kümülatif-ağırlık uzayına eşler. `variantBucket <
        // bucketModulus` → scaled her zaman < totalWeight. Overflow-güvenli: aşırı-büyük totalWeight
        // (adversarial remote config) `variantBucket * totalWeight`'i Int64'te TAŞIRIP TRAP ettirebilir →
        // taşmada Double ile hesapla (bucketing için hassasiyet yeterli, crash yerine geçerli dağılım);
        // normal (erişilebilir) durumda exact integer math korunur.
        let (product, overflow) = variantBucket.multipliedReportingOverflow(by: totalWeight)
        let scaled = overflow
            ? Int((Double(variantBucket) / Double(Self.bucketModulus)) * Double(totalWeight))
            : product / Self.bucketModulus
        var cumulative = 0
        for variant in experiment.variants {
            cumulative += variant.weight
            if scaled < cumulative {
                return variant
            }
        }
        return experiment.variants.last
    }

    /// Sunucunun bu deney için verdiği açık atama (varsa ve tanımda geçerliyse).
    private func serverOverride(for experiment: Experiment) -> ExperimentVariant? {
        guard let forcedID = serverAssignments[experiment.key] else { return nil }
        return experiment.variant(withID: forcedID)
    }

    /// 0..<10_000 deterministik bucket (docs/08 §7.2). Aynı `userID` + `experimentKey` +
    /// `salt` her zaman aynı değeri verir (yapışkanlık ve cihazlar-arası tutarlılık temeli).
    public static func bucket(userID: String, experimentKey: String, salt: String) -> Int {
        let input = Data("\(experimentKey):\(salt):\(userID)".utf8)
        let digest = SHA256.hash(data: input)
        let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Int(value % UInt64(bucketModulus))
    }
}
