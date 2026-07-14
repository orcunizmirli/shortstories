import AppFoundation
import Testing
@testable import PlayerKit

/// Durum makinesi geçiş testleri (04 §2 durumlar; SS-040 durum makinesi kalemi).
/// Geçersiz geçişler yok sayılır: `nextState` nil döner, state korunur.
struct PlayerStateMachineTests {
    @Test func idleLoadIleLoadingaGecer() {
        #expect(PlayerStateMachine.nextState(from: .idle, on: .loadRequested) == .loading)
    }

    @Test func loadingIlkKareyleReadyeGecer() {
        #expect(PlayerStateMachine.nextState(from: .loading, on: .firstFrameReady) == .readyAtFirstFrame)
    }

    @Test func readydenPlayIlePlayingaGecer() {
        #expect(PlayerStateMachine.nextState(from: .readyAtFirstFrame, on: .playRequested) == .playing)
    }

    @Test func playingPauseIlePausedaGecer() {
        #expect(PlayerStateMachine.nextState(from: .playing, on: .pauseRequested) == .paused)
    }

    @Test func pausedPlayIlePlayingaDoner() {
        #expect(PlayerStateMachine.nextState(from: .paused, on: .playRequested) == .playing)
    }

    @Test func playingStallIleStalledaGecer() {
        #expect(PlayerStateMachine.nextState(from: .playing, on: .stallBegan) == .stalled)
    }

    @Test func stalledStallBitincePlayingaDoner() {
        #expect(PlayerStateMachine.nextState(from: .stalled, on: .stallEnded) == .playing)
    }

    @Test func stalledPauseEdilebilir() {
        #expect(PlayerStateMachine.nextState(from: .stalled, on: .pauseRequested) == .paused)
    }

    @Test func herDurumdanFailedaGecilebilir() {
        let error = AppError.playback(.assetUnavailable)
        for state: PlayerEngineState in [.idle, .loading, .readyAtFirstFrame, .playing, .paused, .stalled] {
            #expect(PlayerStateMachine.nextState(from: state, on: .didFail(error)) == .failed(error))
        }
    }

    @Test func failedYenidenLoadEdilebilir() {
        let failed = PlayerEngineState.failed(.playback(.signedURLExpired))
        #expect(PlayerStateMachine.nextState(from: failed, on: .loadRequested) == .loading)
    }

    @Test func resetHerDurumuIdleaDondurur() {
        let error = AppError.playback(.assetUnavailable)
        for state: PlayerEngineState in [.loading, .readyAtFirstFrame, .playing, .paused, .stalled, .failed(error)] {
            #expect(PlayerStateMachine.nextState(from: state, on: .resetRequested) == .idle)
        }
    }

    @Test func kurtarmaBaslayincaLoadingaDonulur() {
        // İmzalı URL kurtarması (04 §6.4): kullanıcı failed görmez, spinner (loading) görür.
        #expect(PlayerStateMachine.nextState(from: .playing, on: .recoveryStarted) == .loading)
        #expect(PlayerStateMachine.nextState(from: .stalled, on: .recoveryStarted) == .loading)
        #expect(PlayerStateMachine.nextState(from: .loading, on: .recoveryStarted) == .loading)
    }

    // MARK: - Geçersiz geçişler

    @Test func idledenPlayGecersizdir() {
        #expect(PlayerStateMachine.nextState(from: .idle, on: .playRequested) == nil)
    }

    @Test func loadingdenPlayGecersizdir() {
        // Oynatma niyeti engine'de kuyruklanır (pendingPlay); reducer geçişi reddeder.
        #expect(PlayerStateMachine.nextState(from: .loading, on: .playRequested) == nil)
    }

    @Test func pausedIkenStallGecersizdir() {
        #expect(PlayerStateMachine.nextState(from: .paused, on: .stallBegan) == nil)
    }

    @Test func playingIkenLoadGecersizdir() {
        // Yeni bölüm için önce reset gerekir (PlaybackEngine.prepare bunu yapar).
        #expect(PlayerStateMachine.nextState(from: .playing, on: .loadRequested) == nil)
    }

    @Test func handleGecersizGecisteStateKorur() {
        var machine = PlayerStateMachine()
        let changed = machine.handle(.playRequested)
        #expect(!changed)
        #expect(machine.state == .idle)
    }

    @Test func handleGecerliGecisteStateIlerletir() {
        var machine = PlayerStateMachine()
        let loadChanged = machine.handle(.loadRequested)
        let frameChanged = machine.handle(.firstFrameReady)
        let playChanged = machine.handle(.playRequested)
        #expect(loadChanged && frameChanged && playChanged)
        #expect(machine.state == .playing)
    }
}
