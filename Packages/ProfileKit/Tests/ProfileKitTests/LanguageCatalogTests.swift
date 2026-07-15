import AppFoundation
import Testing
@testable import ProfileKit

@Suite("SS-161 dil kataloğu + değer tipleri (saf)")
struct LanguageCatalogTests {
    @Test func appLanguageResolvesKnownCode() {
        #expect(LanguageCatalog.appLanguage(forStoredCode: "tr") == .turkish)
    }

    @Test func appLanguageUnknownCodeFallsBackToDefault() {
        // Uygulama dili izin listesine tabidir — paketlenmemiş dile UI ayarlanamaz.
        #expect(LanguageCatalog.appLanguage(forStoredCode: "xx") == .default)
        #expect(AppLanguage.default == .english)
    }

    @Test func subtitleOffSentinelResolvesToOff() {
        // Kapalı durumun kalıcı sentinel'i boş dizedir; literal "off" kodu artık GERÇEK bir
        // track'tir (sunucu-tanımlı), altyazı-kapalı DEĞİL (review #9).
        #expect(LanguageCatalog.subtitleLanguage(forStoredCode: "") == .off)
        #expect(SubtitleLanguage.off.isOff)
        #expect(LanguageCatalog.subtitleLanguage(forStoredCode: "off").isOff == false)
        #expect(LanguageCatalog.subtitleLanguage(forStoredCode: "off").code == "off")
    }

    @Test func realOffCodedTrackSurvivesRoundTripWithoutSilentLoss() {
        // Regresyon (review #9): kodu literal "off" olan gerçek sunucu track'i altyazı-kapalıya
        // round-trip olup kullanıcı seçimini KAYBETMEMELİ.
        let realOff = SubtitleLanguage(code: "off")
        #expect(realOff.isOff == false)
        let restored = SubtitleLanguage(persistedCode: realOff.persistedValue)
        #expect(restored == realOff)
        #expect(restored.code == "off")
        #expect(restored.isOff == false)
        // Gerçek kapalı durumdan hem kalıcı temsil hem kimlik olarak AYRIK.
        #expect(SubtitleLanguage.off.persistedValue != realOff.persistedValue)
        #expect(SubtitleLanguage.off.id != realOff.id)
    }

    @Test func subtitleKnownCodeResolves() {
        #expect(LanguageCatalog.subtitleLanguage(forStoredCode: "es") == .spanish)
    }

    @Test func subtitleUnknownCodeIsHonored() {
        // Altyazı izin listesine tabi DEĞİLDİR (sunucu-tanımlı track'ler) — kullanıcı seçimi korunur.
        let value = LanguageCatalog.subtitleLanguage(forStoredCode: "ja")
        #expect(value.code == "ja")
        #expect(value.isOff == false)
    }

    @Test func subtitlePersistedRoundTrip() {
        #expect(SubtitleLanguage.off.persistedValue != "off") // sentinel, gerçek koddan ayrık
        #expect(SubtitleLanguage.spanish.persistedValue == "es")
        #expect(SubtitleLanguage(persistedCode: "es") == .spanish)
        #expect(SubtitleLanguage(persistedCode: SubtitleLanguage.off.persistedValue) == .off)
    }

    @Test func supportedAppLanguagesAreCanonical() {
        #expect(LanguageCatalog.supportedAppLanguages == [.english, .turkish, .spanish, .portuguese])
    }

    @Test func offeredSubtitleLanguagesStartWithOff() {
        #expect(LanguageCatalog.offeredSubtitleLanguages.first == .off)
        #expect(LanguageCatalog.offeredSubtitleLanguages.contains(.english))
    }

    @Test func endonymIsLanguageOwnName() {
        #expect(AppLanguage.turkish.displayName == "Türkçe")
        #expect(AppLanguage.english.displayName == "English")
        #expect(SubtitleLanguage.spanish.displayName == "Español")
        #expect(SubtitleLanguage.off.displayName == nil)
    }

    @Test func appAndSubtitleAreIndependentTypes() {
        // SS-161 çekirdek: uygulama dili tr iken altyazı es olabilir (bağımsız).
        let app = LanguageCatalog.appLanguage(forStoredCode: "tr")
        let subtitle = LanguageCatalog.subtitleLanguage(forStoredCode: "es")
        #expect(app.code == "tr")
        #expect(subtitle.code == "es")
    }
}
