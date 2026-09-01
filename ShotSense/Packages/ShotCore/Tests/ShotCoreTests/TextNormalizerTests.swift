import Testing
@testable import ShotCore

@Suite("TextNormalizer")
struct TextNormalizerTests {
    @Test("Türkçe noktalı I katlaması eşleşmeyi bozmaz")
    func turkishDottedICaseFolding() {
        #expect(TextNormalizer.fold("MİGROS") == TextNormalizer.fold("migros"))
        #expect(TextNormalizer.fold("IŞIK") == TextNormalizer.fold("ışık"))
    }

    @Test("Alfanümerik indirgeme biçimlendirmeyi yok sayar")
    func alphanumericStripsFormatting() {
        #expect(
            TextNormalizer.alphanumeric("TR33 0006-1005.1978")
                == TextNormalizer.alphanumeric("tr330006100519 78")
        )
    }

    @Test("Tokenizasyon tek karakterlik parçaları atar")
    func tokenizerDropsShortTokens() {
        #expect(TextNormalizer.tokenize("a bb ccc 1 22") == ["bb", "ccc", "22"])
    }

    @Test("Tokenizasyon noktalama üzerinden böler")
    func tokenizerSplitsOnPunctuation() {
        #expect(TextNormalizer.tokenize("toplam:249,90TL") == ["toplam", "249", "90tl"])
    }
}
