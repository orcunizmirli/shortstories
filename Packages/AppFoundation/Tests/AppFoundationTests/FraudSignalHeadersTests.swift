import Foundation
import Testing
@testable import AppFoundation

/// SS-100: `FraudSignal` → header sözlüğü üretimi (integrity + velocity kombinasyonları) ve
/// PII/secret sızıntısı OLMADIĞI doğrulaması.
struct FraudSignalHeadersTests {
    private let suspected = DeviceIntegritySignal(reasons: [.suspiciousFile, .sandboxEscape])

    @Test func temizIntegrityCleanBayragiUretir() {
        let fields = FraudSignalHeaders.fields(for: FraudSignal(integrity: .clean))

        #expect(fields[FraudSignalHeaders.deviceIntegrity] == "clean")
    }

    @Test func supheliIntegritySuspectedBayragiUretir() {
        let fields = FraudSignalHeaders.fields(for: FraudSignal(integrity: suspected))

        #expect(fields[FraudSignalHeaders.deviceIntegrity] == "suspected")
    }

    @Test func velocityYoksaVelocityHeaderEklenmez() {
        let fields = FraudSignalHeaders.fields(for: FraudSignal(integrity: .clean, earnVelocity: nil))

        #expect(fields[FraudSignalHeaders.earnVelocityFlag] == nil)
        #expect(fields.count == 1)
    }

    @Test func normalVelocityNormalBayragiUretir() {
        let signal = FraudSignal(integrity: .clean, earnVelocity: EarnVelocitySignal(level: .normal))
        let fields = FraudSignalHeaders.fields(for: signal)

        #expect(fields[FraudSignalHeaders.earnVelocityFlag] == "normal")
    }

    @Test func elevatedVelocityElevatedBayragiUretir() {
        let signal = FraudSignal(integrity: suspected, earnVelocity: EarnVelocitySignal(level: .elevated))
        let fields = FraudSignalHeaders.fields(for: signal)

        #expect(fields[FraudSignalHeaders.deviceIntegrity] == "suspected")
        #expect(fields[FraudSignalHeaders.earnVelocityFlag] == "elevated")
        #expect(fields.count == 2)
    }

    @Test func headerAdlariSozlesmeyeSabit() {
        // Wire sözleşmesi (05 §1.1) — istemci/backend paylaşımı; regresyon kilidi.
        #expect(FraudSignalHeaders.deviceIntegrity == "X-Device-Integrity")
        #expect(FraudSignalHeaders.earnVelocityFlag == "X-Earn-Velocity-Flag")
    }

    @Test func sadeceKabaBayrakGiderPiiSecretSizmaz() {
        // Şüpheli nedenler ham yol/sayaç içerir; header'a YALNIZ kaba bayrak yansımalı — ham yol,
        // enum neden adı, sayaç ya da zaman damgası header değerlerine SIZMAMALI.
        let signal = FraudSignal(
            integrity: DeviceIntegritySignal(reasons: DeviceIntegritySignal.Reason.allCases),
            earnVelocity: EarnVelocitySignal(level: .elevated)
        )
        let fields = FraudSignalHeaders.fields(for: signal)

        #expect(Set(fields.keys) == [FraudSignalHeaders.deviceIntegrity, FraudSignalHeaders.earnVelocityFlag])
        #expect(Set(fields.values) == ["suspected", "elevated"])
        for value in fields.values {
            #expect(!value.contains("/")) // ham dosya yolu yok
            #expect(!value.contains("suspiciousFile")) // enum neden adı yok
        }
    }
}
