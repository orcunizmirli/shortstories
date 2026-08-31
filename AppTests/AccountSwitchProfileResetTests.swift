import AppFoundation
import AppFoundationTestSupport
import XCTest
@testable import ShortSeriesApp

/// Cross-account nav-leak (SS-132 sınıfı): `ProfileCoordinator` uzun-ömürlü (TabCoordinator ömrü); hesap
/// DEĞİŞİMİNDE Profil stack'i (pushed Ayarlar/BildirimMerkezi — hesap-özel bildirimler) köke sıfırlanmalı →
/// A'nın açık ekranı B'ye taşınmasın. Gözlemci Home/Discover/Library/Rewards ile simetrik. `ProfilModel`
/// stream-türetimli olduğundan yalnız `path` sıfırlanır (model-reset gerekmez).
@MainActor
final class AccountSwitchProfileResetTests: XCTestCase {
    func testDifferentAccountSwitchResetsProfilePathButSameUserIDDoesNot() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        _ = tab.profile.profilModel // lazy init (coordinator + gözlemci canlı)
        tab.profile.showSettings() // A Ayarlar push eder
        XCTAssertFalse(tab.profile.path.isEmpty)

        // Aynı userID (link/re-auth AYNI hesap) reset ETMEMELİ.
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertFalse(tab.profile.path.isEmpty) // aynı hesap → stack korunur

        // FARKLI hesaba geçiş → Profil stack köke sıfırlanır.
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if tab.profile.path.isEmpty {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // A'nın pushed Ayarlar/BildirimMerkezi'si B'ye taşınmadı
    }

    func testProfileSwitchThroughLoggedOutIntermediateStateStillResets() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        _ = tab.profile.profilModel
        tab.profile.showSettings()
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertFalse(tab.profile.path.isEmpty)

        // u1 → loggedOut (nil ara-durum) → u2: nil'den geçse de switch algılanmalı.
        session.send(.loggedOut(previousUserID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if tab.profile.path.isEmpty {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // nil-ara-durumdan geçen switch yakalandı
    }
}
