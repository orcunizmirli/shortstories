import Foundation
import Testing
@testable import AppFoundation

/// SS-100: `BasicDeviceIntegrityProbe` heuristikleri, tüm OS-dokunuşları ENJEKTE edilmiş sahte
/// seam'lerle deterministik doğrulanır — testler gerçek dosya sistemine/jailbreak API'sine dokunmaz.
struct DeviceIntegrityProbeTests {
    private let paths = ["/Applications/Cydia.app"]
    private let schemes = ["cydia"]

    private func probe(
        pathExists: @escaping @Sendable (String) -> Bool = { _ in false },
        canOpenScheme: @escaping @Sendable (String) -> Bool = { _ in false },
        sandboxEscape: @escaping @Sendable () -> Bool = { false }
    ) -> BasicDeviceIntegrityProbe {
        BasicDeviceIntegrityProbe(
            suspiciousPaths: paths,
            suspiciousSchemes: schemes,
            pathExists: pathExists,
            canOpenScheme: canOpenScheme,
            sandboxEscapeProbe: sandboxEscape
        )
    }

    @Test func temizCihazSuphelisizDoner() {
        let signal = probe().evaluate()

        #expect(signal.suspected == false)
        #expect(signal.reasons.isEmpty)
        #expect(signal == .clean)
    }

    @Test func supheliDosyaVarsaSuspiciousFileNedeni() {
        let signal = probe(pathExists: { $0 == "/Applications/Cydia.app" }).evaluate()

        #expect(signal.suspected)
        #expect(signal.reasons == [.suspiciousFile])
    }

    @Test func supheliUrlSemasiAcilabilirseUrlSchemeNedeni() {
        let signal = probe(canOpenScheme: { $0 == "cydia" }).evaluate()

        #expect(signal.suspected)
        #expect(signal.reasons == [.suspiciousURLScheme])
    }

    @Test func sandboxDisiYazmaBasarirsaSandboxEscapeNedeni() {
        let signal = probe(sandboxEscape: { true }).evaluate()

        #expect(signal.suspected)
        #expect(signal.reasons == [.sandboxEscape])
    }

    @Test func birdenFazlaHeuristikSabitSiradaBirikir() {
        let signal = probe(
            pathExists: { _ in true },
            canOpenScheme: { _ in true },
            sandboxEscape: { true }
        ).evaluate()

        // Sabit sıra: dosya → URL şeması → sandbox kaçışı.
        #expect(signal.reasons == [.suspiciousFile, .suspiciousURLScheme, .sandboxEscape])
        #expect(signal.suspected)
    }

    @Test func varsayilanProbGercekJailbreakArtefaktiListesiTasir() {
        // Varsayılan liste boş olmamalı ve gizleme kolaylığına rağmen bilinen artefaktları içermeli.
        #expect(BasicDeviceIntegrityProbe.defaultSuspiciousPaths.contains("/Applications/Cydia.app"))
        #expect(BasicDeviceIntegrityProbe.defaultSuspiciousSchemes.contains("cydia"))
    }

    @Test func varsayilanCanOpenSchemeUikitGerektirmedenFalseDoner() {
        // Varsayılan seam UIKit'e dokunmaz (AppFoundation UIKit-free) → temiz kabul.
        let live = BasicDeviceIntegrityProbe(
            pathExists: { _ in false },
            sandboxEscapeProbe: { false }
        )

        #expect(live.evaluate() == .clean)
    }
}
