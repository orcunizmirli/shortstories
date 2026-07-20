/// `FraudSignal` → HTTP header sözlüğü üreticisi + wire header adı sözleşmesi (SS-100; 05 §1.1).
/// TEK doğruluk kaynağı: header adları burada sabit tanımlıdır (analytics-registry deseni gibi kritik —
/// istemci/backend aynı adları paylaşır). Yalnız KABA advisory bayraklar yazılır; PII/secret/ham sayaç
/// KOYULMAZ (cihaz kimliği zaten `X-Device-Id`'de — 05 §1.1). Bütünlük bayrağı her authed istekte gider
/// (temiz durumda bile "clean" — backend "prob çalıştı, temiz"i "eski istemci/prob yok"tan ayırt eder);
/// kazanç-hızı yalnız sinyal varken.
public enum FraudSignalHeaders {
    /// Cihaz bütünlüğü danışma bayrağı. Değer: `clean` | `suspected`.
    public static let deviceIntegrity = "X-Device-Integrity"
    /// Kazanç-hızı danışma bayrağı. Değer: `EarnVelocitySignal.Level.rawValue` (`normal` | `elevated`).
    public static let earnVelocityFlag = "X-Earn-Velocity-Flag"

    /// Wire değeri: bütünlük şüpheliyse `suspected`, değilse `clean`.
    public static func integrityValue(for signal: DeviceIntegritySignal) -> String {
        signal.suspected ? "suspected" : "clean"
    }

    /// `FraudSignal`'den header sözlüğü. Bütünlük her zaman; kazanç-hızı yalnız sinyal varken.
    public static func fields(for signal: FraudSignal) -> [String: String] {
        var fields = [deviceIntegrity: integrityValue(for: signal.integrity)]
        if let earnVelocity = signal.earnVelocity {
            fields[earnVelocityFlag] = earnVelocity.level.rawValue
        }
        return fields
    }
}
