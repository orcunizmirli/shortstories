import Foundation
import Testing
@testable import AppFoundation

/// SS-100: `FraudSignalInterceptor` — fraud header'larını yalnız authed isteklere ekler, prob'u
/// sahteler (gerçek OS-probe çağrılmaz), kazanç-hızı port'unu enjekte eder.
struct FraudSignalInterceptorTests {
    private let request = URLRequest(url: URL(string: "https://api.test.local/v1/wallet/unlock")!)

    // MARK: - Test double'ları (yerel; gerçek OS/WalletKit'e dokunmaz)

    /// Sahte prob: canned sinyal döner ve `evaluate` çağrı sayısını sayar (tek-sefer değerlemeyi doğrular).
    private final class StubProbe: DeviceIntegrityProbing, @unchecked Sendable {
        let signal: DeviceIntegritySignal
        private let lock = NSLock()
        private var count = 0

        init(_ signal: DeviceIntegritySignal) {
            self.signal = signal
        }

        var evaluateCount: Int {
            lock.withLock { count }
        }

        func evaluate() -> DeviceIntegritySignal {
            lock.withLock { count += 1 }
            return signal
        }
    }

    /// Sahte kazanç-hızı raporlayıcı (WalletKit yerine): canned opsiyonel sinyal döner.
    private struct StubVelocityReporter: EarnVelocityReporting {
        let signal: EarnVelocitySignal?

        func currentEarnVelocity() async -> EarnVelocitySignal? {
            signal
        }
    }

    // MARK: - Kapsam: authed / non-authed

    @Test func authedIsteyeIntegrityHeaderEkler() async throws {
        let interceptor = FraudSignalInterceptor(probe: StubProbe(.clean))

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.deviceIntegrity) == "clean")
    }

    @Test func nonAuthedIsteyeFraudHeaderEklemez() async throws {
        let interceptor = FraudSignalInterceptor(
            probe: StubProbe(DeviceIntegritySignal(reasons: [.suspiciousFile])),
            velocityReporter: StubVelocityReporter(signal: EarnVelocitySignal(level: .elevated))
        )

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: false))

        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.deviceIntegrity) == nil)
        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.earnVelocityFlag) == nil)
    }

    @Test func supheliCihazSuspectedBayragiGonderir() async throws {
        let interceptor = FraudSignalInterceptor(
            probe: StubProbe(DeviceIntegritySignal(reasons: [.sandboxEscape]))
        )

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.deviceIntegrity) == "suspected")
    }

    // MARK: - Kazanç-hızı enjeksiyonu

    @Test func velocityReporterYoksaVelocityHeaderEklenmez() async throws {
        let interceptor = FraudSignalInterceptor(probe: StubProbe(.clean))

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.earnVelocityFlag) == nil)
    }

    @Test func velocitySinyaliNilDonerseVelocityHeaderEklenmez() async throws {
        let interceptor = FraudSignalInterceptor(
            probe: StubProbe(.clean),
            velocityReporter: StubVelocityReporter(signal: nil)
        )

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.earnVelocityFlag) == nil)
    }

    @Test func elevatedVelocityHeaderiEklenir() async throws {
        let interceptor = FraudSignalInterceptor(
            probe: StubProbe(.clean),
            velocityReporter: StubVelocityReporter(signal: EarnVelocitySignal(level: .elevated))
        )

        let adapted = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.earnVelocityFlag) == "elevated")
        #expect(adapted.value(forHTTPHeaderField: FraudSignalHeaders.deviceIntegrity) == "clean")
    }

    // MARK: - Prob tek kez değerlenir + istek bütünlüğü korunur

    @Test func probTekKezDegerlenirBirdenFazlaAdaptDosyaSistemiTekrarProbeEtmez() async throws {
        let stub = StubProbe(.clean)
        let interceptor = FraudSignalInterceptor(probe: stub)

        _ = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))
        _ = try await interceptor.adapt(request, context: RequestContext(requiresAuth: true))

        // Prob init'te BİR KEZ değerlenir; per-istek yeniden probe YOK.
        #expect(stub.evaluateCount == 1)
    }

    @Test func mevcutHeaderVeUrlKorunur() async throws {
        let interceptor = FraudSignalInterceptor(probe: StubProbe(.clean))
        var original = request
        original.setValue("tr-TR", forHTTPHeaderField: "Accept-Language")
        original.setValue("Bearer at_1", forHTTPHeaderField: "Authorization")

        let adapted = try await interceptor.adapt(original, context: RequestContext(requiresAuth: true))

        #expect(adapted.url == original.url)
        #expect(adapted.value(forHTTPHeaderField: "Accept-Language") == "tr-TR")
        #expect(adapted.value(forHTTPHeaderField: "Authorization") == "Bearer at_1")
    }
}
