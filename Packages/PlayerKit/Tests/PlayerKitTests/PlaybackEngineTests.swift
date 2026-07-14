import AppFoundation
import Foundation
import Testing
@testable import PlayerKit

/// PlaybackEngine davranış testleri: sahte backend ile durum akışı, playImmediately
/// semantiği (04 §4.2) ve resume pozisyonu (04 §12.2). AVFoundation'a dokunmaz.
struct PlaybackEngineTests {
    private let url = URL(string: "https://cdn.test/e1/master.m3u8")!
    private let episodeID = EpisodeID("e1")

    private func makeEngine(
        freshURLProvider: (@Sendable (EpisodeID) async throws -> URL)? = nil
    ) -> (PlaybackEngine, FakeVideoPlaying) {
        let backend = FakeVideoPlaying()
        let engine = PlaybackEngine(backend: backend, freshURLProvider: freshURLProvider)
        return (engine, backend)
    }

    @Test func prepareLoadingDurumunaGecerVeBackendeYukler() async {
        let (engine, backend) = makeEngine()

        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)

        #expect(await engine.currentState() == .loading)
        #expect(backend.calls.contains(.load(url, .active)))
    }

    @Test func ilkKareGelinceReadyeGecer() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)

        backend.emit(.firstFrameReady)

        #expect(await awaitState(.readyAtFirstFrame, on: engine))
    }

    @Test func readyIkenPlayPlayImmediatelyCagirir() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)

        await engine.play()

        #expect(await awaitState(.playing, on: engine))
        #expect(backend.calls.contains(.playImmediately(1.0)))
    }

    @Test func loadingIkenPlayNiyetiKuyruklanirIlkKaredeOynar() async {
        // Swipe anında henüz yüklenmemiş bölüm: play niyeti düşmez, ilk karede uygulanır.
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)

        await engine.play()
        #expect(await engine.currentState() == .loading)
        #expect(!backend.calls.contains(.playImmediately(1.0)))

        backend.emit(.firstFrameReady)

        #expect(await awaitState(.playing, on: engine))
        #expect(backend.calls.contains(.playImmediately(1.0)))
    }

    @Test func pausePlayingdenPausedaGecirir() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        await engine.play()
        _ = await awaitState(.playing, on: engine)

        await engine.pause()

        #expect(await engine.currentState() == .paused)
        #expect(backend.calls.contains(.pause))
    }

    @Test func stallBaslayipBitinceDurumlarIzlenir() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        await engine.play()
        _ = await awaitState(.playing, on: engine)

        backend.emit(.stallBegan)
        #expect(await awaitState(.stalled, on: engine))

        backend.emit(.stallEnded)
        #expect(await awaitState(.playing, on: engine))
    }

    @Test func resumePozisyonuIlkKaredenSonraSeekEdilir() async {
        // Devam Et (04 §12.2): item hazırlanırken seek, kullanıcı sıçrama görmez.
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active, resumePosition: 33)
        await engine.play()

        backend.emit(.firstFrameReady)
        _ = await awaitState(.playing, on: engine)

        let calls = backend.calls
        let seekIndex = calls.firstIndex(of: .seek(33))
        let playIndex = calls.firstIndex(of: .playImmediately(1.0))
        #expect(seekIndex != nil)
        #expect(playIndex != nil)
        if let seekIndex, let playIndex {
            #expect(seekIndex < playIndex) // önce konum, sonra oynatma
        }
    }

    @Test func toleransliVeKeskinSeekAyriYollardir() async {
        // 04 §8.1 / 01 PLR-02: çift tap TOLERANT seek; resume/scrubber bırakışı keskin (.zero).
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)

        await engine.seek(toSeconds: 10) // keskin
        await engine.seekTolerant(toSeconds: 20) // toleranslı

        #expect(backend.calls.contains(.seek(10)))
        #expect(backend.calls.contains(.seekTolerant(20)))
        #expect(!backend.calls.contains(.seekTolerant(10)))
        #expect(!backend.calls.contains(.seek(20)))
    }

    @Test func setRateOynarkenBackendeUygulanir() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        await engine.play()
        _ = await awaitState(.playing, on: engine)

        await engine.setRate(2.0)

        #expect(backend.calls.contains(.setRate(2.0)))
    }

    @Test func resetItemBirakirIdleaDoner() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)

        await engine.reset()

        #expect(await engine.currentState() == .idle)
        #expect(backend.calls.contains(.clearItem))
    }

    @Test func bolumSonundaPausedaGecer() async {
        // actionAtItemEnd = .pause (04 §3.3): auto-next feed katmanının işidir.
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        await engine.play()
        _ = await awaitState(.playing, on: engine)

        backend.emit(.playedToEnd)

        #expect(await awaitState(.paused, on: engine))
    }

    @Test func gecAboneOlanGozlemciBitisOlayiniLatchIleAlir() async {
        // Kök neden regresyonu: watchPlayedToEnd gözlemcisi settle döndükten SONRA
        // tembel abone olur; playedToEnd gözlemci abone OLMADAN yayılırsa (yüksek yükte
        // CI yarışı) olay kaybolurdu. Latch, geç aboneye bir kez teslim eder.
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        await engine.play()
        _ = await awaitState(.playing, on: engine)

        // ÖNCE bitiş yayılır, SONRA abone olunur (yarışın kaybeden tarafı).
        backend.emit(.playedToEnd)
        _ = await awaitState(.paused, on: engine)

        let received = await eventually {
            var iterator = await engine.playedToEndEvents().makeAsyncIterator()
            return await iterator.next() != nil
        }
        #expect(received)
    }

    @Test func yeniHazirlamaBitisLatchiniSifirlar() async {
        // Bayat bitiş yanlış auto-next tetiklemez (T4): prepare latch'i sıfırlar.
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        backend.emit(.playedToEnd)
        _ = await awaitState(.paused, on: engine)

        await engine.prepare(episodeID: EpisodeID("e2"), url: url, bufferPolicy: .active)

        // Yeni yüklemede latch temiz: hemen bir bitiş olayı DÜŞMEZ.
        let spuriousEnd = await withTimeoutReturningTrueIfEventArrives(engine: engine, seconds: 0.2)
        #expect(spuriousEnd == false)
    }

    private func withTimeoutReturningTrueIfEventArrives(
        engine: PlaybackEngine,
        seconds: Double
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = await engine.playedToEndEvents().makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    @Test func kurtarilamazHataFailedaDusurur() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)

        backend.emit(.didFail(.playback(.drmDenied)))

        #expect(await awaitState(.failed(.playback(.drmDenied)), on: engine))
    }

    @Test func statusUpdatesSonDurumuReplayEder() async {
        let (engine, backend) = makeEngine()
        await engine.prepare(episodeID: episodeID, url: url, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)

        var first: PlayerEngineState?
        for await state in await engine.statusUpdates() {
            first = state
            break
        }

        #expect(first == .readyAtFirstFrame)
    }
}
