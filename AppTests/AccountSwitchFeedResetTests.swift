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

    /// Self-review2 (MEDIUM, paywall bypass): gözlemci nil-userID ARA-DURUMUNDAN (loggedOut/session-death)
    /// geçen gerçek hesap geçişini KAÇIRIYORDU — `lastUserID = state.userID` koşulsuz olduğundan loggedOut'ta
    /// nil'e set ediliyordu → sonraki FARKLI hesaba re-auth `previous=nil` ile switch algılanamıyordu →
    /// A'nın `.unlocked` feedState'i B'ye sızıyordu. Fix: lastUserID yalnız non-nil userID'de güncellenir.
    func testSwitchThroughLoggedOutIntermediateStateStillResets() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        let home = tab.home
        let tokenStart = home.feedMountToken

        // Baseline: gözlemci u1'i lastUserID olarak deterministik kursun (replay-on-subscribe yarışı yok).
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }

        // u1 → loggedOut (session-death): reset ETMEZ (kurtarılabilir), ama lastUserID KORUNMALI (nil'lenmemeli).
        session.send(.loggedOut(previousUserID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        XCTAssertEqual(home.feedMountToken, tokenStart) // loggedOut tek başına reset ETMEZ

        // loggedOut → FARKLI hesaba re-auth (u2): nil-ara-durumdan geçse de SWITCH algılanmalı → feed reset.
        session.send(.linked(userID: "u2", provider: .apple))
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if home.feedMountToken != tokenStart {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset) // FIX: nil-ara-durumdan geçen gerçek switch yakalandı (paywall sızıntısı kapandı)
        XCTAssertTrue(home.feedViewModel.feedState.items.isEmpty)
    }

    /// Self-review2 negatif taraf: loggedOut → AYNI hesaba re-auth (u1) reset ETMEMELİ (§3.3 sıfır-kayıp
    /// re-auth). lastUserID korunduğundan previous=u1==current=u1 → switch değil.
    func testReauthToSameAccountThroughLoggedOutDoesNotReset() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        let home = tab.home
        let tokenStart = home.feedMountToken

        // Baseline u1 kur (gözlemci lastUserID=u1).
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        session.send(.loggedOut(previousUserID: "u1", provider: .apple))
        session.send(.linked(userID: "u1", provider: .apple)) // AYNI hesaba geri dönüş
        for _ in 0 ..< 200 {
            await Task.yield()
        }
        XCTAssertEqual(home.feedMountToken, tokenStart) // aynı hesap re-auth → reset YOK (sıfır-kayıp korunur)
    }

    /// Self-review2 (LOW): resetForAccountSwitch A'nın Ana Sayfa navigasyon stack'ini (`path`) da temizlemeli
    /// → B'nin Ana Sayfa'sında A'nın DiziDetay push'u kalmasın.
    func testAccountSwitchClearsHomeNavigationStack() async throws {
        let session = MockSession(state: .linked(userID: "u1", provider: .apple))
        let composition = try AppComposition(dependencies: PreviewDependencies(session: session))
        let tab = TabCoordinator(composition: composition)
        let home = tab.home
        let tokenStart = home.feedMountToken

        // Baseline u1 kur (gözlemci lastUserID=u1).
        session.send(.linked(userID: "u1", provider: .apple))
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        home.path.append(AppRoute.diziDetay(seriesID: SeriesID("s1"), source: .playerFeed)) // A'nın nav stack'i
        XCTAssertFalse(home.path.isEmpty)

        session.send(.linked(userID: "u2", provider: .apple)) // switch
        var didReset = false
        for _ in 0 ..< 500 where !didReset {
            if home.feedMountToken != tokenStart {
                didReset = true
            } else {
                await Task.yield()
            }
        }
        XCTAssertTrue(didReset)
        XCTAssertTrue(home.path.isEmpty) // FIX: A'nın nav stack'i B'ye taşınmadı
    }
}
