import Testing
@testable import PlayerKit

/// SS-046 altyazı-track eşleştirici (saf karar). BCP-47 birincil alt-etiket eşleşmesi, region toleransı,
/// off/eşleşmeyen davranışı. Gerçek AVMediaSelection uygulaması AVPlayerBackend'de (sim/cihaz perf koşusu).
struct SubtitleTrackSelectorTests {
    private func opt(_ index: Int, _ tag: String?) -> SubtitleTrackSelector.Option {
        SubtitleTrackSelector.Option(index: index, languageTag: tag)
    }

    @Test func nilKodKapaliDoner() {
        #expect(SubtitleTrackSelector.decide(preferredCode: nil, available: [opt(0, "en")]) == .off)
    }

    @Test func bosKodKapaliDoner() {
        // Off sentinel boş string de kapalı sayılır (adaptör nil taşır ama savunmacı).
        #expect(SubtitleTrackSelector.decide(preferredCode: "", available: [opt(0, "en")]) == .off)
    }

    @Test func tamEslesmeSecilir() {
        let options = [opt(0, "en"), opt(1, "tr"), opt(2, "es")]
        #expect(SubtitleTrackSelector.decide(preferredCode: "tr", available: options) == .select(index: 1))
    }

    @Test func regionToleransiPtBRIleEslesir() {
        // "pt" tercihi "pt-BR" track'iyle eşleşmeli (birincil alt-etiket).
        #expect(SubtitleTrackSelector.decide(preferredCode: "pt", available: [opt(0, "pt-BR")]) == .select(index: 0))
    }

    @Test func buyukKucukHarfVeAltCizgiToleransi() {
        #expect(SubtitleTrackSelector.decide(preferredCode: "EN", available: [opt(0, "en_US")]) == .select(index: 0))
    }

    @Test func eslesmeyenDilKapaliDoner() {
        // Asset bu dili sunmuyor → kapalı (tercih persist'te korunur, burada uygulanmaz).
        #expect(SubtitleTrackSelector.decide(preferredCode: "de", available: [opt(0, "en"), opt(1, "tr")]) == .off)
    }

    @Test func bosListeKapaliDoner() {
        #expect(SubtitleTrackSelector.decide(preferredCode: "en", available: []) == .off)
    }

    @Test func ilkEslesenIndexSecilir() {
        // Birden çok aynı-dil option'ında ilk eşleşen döner.
        let options = [opt(0, "fr"), opt(1, "en"), opt(2, "en")]
        #expect(SubtitleTrackSelector.decide(preferredCode: "en", available: options) == .select(index: 1))
    }

    @Test func nilLanguageTagliOptionEslesmez() {
        #expect(SubtitleTrackSelector.decide(preferredCode: "en", available: [opt(0, nil)]) == .off)
    }

    // MARK: - primarySubtag (menü + seçim AYNI normalleştirmeyi paylaşır — review bulgusu)

    @Test func primarySubtagRegionKoduSoyar() {
        #expect(SubtitleTrackSelector.primarySubtag("pt-BR") == "pt")
        #expect(SubtitleTrackSelector.primarySubtag("es-419") == "es")
        #expect(SubtitleTrackSelector.primarySubtag("en_US") == "en")
    }

    @Test func primarySubtagBuyukHarfKucultur() {
        #expect(SubtitleTrackSelector.primarySubtag("EN") == "en")
        #expect(SubtitleTrackSelector.primarySubtag("zh-Hant") == "zh")
    }

    @Test func primarySubtagNilVeBosNilDoner() {
        #expect(SubtitleTrackSelector.primarySubtag(nil) == nil)
        #expect(SubtitleTrackSelector.primarySubtag("") == nil)
    }
}
