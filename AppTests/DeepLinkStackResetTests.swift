import AppFoundation
import DiscoverKit
import XCTest
@testable import ShortSeriesApp

/// SS-142 / audit LOW (deeplink-fidelity, 02 §8.2/§8.4): sekme-KÖKÜ hedefleyen deep-link/push rotaları
/// (`.home`, `.profile`) yalnız sekme değiştirmemeli — hedef sekmenin NavigationStack'ini de köke
/// sıfırlamalı. Aksi halde kullanıcı önceden push edilmiş bayat detay ekranında kalır (beklenen kök yerine).
@MainActor
final class DeepLinkStackResetTests: XCTestCase {
    private func makeTabCoordinator() throws -> TabCoordinator {
        let composition = try AppComposition(dependencies: PreviewDependencies())
        return TabCoordinator(composition: composition)
    }

    func testHomeDeepLinkResetsHomeStackToRoot() throws {
        let tab = try makeTabCoordinator()
        tab.home.path.append(SeriesID("srs_stale")) // Ana Sayfa'da bayat bir DiziDetay push'u var
        XCTAssertFalse(tab.home.path.isEmpty)

        tab.handle(.home) // sekme-kökü deep-link/push

        XCTAssertTrue(tab.home.path.isEmpty) // stack köke sıfırlandı (bayat detay temizlendi)
    }

    func testProfileDeepLinkResetsProfileStackToRoot() throws {
        let tab = try makeTabCoordinator()
        tab.profile.path.append(.ayarlar) // Profil'de bayat bir Ayarlar push'u var
        XCTAssertFalse(tab.profile.path.isEmpty)

        tab.handle(.profile) // sekme-kökü deep-link/push

        XCTAssertTrue(tab.profile.path.isEmpty) // stack köke sıfırlandı
    }
}
