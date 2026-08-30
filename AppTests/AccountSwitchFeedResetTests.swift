import AppFoundation
import AppFoundationTestSupport
import XCTest
@testable import ShortSeriesApp

/// Cross-account (05 §3.3, SS-132): uzun-ömürlü HomeCoordinator.feedViewModel (TabCoordinator ömrü,
/// switch'te yeniden yaratılmaz) hesap DEĞİŞİMİNDE sıfırlanmalı → önceki hesabın feedState'i (applyUnlock
/// `.unlocked` işaretleri) yeni hesaba sızmasın (PlayerPool.isPlayable `.unlocked`'a entitlement sormaz →
/// paywall bypass). HomeCoordinator her-zaman-canlı session gözlemcisiyle sağlar (RewardsCoordinator deseni).
@MainActor
final class AccountSwitchFeedResetTests: XCTestCase {
    func testDifferentAccountSwitchRemountsFeedButSameUserIDDoesNot() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        // `tab` TUTULUR: üretimde coordinator app-ömrü yaşar; tutmazsak HomeCoordinator dealloc → gözlemci no-op.
        let tab = TabCoordinator(composition: composition)
        let home = tab.home
        let tokenStart = home.feedMountToken

        // Aynı userID'nin yeniden emisyonu (link/re-auth AYNI hesap = §3.3 sıfır-kayıp) reset ETMEMELİ.
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertEqual(home.feedMountToken, tokenStart) // aynı hesap → reset yok

        // FARKLI hesaba geçiş (409 switch → userID değişir) → feed reset (remount + feedState boş).
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if home.feedMountToken != tokenStart {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // hesap değişimi feed'i remount etti
        XCTAssertTrue(home.feedViewModel.feedState.items.isEmpty) // hesap-özel feed temizlendi
    }
}
