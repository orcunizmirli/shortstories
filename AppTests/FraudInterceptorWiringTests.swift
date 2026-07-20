import AppFoundation
import Foundation
import XCTest
@testable import ShortSeriesApp

/// SS-100 (F2): App kompozisyonu `FraudSignalInterceptor`'ı authed apiClient zincirine kaydeder ve
/// cihaz-bütünlüğü prob'u (canlı) + kazanç-hızı raporlayıcısını (WalletKit monitörü) enjekte eder.
/// Bu testler gerçek dependency grafiği / ağ KURMADAN `LiveDependencies.makeInterceptors` fabrikasını
/// doğrudan doğrular: fraud interceptor zincirde mi, header'lar yalnız authed isteklere mi gidiyor,
/// enjekte kazanç-hızı sinyali header'a mı düşüyor. Değer davranışı; backend kararı test edilmez.
@MainActor
final class FraudInterceptorWiringTests: XCTestCase {
    // MARK: - Test double'ları (yerel; gerçek Keychain/WalletKit'e dokunmaz)

    private struct StubSecureStore: SecureStoring {
        func data(forKey _: SecureStoreKey) throws -> Data? {
            nil
        }

        func setData(_: Data, forKey _: SecureStoreKey) throws {}
        func removeData(forKey _: SecureStoreKey) throws {}
    }

    private struct StubVelocityReporter: EarnVelocityReporting {
        let signal: EarnVelocitySignal?
        func currentEarnVelocity() async -> EarnVelocitySignal? {
            signal
        }
    }

    private let url = URL(string: "https://api.test.local/v1/wallet")!

    /// Fabrika zincirini kurar ve verilen bağlamda tüm interceptor'ları sırayla uygular.
    private func adapt(
        requiresAuth: Bool,
        reporter: (any EarnVelocityReporting)?
    ) async throws -> URLRequest {
        let interceptors = LiveDependencies.makeInterceptors(secureStore: StubSecureStore(), velocityReporter: reporter)
        var request = URLRequest(url: url)
        let context = RequestContext(requiresAuth: requiresAuth)
        for interceptor in interceptors {
            request = try await interceptor.adapt(request, context: context)
        }
        return request
    }

    // MARK: - Kayıt

    func testFraudInterceptorRegisteredInAuthedChain() {
        let interceptors = LiveDependencies.makeInterceptors(secureStore: StubSecureStore(), velocityReporter: nil)
        XCTAssertTrue(
            interceptors.contains { $0 is FraudSignalInterceptor },
            "FraudSignalInterceptor authed apiClient zincirinde kayıtlı olmalı (AuthInterceptor yanına)."
        )
    }

    // MARK: - Header kapsamı (yalnız authed)

    func testAuthedRequestCarriesDeviceIntegrityHeader() async throws {
        let request = try await adapt(requiresAuth: true, reporter: nil)
        // Cihaz bütünlüğü HER authed istekte gider; değer clean|suspected (simülatör sandbox'ına
        // göre değişebilir — burada yalnız VARLIĞI + sözleşme değeri doğrulanır).
        let value = request.value(forHTTPHeaderField: FraudSignalHeaders.deviceIntegrity)
        XCTAssertNotNil(value, "Authed istek X-Device-Integrity taşımalı.")
        XCTAssertTrue(["clean", "suspected"].contains(value), "Bütünlük değeri sözleşme dışı: \(value ?? "nil")")
    }

    func testGuestRequestOmitsAllFraudHeaders() async throws {
        // requiresAuth=false: fraud header GİTMEZ (elevated sinyal enjekte edilmiş olsa bile).
        let request = try await adapt(requiresAuth: false, reporter: StubVelocityReporter(signal: .init(level: .elevated)))
        XCTAssertNil(request.value(forHTTPHeaderField: FraudSignalHeaders.deviceIntegrity))
        XCTAssertNil(request.value(forHTTPHeaderField: FraudSignalHeaders.earnVelocityFlag))
    }

    // MARK: - Kazanç-hızı enjeksiyonu (WalletKit monitörü → header)

    func testInjectedElevatedVelocityFlowsToHeader() async throws {
        let request = try await adapt(requiresAuth: true, reporter: StubVelocityReporter(signal: .init(level: .elevated)))
        XCTAssertEqual(request.value(forHTTPHeaderField: FraudSignalHeaders.earnVelocityFlag), "elevated")
    }

    func testNilReporterOmitsVelocityHeaderButKeepsIntegrity() async throws {
        // Sinyal yok (nil reporter / henüz kazanç aktivitesi yok) → velocity header eklenmez;
        // bütünlük bayrağı yine gider.
        let request = try await adapt(requiresAuth: true, reporter: StubVelocityReporter(signal: nil))
        XCTAssertNil(request.value(forHTTPHeaderField: FraudSignalHeaders.earnVelocityFlag))
        XCTAssertNotNil(request.value(forHTTPHeaderField: FraudSignalHeaders.deviceIntegrity))
    }
}
