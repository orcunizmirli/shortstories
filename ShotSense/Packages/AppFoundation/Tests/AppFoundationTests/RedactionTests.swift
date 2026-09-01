import Testing
@testable import AppFoundation

@Suite("Redaction")
struct RedactionTests {
    @Test("Maske kaynak uzunluğunu sızdırmaz")
    func maskDoesNotLeakLength() {
        // Farklı uzunluktaki iki şifre aynı maskeyi üretmeli; aksi hâlde ekrandaki nokta
        // sayısından şifre uzunluğu okunabilirdi (KANON §7).
        #expect(Redaction.mask("ab") == Redaction.mask("uzun-bir-wifi-sifresi"))
    }

    @Test("Son ekli maske yalnız istenen kadar karakter gösterir")
    func maskShowsRequestedSuffix() {
        #expect(Redaction.mask("TR330006100519786457841326", visibleSuffix: 4) == "•••• 1326")
    }

    @Test("Sonek değerden uzunsa hiçbir şey açığa çıkmaz")
    func suffixLongerThanValueIsFullyMasked() {
        #expect(Redaction.mask("123", visibleSuffix: 8) == "••••")
    }

    @Test("Boş ve boşluk-yalnız değer boş döner")
    func emptyStaysEmpty() {
        #expect(Redaction.mask("   ") == "")
    }

    @Test("Özet metnin kendisini içermez")
    func summaryOmitsContent() {
        let summary = Redaction.summarize("sifre123")
        #expect(!summary.contains("sifre"))
        #expect(summary.contains("len=8"))
    }
}
