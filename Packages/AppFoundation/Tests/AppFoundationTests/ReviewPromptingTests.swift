import AppFoundationTestSupport
import Foundation
import Testing
@testable import AppFoundation

/// RTG-01 uygulama-içi puanlama istemi (00-genel-bakis.md §294): YALNIZCA pozitif anlarda, terbiyeli
/// sıklıkla. Politika (saf karar) + controller (kalıcı sayaç/damga + port) davranışını kilitler.
@MainActor
private final class MockReviewRequester: ReviewRequesting {
    private(set) var requestCount = 0
    func requestReview() {
        requestCount += 1
    }
}

@MainActor
@Suite("ReviewPromptPolicy — saf karar")
struct ReviewPromptPolicyTests {
    private let policy = ReviewPromptPolicy(minPositiveMoments: 3, minDaysBetweenPrompts: 120)
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    @Test func esikAltiPozitifAnIstemez() {
        #expect(!policy.shouldRequest(
            positiveMomentCount: 2, lastPromptAt: nil, lastPromptVersion: nil,
            currentVersion: "1.0", now: now
        ))
    }

    @Test func esikteVeHicIstenmemisIster() {
        #expect(policy.shouldRequest(
            positiveMomentCount: 3, lastPromptAt: nil, lastPromptVersion: nil,
            currentVersion: "1.0", now: now
        ))
    }

    @Test func ayniSurumdeTekrarIstemez() {
        #expect(!policy.shouldRequest(
            positiveMomentCount: 10, lastPromptAt: now.addingTimeInterval(-400 * 86400),
            lastPromptVersion: "1.0", currentVersion: "1.0", now: now
        ))
    }

    @Test func farkliSurumVeYeterliGunGecmisIster() {
        #expect(policy.shouldRequest(
            positiveMomentCount: 10, lastPromptAt: now.addingTimeInterval(-200 * 86400),
            lastPromptVersion: "1.0", currentVersion: "1.1", now: now
        ))
    }

    @Test func sonIstemdenBeriYeterliGunGecmediyseIstemez() {
        #expect(!policy.shouldRequest(
            positiveMomentCount: 10, lastPromptAt: now.addingTimeInterval(-30 * 86400),
            lastPromptVersion: "1.0", currentVersion: "1.1", now: now
        ))
    }

    @Test func negatifElapsedSaatGeriAlindiIstemez() {
        // Cihaz saati geri alındı → lastPromptAt gelecekte → elapsed negatif < eşik → isteme.
        #expect(!policy.shouldRequest(
            positiveMomentCount: 10, lastPromptAt: now.addingTimeInterval(86400),
            lastPromptVersion: "1.0", currentVersion: "1.1", now: now
        ))
    }
}

@MainActor
@Suite("ReviewPromptController — kalıcı sayaç + port tetikleme")
struct ReviewPromptControllerTests {
    private let base = Date(timeIntervalSince1970: 1_000_000_000)

    private func make(
        version: String,
        prefs: MockPreferences,
        requester: MockReviewRequester
    ) -> ReviewPromptController {
        ReviewPromptController(
            requester: requester,
            preferences: prefs,
            currentAppVersion: version,
            policy: ReviewPromptPolicy(minPositiveMoments: 3, minDaysBetweenPrompts: 120)
        )
    }

    @Test func esikAltindaIstemYok() {
        let requester = MockReviewRequester()
        let controller = make(version: "1.0", prefs: MockPreferences(), requester: requester)
        controller.recordPositiveMoment(.episodeCompleted, now: base)
        controller.recordPositiveMoment(.episodeCompleted, now: base)
        #expect(requester.requestCount == 0) // 2 < 3
    }

    @Test func donusDegeriTalepEdilipEdilmediginiYansitir() {
        // RTG-01 kriter 5: çağıran, GERÇEK talep edildiğinde (true) "review_prompt_requested" yazar.
        let controller = make(version: "1.0", prefs: MockPreferences(), requester: MockReviewRequester())
        #expect(controller.recordPositiveMoment(.episodeCompleted, now: base) == false) // 1 < 3
        #expect(controller.recordPositiveMoment(.streakDay, now: base) == false) // 2 < 3
        #expect(controller.recordPositiveMoment(.episodeCompleted, now: base) == true) // 3 → talep edildi
        #expect(controller.recordPositiveMoment(.episodeCompleted, now: base) == false) // aynı sürüm guard
    }

    @Test func esigeUlasincaBirKezIster() {
        let requester = MockReviewRequester()
        let controller = make(version: "1.0", prefs: MockPreferences(), requester: requester)
        controller.recordPositiveMoment(.episodeCompleted, now: base)
        controller.recordPositiveMoment(.streakDay, now: base)
        controller.recordPositiveMoment(.episodeCompleted, now: base) // 3. an → istenir
        #expect(requester.requestCount == 1)
    }

    @Test func istemSonrasiAyniSurumdeTekrarIstemez() {
        let requester = MockReviewRequester()
        let controller = make(version: "1.0", prefs: MockPreferences(), requester: requester)
        for _ in 0 ..< 6 {
            controller.recordPositiveMoment(.episodeCompleted, now: base)
        }
        #expect(requester.requestCount == 1) // eşikte bir kez; sonrası aynı sürüm → guard
    }

    @Test func durumRelaunchArasiSurumGuardiKorunur() {
        // Oturum A: eşiğe ulaş, istem tetiklenir; durum kalıcı prefs'te.
        let prefs = MockPreferences()
        let requesterA = MockReviewRequester()
        let controllerA = make(version: "1.0", prefs: prefs, requester: requesterA)
        for _ in 0 ..< 3 {
            controllerA.recordPositiveMoment(.episodeCompleted, now: base)
        }
        #expect(requesterA.requestCount == 1)

        // Oturum B (relaunch): AYNI prefs, AYNI sürüm, gün-eşiği ÇOK ÖTELENMİŞ (300 gün) → gün-guard'ı
        // geçse bile SÜRÜM-guard'ı (kalıcı son-istem-sürümü) tekrar istemi engeller.
        let requesterB = MockReviewRequester()
        let controllerB = make(version: "1.0", prefs: prefs, requester: requesterB)
        controllerB.recordPositiveMoment(.episodeCompleted, now: base.addingTimeInterval(300 * 86400))
        #expect(requesterB.requestCount == 0) // aynı sürümde zaten istendi (kalıcı sürüm guard)
    }

    @Test func yeniSurumdeYeterliGunSonraTekrarIster() {
        let prefs = MockPreferences()
        let requesterA = MockReviewRequester()
        let controllerA = make(version: "1.0", prefs: prefs, requester: requesterA)
        for _ in 0 ..< 3 {
            controllerA.recordPositiveMoment(.episodeCompleted, now: base)
        }
        #expect(requesterA.requestCount == 1)

        // Yeni sürüm + 200 gün sonra → yeniden istenebilir.
        let requesterB = MockReviewRequester()
        let controllerB = make(version: "1.1", prefs: prefs, requester: requesterB)
        controllerB.recordPositiveMoment(.episodeCompleted, now: base.addingTimeInterval(200 * 86400))
        #expect(requesterB.requestCount == 1)
    }
}
