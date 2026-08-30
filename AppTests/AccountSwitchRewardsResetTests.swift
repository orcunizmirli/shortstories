import AppFoundation
import AppFoundationTestSupport
import RewardsKit
import XCTest
@testable import ShortSeriesApp

/// Cross-account (05 §3.3, SS-132 sınıfı): uzun-ömürlü `OdulMerkeziModel` (TabCoordinator ömrü, switch'te
/// yeniden yaratılmaz) hesap DEĞİŞİMİNDE sıfırlanmalı → önceki hesabın check-in/görev/bakiye state'i yeni
/// hesaba sızmasın. `RewardsCoordinator` her-zaman-canlı session gözlemcisiyle bunu sağlar (switch hangi
/// sekmede olursa olsun yakalanır). Reset LOGIC'i RewardsKit'te CI-testli; bu test WIRING'i doğrular.
@MainActor
final class AccountSwitchRewardsResetTests: XCTestCase {
    func testDifferentAccountSwitchResetsModelButSameUserIDDoesNot() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        // TabCoordinator init → RewardsCoordinator → hesap-değişimi gözlemcisi başlar. `tab` test süresince
        // TUTULUR: üretimde coordinator app ömrü boyunca yaşar (weak-self gözlemci canlı kalır); tutmazsak
        // RewardsCoordinator dealloc olup gözlemci no-op olurdu.
        let tab = TabCoordinator(composition: composition)
        let model = tab.rewards.odulMerkeziModel
        model.onAppear()
        // İlk yükleme tamamlanana dek bekle (pendingWork internal; loadState terminal olunca biter).
        for _ in 0 ..< 1000 where model.loadState == .loading {
            await Task.yield()
        }
        let loadedState = model.loadState
        XCTAssertNotEqual(loadedState, .loading) // ilk yükleme tamamlandı (terminal durum)

        // Aynı userID'nin yeniden emisyonu (link/re-auth AYNI hesap = §3.3 sıfır-kayıp) reset ETMEMELİ.
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertEqual(model.loadState, loadedState) // aynı hesap → reset yok

        // FARKLI hesaba geçiş (409 switch → userID değişir) → reset (loadState .loading olur).
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if model.loadState == .loading {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // hesap değişimi modeli sıfırladı
        XCTAssertNil(model.checkInState) // hesap-özel state temizlendi
    }

    /// Self-review2 (HomeCoordinator ile simetrik): gözlemci nil-userID ara-durumundan (loggedOut) GEÇEN
    /// gerçek switch'i (u1→loggedOut→u2) yakalamalı → önceki hesabın check-in/görev state'i sızmasın.
    func testRewardsSwitchThroughLoggedOutIntermediateStateStillResets() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        let model = tab.rewards.odulMerkeziModel
        model.onAppear()
        for _ in 0 ..< 1000 where model.loadState == .loading {
            await Task.yield()
        }
        // Baseline u1 (gözlemci lastUserID=u1).
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertNotEqual(model.loadState, .loading)

        // u1 → loggedOut (nil ara-durum) → u2: nil'den geçse de switch algılanmalı.
        session.send(.loggedOut(previousUserID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if model.loadState == .loading {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // FIX: nil-ara-durumdan geçen switch yakalandı
        XCTAssertNil(model.checkInState)
    }
}
