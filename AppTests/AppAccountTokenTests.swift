import AppFoundation
import XCTest
@testable import ShortSeriesApp

/// Audit LOW: StoreKit `appAccountToken` KURULUM-KARARLI olmalı (işlem→hesap attribution). Fresh
/// `UUID()` her launch'ta değişip aynı kurulumun satın-almalarını korele edilemez yapıyordu →
/// preferences'ta persist edilir (yoksa üret+yaz).
final class AppAccountTokenTests: XCTestCase {
    func testAppAccountTokenPersistEdilirVeKararliKalir() {
        let prefs = OnboardingInMemoryPreferences()
        let first = AppComposition.resolveAppAccountToken(preferences: prefs)
        let second = AppComposition.resolveAppAccountToken(preferences: prefs)
        XCTAssertEqual(first, second) // persist edildi → aynı token (fresh UUID değil)
    }

    func testFarkliKurulumFarkliToken() {
        let a = AppComposition.resolveAppAccountToken(preferences: OnboardingInMemoryPreferences())
        let b = AppComposition.resolveAppAccountToken(preferences: OnboardingInMemoryPreferences())
        XCTAssertNotEqual(a, b) // ayrı kurulumlar (boş preferences) ayrı token üretir
    }
}
