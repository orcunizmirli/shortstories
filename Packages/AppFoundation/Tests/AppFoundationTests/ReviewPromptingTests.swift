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
            positiveMomentCount: 2, state: ReviewPromptState(), currentVersion: "1.0", now: now
        ))
    }

    @Test func esikteVeHicIstenmemisIster() {
        #expect(policy.shouldRequest(
            positiveMomentCount: 3, state: ReviewPromptState(), currentVersion: "1.0", now: now
        ))
    }

    @Test func ayniSurumdeTekrarIstemez() {
        let state = ReviewPromptState(lastPromptAt: now.addingTimeInterval(-400 * 86400), lastPromptVersion: "1.0")
        #expect(!policy.shouldRequest(positiveMomentCount: 10, state: state, currentVersion: "1.0", now: now))
    }

    @Test func farkliSurumVeYeterliGunGecmisIster() {
        let state = ReviewPromptState(lastPromptAt: now.addingTimeInterval(-200 * 86400), lastPromptVersion: "1.0")
        #expect(policy.shouldRequest(positiveMomentCount: 10, state: state, currentVersion: "1.1", now: now))
    }

    @Test func sonIstemdenBeriYeterliGunGecmediyseIstemez() {
        let state = ReviewPromptState(lastPromptAt: now.addingTimeInterval(-30 * 86400), lastPromptVersion: "1.0")
        #expect(!policy.shouldRequest(positiveMomentCount: 10, state: state, currentVersion: "1.1", now: now))
    }

    @Test func negatifElapsedSaatGeriAlindiIstemez() {
        // Cihaz saati geri alındı → lastPromptAt gelecekte → elapsed negatif < eşik → isteme.
        let state = ReviewPromptState(lastPromptAt: now.addingTimeInterval(86400), lastPromptVersion: "1.0")
        #expect(!policy.shouldRequest(positiveMomentCount: 10, state: state, currentVersion: "1.1", now: now))
    }

    @Test func yakinNegatifSinyalPenceresiIcindeIstemez() {
        // Şikayet/hata sinyali penceresi içinde (14 gün) istem bastırılır → önce destek akışı (RTG-01 k3).
        let state = ReviewPromptState(lastNegativeSignalAt: now.addingTimeInterval(-3 * 86400))
        #expect(!policy.shouldRequest(positiveMomentCount: 10, state: state, currentVersion: "1.0", now: now))
    }

    @Test func eskiNegatifSinyalPencereDisindaIster() {
        // Negatif sinyal penceresi (14 gün) GEÇMİŞSE artık bastırılmaz.
        let state = ReviewPromptState(lastNegativeSignalAt: now.addingTimeInterval(-30 * 86400))
        #expect(policy.shouldRequest(positiveMomentCount: 10, state: state, currentVersion: "1.0", now: now))
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

    @Test func negatifSinyalSonrasiIstemBastirilir() {
        // RTG-01 kriter 3: yakın zamanda negatif sinyal (oynatma hatası/başarısız satın alma) → eşik
        // aşılsa bile istem bastırılır (kalıcı damga).
        let requester = MockReviewRequester()
        let controller = make(version: "1.0", prefs: MockPreferences(), requester: requester)
        controller.recordNegativeSignal(now: base)
        for _ in 0 ..< 5 {
            controller.recordPositiveMoment(.episodeCompleted, now: base)
        }
        #expect(requester.requestCount == 0)
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
