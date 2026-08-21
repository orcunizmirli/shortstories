import UIKit
import XCTest
@testable import ShortSeriesApp

/// SS-113 AdMob rewarded-ad sunum bağlamı: reklam, anahtar pencerenin EN ÜSTTEKİ sunulan view
/// controller'ından present edilmeli. UnlockSheet MODAL sunulduğu için taban root zaten bir sunum
/// yapıyordur; reklam taban'dan present edilirse UIKit ikinci sunumu reddeder → `.failed` (reklamla
/// kilit hiç açılmaz). Bu suite saf `topmostViewController(from:)` walk'unu izole doğrular (gerçek
/// sunum/runloop gerektirmeden — sahte zincir `presentedViewController` override'ıyla kurulur).
@MainActor
final class RealRewardedAdPresentationTests: XCTestCase {
    func testTopmostReturnsBaseWhenNothingPresented() {
        let base = UIViewController()
        XCTAssertIdentical(RealRewardedAdProvider.topmostViewController(from: base), base)
    }

    func testTopmostWalksPresentedChainToLeaf() {
        // base → mid → leaf (leaf hiçbir şey sunmaz). En üstteki = leaf.
        let leaf = UIViewController()
        let mid = StubPresentingViewController(presented: leaf)
        let base = StubPresentingViewController(presented: mid)

        XCTAssertIdentical(RealRewardedAdProvider.topmostViewController(from: base), leaf)
    }

    func testTopmostWalksSingleLevelModal() {
        // Kritik senaryo: UnlockSheet gibi TEK modal sunumu — taban değil, sunulan sheet döndürülmeli.
        let sheet = UIViewController()
        let base = StubPresentingViewController(presented: sheet)

        XCTAssertIdentical(RealRewardedAdProvider.topmostViewController(from: base), sheet)
    }
}

/// `presentedViewController` getter'ını override ederek gerçek sunum/runloop olmadan sahte modal zincir
/// kurar (`presentedViewController` `open` — override edilebilir).
private final class StubPresentingViewController: UIViewController {
    private let presented: UIViewController?

    init(presented: UIViewController?) {
        self.presented = presented
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) kullanılmıyor")
    }

    override var presentedViewController: UIViewController? {
        presented
    }
}
