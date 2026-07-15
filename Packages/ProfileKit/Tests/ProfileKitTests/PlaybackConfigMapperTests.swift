import Testing
@testable import ProfileKit

@Suite("SS-048 oynatma tercihi → player-config eşlemesi (saf)")
struct PlaybackConfigMapperTests {
    @Test func defaultPreferencesUnlimited() {
        let config = PlaybackConfigMapper.config(for: .default)
        #expect(config.autoAdvanceEnabled)
        #expect(config.cellularMaxHeight == nil)
        #expect(config.prefetchAllowedOnCellular)
    }

    @Test func dataSaverCaps480AndStopsPrefetch() {
        let config = PlaybackConfigMapper.config(
            for: PlaybackPreferences(autoplayEnabled: true, dataSaverEnabled: true)
        )
        #expect(config.cellularMaxHeight == 480)
        #expect(config.prefetchAllowedOnCellular == false)
    }

    @Test func autoplayOffDisablesAutoAdvance() {
        let config = PlaybackConfigMapper.config(
            for: PlaybackPreferences(autoplayEnabled: false, dataSaverEnabled: false)
        )
        #expect(config.autoAdvanceEnabled == false)
        // Veri tasarrufu kapalı → tavan yok, autoplay ekseni bağımsız.
        #expect(config.cellularMaxHeight == nil)
    }
}
