import AppFoundation
import AVFoundation
import ContentKit
import Foundation
import Testing
import UIKit
@testable import PlayerKit

// MARK: - Görüntü yüzeyi taşıyan sahte backend

/// `AVPlayerSurfaceSource` uygulayan minimal backend: `PlayerCell.bind` yalnız
/// `surfacePlayer`'ı ister (oynatma sürülmez). Gerçek medya olmadan hücre yaşam
/// döngüsü (bind/unbind/reveal/reconfigure) deterministik zorlanır.
final class SurfacePlayerBackend: VideoPlaying, AVPlayerSurfaceSource, @unchecked Sendable {
    nonisolated let runtimeEvents: AsyncStream<TaggedRuntimeEvent>
    private let continuation: AsyncStream<TaggedRuntimeEvent>.Continuation
    private let player = AVPlayer()

    init() {
        (runtimeEvents, continuation) = AsyncStream.makeStream()
    }

    @MainActor var surfacePlayer: AVPlayer? {
        player
    }

    func load(url _: URL, bufferPolicy _: BufferPolicy, generation _: UInt64) async {}
    func playImmediately(atRate _: Double) async {}
    func pause() async {}
    func seek(toSeconds _: Double, tolerant _: Bool) async {}
    func setRate(_: Double) async {}
    func setMuted(_: Bool) async {}
    func setPitchPreservation(_: Bool) async {}
    func applyBufferPolicy(_: BufferPolicy) async {}
    func setPeakBitRateCap(_: Double?) async {}
    func currentPositionSeconds() async -> Double {
        0
    }

    func clearItem() async {}
}

@MainActor
private func makeSurfaceHandle(episodeID: String) -> PlaybackHandle {
    PlaybackHandle(episodeID: EpisodeID(episodeID), engine: PlaybackEngine(backend: SurfacePlayerBackend()))
}

// MARK: - Hücre yaşam döngüsü (bulgu 1/3/5/7)

@MainActor
@Suite("PlayerCell — yaşam döngüsü kenar durumları")
struct PlayerCellLifecycleTests {
    @Test("Aktif oynayan hücrenin yerinde reconfigure'ü canlı videoyu posterle GÖMMEZ (bulgu 1/5)")
    func reconfigurePreservesRevealedVideo() {
        let cell = PlayerCell(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let episode = Fixture.episode(id: "e0", index: 1)
        cell.configure(with: Fixture.feedItem(episode: episode))
        cell.bind(handle: makeSurfaceHandle(episodeID: "e0"))

        // İlk kare geldi → poster videoya geçti (gizlendi).
        cell.revealVideoSurface()
        cell.finishRevealIfCurrent(generation: cell.revealGeneration, finished: true)
        #expect(cell.posterIsHidden)
        #expect(cell.boundEpisodeID == EpisodeID("e0"))

        // AYNI bölüm içerik güncellemesiyle yerinde reconfigure (ör. progress/favorite):
        cell.configure(with: Fixture.feedItem(
            episode: episode,
            progress: Fixture.progress(for: episode, positionSec: 20)
        ))

        // Canlı video korunur: poster GİZLİ kalır, bağlama düşmez.
        #expect(cell.posterIsHidden)
        #expect(cell.boundEpisodeID == EpisodeID("e0"))
    }

    @Test("Farklı bölüm reconfigure'ünde poster geri gösterilir, bağlama düşer")
    func reconfigureDifferentEpisodeResetsPoster() {
        let cell = PlayerCell(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        let e0 = Fixture.episode(id: "e0", index: 1)
        cell.configure(with: Fixture.feedItem(episode: e0))
        cell.bind(handle: makeSurfaceHandle(episodeID: "e0"))
        cell.revealVideoSurface()
        cell.finishRevealIfCurrent(generation: cell.revealGeneration, finished: true)
        #expect(cell.posterIsHidden)

        // Aynı feed slot'una FARKLI bölüm geldi (nadir ama olası server değişimi):
        cell.configure(with: Fixture.feedItem(episode: Fixture.episode(id: "e1", index: 2)))

        #expect(!cell.posterIsHidden) // yeni bölüm posteri gösterilir
        #expect(cell.boundEpisodeID == nil)
    }

    @Test("Reuse sırasındaki BAYAT reveal completion'ı yeni item'ın posterini gizlemez (bulgu 3/7)")
    func staleRevealCompletionDoesNotHideRecycledPoster() {
        let cell = PlayerCell(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        cell.configure(with: Fixture.feedItem(episode: Fixture.episode(id: "e0", index: 1)))

        // A'nın ilk karesi reveal'i başlattı (0.15 sn animasyon uçuşta):
        cell.revealVideoSurface()
        let staleGeneration = cell.revealGeneration

        // 150 ms dolmadan hücre B için geri dönüştürülür:
        cell.prepareForReuse()
        cell.configure(with: Fixture.feedItem(episode: Fixture.episode(id: "e9", index: 9)))
        #expect(!cell.posterIsHidden) // B posteri görünür

        // A'nın uçuştaki animasyonunun BAYAT completion'ı şimdi ateşlenir:
        cell.finishRevealIfCurrent(generation: staleGeneration, finished: true)

        // B'nin posteri gizlenMEZ (siyah kare yok).
        #expect(!cell.posterIsHidden)
    }

    @Test("prepareForReuse uçuştaki reveal'i geçersizler (reveal jenerasyonu artar)")
    func prepareForReuseInvalidatesReveal() {
        let cell = PlayerCell(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        cell.configure(with: Fixture.feedItem(episode: Fixture.episode(id: "e0", index: 1)))
        cell.revealVideoSurface()
        let before = cell.revealGeneration

        cell.prepareForReuse()

        #expect(cell.revealGeneration != before)
        #expect(!cell.posterIsHidden)
    }

    @Test("İptal edilmemiş güncel reveal completion'ı posteri gizler (poziti kontrol)")
    func currentRevealCompletionHidesPoster() {
        let cell = PlayerCell(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        cell.configure(with: Fixture.feedItem(episode: Fixture.episode(id: "e0", index: 1)))
        cell.revealVideoSurface()

        cell.finishRevealIfCurrent(generation: cell.revealGeneration, finished: true)
        #expect(cell.posterIsHidden)
    }

    @Test("Yarıda kesilen (finished=false) reveal completion'ı posteri gizlemez")
    func interruptedRevealDoesNotHidePoster() {
        let cell = PlayerCell(frame: CGRect(x: 0, y: 0, width: 100, height: 200))
        cell.configure(with: Fixture.feedItem(episode: Fixture.episode(id: "e0", index: 1)))
        cell.revealVideoSurface()

        cell.finishRevealIfCurrent(generation: cell.revealGeneration, finished: false)
        #expect(!cell.posterIsHidden)
    }
}
