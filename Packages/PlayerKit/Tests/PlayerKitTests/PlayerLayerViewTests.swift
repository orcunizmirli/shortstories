import AVFoundation
import Foundation
import Testing
import UIKit
@testable import PlayerKit

/// `PlayerLayerView` bind jenerasyon korkuluğu testleri (bulgu 8): `isReadyForDisplay`
/// KVO→Task köprüsündeki sinyal, planlandığı bind jenerasyonunu taşır — unbind→rebind
/// sonrası bayat Task, yeni episode'un `onFirstFrameReady`'sini ERKEN ateşleyemez.
@MainActor
@Suite("PlayerLayerView — bind jenerasyon korkuluğu")
struct PlayerLayerViewTests {
    @Test("Bayat first-frame sinyali unbind→rebind sonrası yeni episode callback'ini ateşlemez (bulgu 8)")
    func staleSignalDoesNotFireRebindCallback() {
        let view = PlayerLayerView()
        view.onFirstFrameReady = {} // Q'nun (eski episode) callback'i

        view.bind(player: AVPlayer()) // jenerasyon Q
        let staleGeneration = view.bindGeneration

        // Fast scroll: ekran dışı → yeni player'a rebind.
        view.unbind()
        var newEpisodeFirstFrames = 0
        view.onFirstFrameReady = { newEpisodeFirstFrames += 1 }
        view.bind(player: AVPlayer()) // jenerasyon R

        // Q'nun KVO→Task köprüsü şimdi drain olur (bayat sinyal):
        view.signalFirstFrameIfNeeded(generation: staleGeneration)
        #expect(newEpisodeFirstFrames == 0) // yeni episode callback'i ERKEN ateşlenmez

        // R'nin gerçek sinyali fire eder:
        view.signalFirstFrameIfNeeded(generation: view.bindGeneration)
        #expect(newEpisodeFirstFrames == 1)
    }

    @Test("Güncel jenerasyon sinyali first-frame'i bir kez ateşler; ikinci sinyal yutulur")
    func currentSignalFiresOnce() {
        let view = PlayerLayerView()
        var count = 0
        view.onFirstFrameReady = { count += 1 }
        view.bind(player: AVPlayer())

        view.signalFirstFrameIfNeeded(generation: view.bindGeneration)
        view.signalFirstFrameIfNeeded(generation: view.bindGeneration)

        #expect(count == 1) // hasSignaledFirstFrame tek-atış korkuluğu
    }

    @Test("unbind bind jenerasyonunu artırır ve player bağlantısını çözer")
    func unbindBumpsGenerationAndDetaches() {
        let view = PlayerLayerView()
        view.bind(player: AVPlayer())
        #expect(view.isBoundToPlayer)
        let bound = view.bindGeneration

        view.unbind()

        #expect(view.bindGeneration != bound)
        #expect(!view.isBoundToPlayer)
    }
}
