import DiscoverKit
import XCTest
@testable import ShortSeriesApp

/// SS-144 R3: BildirimMerkezi landing (deep-link `shortseries://notifications` + push tap ikisi de
/// Profil'e geçip push eder, 03 §3.2 kural 4) IDEMPOTENT olmalı. Ardışık iki landing üst üste özdeş
/// ekran + kopya geri-düğmesi üretmemeli. `ProfileCoordinator.showNotificationCenter` / `showSettings`
/// tam bu kompozisyon-kökü yardımcıyı kullanır; burada seam saf (kompozisyonsuz) doğrulanır.
final class ProfileNavigationIdempotencyTests: XCTestCase {
    /// Aynı rota zaten stack'in tepesindeyken tekrar push EDİLMEZ (idempotent deep-link/push landing).
    func testAppendIfNotTopSkipsDuplicateTopRoute() {
        var path: [AppRoute] = []
        path.appendIfNotTop(.bildirimMerkezi)
        path.appendIfNotTop(.bildirimMerkezi)
        XCTAssertEqual(path, [.bildirimMerkezi], "aynı rota zaten en üstteyken tekrar push edilmemeli (path derinliği 1)")
    }

    /// Farklı rota her zaman push edilir; yalnız TEPEDEKİ özdeş rota bastırılır (genel push kırılmaz).
    func testAppendIfNotTopStacksDistinctRoutes() {
        var path: [AppRoute] = []
        path.appendIfNotTop(.ayarlar)
        path.appendIfNotTop(.bildirimMerkezi)
        path.appendIfNotTop(.bildirimMerkezi)
        XCTAssertEqual(path, [.ayarlar, .bildirimMerkezi])
    }
}
