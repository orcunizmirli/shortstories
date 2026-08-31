import AppFoundation
import AppFoundationTestSupport
import DiscoverKit
import XCTest
@testable import ShortSeriesApp

/// Cross-account (05 §3.3, SS-132 sınıfı): uzun-ömürlü `KesfetModel` + `DiscoverSessionStore` (TabCoordinator
/// ömrü, switch'te yeniden yaratılmaz) hesap DEĞİŞİMİNDE sıfırlanmalı → A'nın per-user `/discover` layout'u
/// (`private` cache) + seçili tür filtresi B'ye sızmasın. `DiscoverCoordinator` her-zaman-canlı session
/// gözlemcisiyle (Home/Rewards/Library ile simetrik) bunu sağlar. Reset LOGIC'i DiscoverKit'te CI-testli; bu
/// test WIRING'i doğrular.
@MainActor
final class AccountSwitchDiscoverResetTests: XCTestCase {
    func testDifferentAccountSwitchResetsKesfetButSameUserIDDoesNot() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        // `tab` test süresince TUTULUR: üretimde coordinator app ömrü boyunca yaşar (weak-self gözlemci
        // canlı kalır); tutmazsak DiscoverCoordinator dealloc olup gözlemci no-op olurdu.
        let tab = TabCoordinator(composition: composition)
        let model = tab.discover.kesfetModel // lazy init → gözlemci bu instance'ı reset edecek
        model.selectGenre("romance") // A'nın tür filtresi
        XCTAssertEqual(model.selectedGenreID, "romance")

        // Aynı userID'nin yeniden emisyonu (link/re-auth AYNI hesap = §3.3 sıfır-kayıp) reset ETMEMELİ.
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertEqual(model.selectedGenreID, "romance") // aynı hesap → reset yok

        // FARKLI hesaba geçiş (409 switch → userID değişir) → reset (filtre "Tümü"e döner).
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if model.selectedGenreID == nil {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // hesap değişimi Kesfet filtresini/layout'unu sıfırladı
        XCTAssertNil(model.content) // A'nın per-user discover layout'u temizlendi
    }

    /// Self-review2 (Home/Rewards/Library ile simetrik): gözlemci nil-userID ara-durumundan (loggedOut) GEÇEN
    /// gerçek switch'i (u1→loggedOut→u2) yakalamalı → A'nın filtresi/layout'u sızmasın.
    func testDiscoverSwitchThroughLoggedOutIntermediateStateStillResets() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        let model = tab.discover.kesfetModel
        model.selectGenre("action")
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertEqual(model.selectedGenreID, "action")

        // u1 → loggedOut (nil ara-durum) → u2: nil'den geçse de switch algılanmalı.
        session.send(.loggedOut(previousUserID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if model.selectedGenreID == nil {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // nil-ara-durumdan geçen switch yakalandı
    }
}
