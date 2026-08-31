import AppFoundation
import AppFoundationTestSupport
import LibraryKit
import XCTest
@testable import ShortSeriesApp

/// Cross-account (05 §3.3, SS-132 sınıfı): uzun-ömürlü `ListemModel` (TabCoordinator ömrü, switch'te yeniden
/// yaratılmaz) hesap DEĞİŞİMİNDE sıfırlanmalı → önceki hesabın favorileri/"devam et"/gizli-öğeleri yeni hesaba
/// sızmasın. `LibraryCoordinator` her-zaman-canlı session gözlemcisiyle bunu sağlar (Home/Rewards ile simetrik,
/// switch hangi sekmede olursa olsun yakalanır). Reset LOGIC'i LibraryKit'te CI-testli; bu test WIRING'i doğrular.
@MainActor
final class AccountSwitchLibraryResetTests: XCTestCase {
    func testDifferentAccountSwitchResetsListemButSameUserIDDoesNot() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        // `tab` test süresince TUTULUR: üretimde coordinator app ömrü boyunca yaşar (weak-self gözlemci
        // canlı kalır); tutmazsak LibraryCoordinator dealloc olup gözlemci no-op olurdu.
        let tab = TabCoordinator(composition: composition)
        let model = tab.library.listemModel // lazy init → gözlemci bu instance'ı reset edecek
        model.onAppear()
        for _ in 0 ..< 1000 where model.favoritesState == .loading {
            await Task.yield()
        }
        let loadedState = model.favoritesState
        XCTAssertNotEqual(loadedState, .loading) // ilk yükleme tamamlandı (terminal durum)

        // Aynı userID'nin yeniden emisyonu (link/re-auth AYNI hesap = §3.3 sıfır-kayıp) reset ETMEMELİ.
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertEqual(model.favoritesState, loadedState) // aynı hesap → reset yok

        // FARKLI hesaba geçiş (409 switch → userID değişir) → reset (favoritesState .loading olur).
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if model.favoritesState == .loading {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // hesap değişimi modeli sıfırladı
        XCTAssertTrue(model.favorites.isEmpty) // hesap-özel state temizlendi
    }

    /// Self-review2 (Home/Rewards ile simetrik): gözlemci nil-userID ara-durumundan (loggedOut) GEÇEN gerçek
    /// switch'i (u1→loggedOut→u2) yakalamalı → önceki hesabın favori/geçmiş state'i sızmasın.
    func testLibrarySwitchThroughLoggedOutIntermediateStateStillResets() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        let model = tab.library.listemModel
        model.onAppear()
        for _ in 0 ..< 1000 where model.favoritesState == .loading {
            await Task.yield()
        }
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertNotEqual(model.favoritesState, .loading)

        // u1 → loggedOut (nil ara-durum) → u2: nil'den geçse de switch algılanmalı.
        session.send(.loggedOut(previousUserID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if model.favoritesState == .loading {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // nil-ara-durumdan geçen switch yakalandı
    }
}
