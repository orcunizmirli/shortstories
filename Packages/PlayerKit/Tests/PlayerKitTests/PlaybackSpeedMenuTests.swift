import Testing
@testable import PlayerKit

/// Hız menüsü saf yardımcısı (04 §8.2): kanonik seçenekler, etiket biçimi, güncel-hız eşleme.
struct PlaybackSpeedMenuTests {
    @Test func kanonikHizlarArtanVeNormaliIcerir() {
        #expect(PlaybackSpeedMenu.rates == [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
        #expect(PlaybackSpeedMenu.rates.contains(1.0))
    }

    @Test func etiketTamSayiGereksizSifirYok() {
        #expect(PlaybackSpeedMenu.label(for: 1.0) == "1x")
        #expect(PlaybackSpeedMenu.label(for: 2.0) == "2x")
    }

    @Test func etiketKesirliDogruBicimlenir() {
        #expect(PlaybackSpeedMenu.label(for: 0.5) == "0.5x")
        #expect(PlaybackSpeedMenu.label(for: 0.75) == "0.75x")
        #expect(PlaybackSpeedMenu.label(for: 1.25) == "1.25x")
        #expect(PlaybackSpeedMenu.label(for: 1.5) == "1.5x")
    }

    @Test func selectedListedekiHiziYansitir() {
        #expect(PlaybackSpeedMenu.selected(for: 1.5) == 1.5)
    }

    @Test func selectedListedeOlmayanHizNormaleDuser() {
        #expect(PlaybackSpeedMenu.selected(for: 3.0) == 1.0) // bilinmeyen → normal
    }
}
