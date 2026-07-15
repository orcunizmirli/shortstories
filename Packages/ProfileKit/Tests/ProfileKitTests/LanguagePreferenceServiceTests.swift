import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ProfileKit

@Suite("SS-161 dil tercihi servisi (kalıcılık + anlık yayın)")
struct LanguagePreferenceServiceTests {
    @Test func initReadsFromPreferences() {
        let prefs = MockPreferences()
        prefs.set("tr", for: ProfilePreferenceKeys.appLanguageCode)
        prefs.set("es", for: PreferenceKeys.subtitleLanguageCode)
        let service = LanguagePreferenceService(preferences: prefs)
        #expect(service.appLanguage == .turkish)
        #expect(service.currentSubtitleLanguage == .spanish)
    }

    @Test func setSubtitlePersistsToSingleSource() {
        let prefs = MockPreferences()
        let service = LanguagePreferenceService(preferences: prefs)
        #expect(service.setSubtitleLanguage(.turkish))
        #expect(prefs.value(for: PreferenceKeys.subtitleLanguageCode) == "tr")
        #expect(service.currentSubtitleLanguage == .turkish)
    }

    @Test func setOffPersistsSentinelDistinctFromRealCodes() {
        let prefs = MockPreferences()
        let service = LanguagePreferenceService(preferences: prefs)
        service.setSubtitleLanguage(.off)
        let persisted = prefs.value(for: PreferenceKeys.subtitleLanguageCode)
        #expect(persisted != "off") // gerçek 'off' koduyla çakışmaz (review #9)
        #expect(SubtitleLanguage(persistedCode: persisted).isOff) // geri okununca kapalı
        #expect(service.currentSubtitleLanguage.isOff)
    }

    @Test func setSameValueReturnsFalse() {
        let service = LanguagePreferenceService(preferences: MockPreferences())
        // Varsayılan altyazı english → aynı değeri set etmek no-op.
        #expect(service.setSubtitleLanguage(.english) == false)
    }

    @Test func setSubtitleBroadcastsInstantly() async {
        let service = LanguagePreferenceService(preferences: MockPreferences())
        var iterator = service.subtitleLanguageUpdates().makeAsyncIterator()
        let replayed = await iterator.next() // current-value replay
        #expect(replayed == .english)
        service.setSubtitleLanguage(.spanish)
        let update = await iterator.next()
        #expect(update == .spanish)
    }

    @Test func setAppLanguagePersistsAndBroadcasts() async {
        let prefs = MockPreferences()
        let service = LanguagePreferenceService(preferences: prefs)
        var iterator = service.appLanguageUpdates().makeAsyncIterator()
        _ = await iterator.next() // replay english
        #expect(service.setAppLanguage(.portuguese))
        #expect(prefs.value(for: ProfilePreferenceKeys.appLanguageCode) == "pt")
        let update = await iterator.next()
        #expect(update == .portuguese)
    }

    @Test func appAndSubtitleChangeIndependently() {
        let prefs = MockPreferences()
        let service = LanguagePreferenceService(preferences: prefs)
        service.setAppLanguage(.turkish)
        service.setSubtitleLanguage(.spanish)
        #expect(service.appLanguage == .turkish)
        #expect(service.currentSubtitleLanguage == .spanish)
        #expect(prefs.value(for: ProfilePreferenceKeys.appLanguageCode) == "tr")
        #expect(prefs.value(for: PreferenceKeys.subtitleLanguageCode) == "es")
    }

    @Test func subtitleProvidingPortReflectsCurrent() {
        let service = LanguagePreferenceService(preferences: MockPreferences())
        service.setSubtitleLanguage(.turkish)
        let port: any SubtitleLanguageProviding = service
        #expect(port.currentSubtitleLanguage == .turkish)
    }

    // MARK: - Geçersiz kalıcı kod geri-yazma (review #8)

    @Test func invalidStoredAppLanguageWritesBackDefault() {
        let prefs = MockPreferences()
        prefs.set("xx", for: ProfilePreferenceKeys.appLanguageCode) // desteklenmeyen/geçersiz
        let service = LanguagePreferenceService(preferences: prefs)
        #expect(service.appLanguage == .default)
        // Yalnız bellekte .default'a düşmek yetmez — geçersiz kod UserDefaults'tan da temizlenmeli,
        // aksi halde changed-guard yüzünden kalıcı kalır.
        #expect(prefs.value(for: ProfilePreferenceKeys.appLanguageCode) == AppLanguage.default.code)
    }

    @Test func validStoredAppLanguageIsNotRewritten() {
        // Geçerli kod gereksiz yere geri yazılmaz (fazladan set yok).
        let prefs = MockPreferences()
        prefs.set("tr", for: ProfilePreferenceKeys.appLanguageCode)
        let setsBefore = prefs.recordedSetKeys.count
        _ = LanguagePreferenceService(preferences: prefs)
        #expect(prefs.recordedSetKeys.count == setsBefore)
    }

    // MARK: - Persist + broadcast atomikliği (review #7)

    @Test func concurrentWritersCommitMemoryAndPersistAtomically() {
        // Regresyon (review #7): mutasyon kilit altında ama persist+broadcast kilit BIRAKILDIKTAN
        // sonra yapılınca eşzamanlı yazarlar bunları bellek-içi değere göre sırasız commit eder →
        // bellek ile kalıcılık sapabilir. A yazarını persist("tr")'de deterministik bloklayıp B
        // yazarını araya sokuyoruz; atomik commit'te bellek == kalıcı SON değer.
        let prefs = GatedPreferences(gate: "tr", signalOnPersist: "es")
        let service = LanguagePreferenceService(preferences: prefs)

        let aDone = DispatchSemaphore(value: 0)
        let bDone = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            service.setAppLanguage(.turkish) // bellek en→tr, persist "tr" (gate'te bloklu)
            aDone.signal()
        }
        prefs.reachedGate.wait() // A persist("tr")'de bloklu

        DispatchQueue.global().async {
            service.setAppLanguage(.spanish) // buggy: hemen tamamlar; fixed: service kilidinde bloklu
            bDone.signal()
        }
        // Buggy'de B persist("es")'i tamamlar → sinyal gelir; fixed'de gelmez → sınırlı timeout.
        _ = prefs.watchPersisted.wait(timeout: .now() + 0.3)
        prefs.releaseGate()

        aDone.wait()
        bDone.wait()

        let persisted = prefs.value(for: ProfilePreferenceKeys.appLanguageCode)
        #expect(service.appLanguage.code == persisted)
    }
}
