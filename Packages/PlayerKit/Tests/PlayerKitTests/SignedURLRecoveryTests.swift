import AppFoundation
import Foundation
import Testing
@testable import PlayerKit

/// İmzalı URL kurtarma politikası + akışı (04 §6.4, SS-051 çekirdek yarısı):
/// oynatma sırasında süre dolarsa konum kaydedilir → taze URL → yeni yükleme →
/// seek → playImmediately. Kullanıcı failed görmez; 2. hata yüzeye çıkar.
struct SignedURLRecoveryPolicyTests {
    @Test func ilkSignedURLExpiredYenilemeIleKurtarilir() {
        let action = SignedURLRecoveryPolicy.action(for: .playback(.signedURLExpired), attempt: 0)
        #expect(action == .refreshAndResume)
    }

    @Test func ikinciDenemedeHataYuzeyeCikar() {
        let action = SignedURLRecoveryPolicy.action(for: .playback(.signedURLExpired), attempt: 1)
        #expect(action == .surface)
    }

    @Test func geciciCDNHatasiDaAyniYoldanKurtarilir() {
        // 04 §6.4 kural 5: CDN kaynaklı geçici hata (asset failed) 1 otomatik deneme alır.
        let action = SignedURLRecoveryPolicy.action(for: .playback(.assetUnavailable), attempt: 0)
        #expect(action == .refreshAndResume)
    }

    @Test func drmHatasiKurtarilmaz() {
        let action = SignedURLRecoveryPolicy.action(for: .playback(.drmDenied), attempt: 0)
        #expect(action == .surface)
    }

    @Test func agHatasiKurtarmaAkisininDisindadir() {
        let action = SignedURLRecoveryPolicy.action(for: .network(.offline), attempt: 0)
        #expect(action == .surface)
    }
}

struct SignedURLRecoveryFlowTests {
    private let url1 = URL(string: "https://cdn.test/e1/v1/master.m3u8")!
    private let url2 = URL(string: "https://cdn.test/e1/v2/master.m3u8")!
    private let episodeID = EpisodeID("e1")

    private final class URLProviderSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var served: [URL]
        private(set) var requestedIDs: [EpisodeID] = []

        init(serving urls: [URL]) {
            served = urls
        }

        var callCount: Int {
            lock.withLock { requestedIDs.count }
        }

        func provide(_ episodeID: EpisodeID) throws -> URL {
            try lock.withLock {
                requestedIDs.append(episodeID)
                guard !served.isEmpty else { throw AppError.playback(.signedURLExpired) }
                return served.removeFirst()
            }
        }
    }

    private func playingEngine(
        provider: URLProviderSpy
    ) async -> (PlaybackEngine, FakeVideoPlaying) {
        let backend = FakeVideoPlaying()
        let engine = PlaybackEngine(
            backend: backend,
            freshURLProvider: { episodeID in try provider.provide(episodeID) }
        )
        await engine.prepare(episodeID: episodeID, url: url1, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)
        await engine.play()
        _ = await awaitState(.playing, on: engine)
        return (engine, backend)
    }

    @Test func sureDolanURLdeKaldigiKaredenDevamEder() async {
        let provider = URLProviderSpy(serving: [url2])
        let (engine, backend) = await playingEngine(provider: provider)
        backend.setPosition(42)

        backend.emit(.didFail(.playback(.signedURLExpired)))

        // Kurtarma: taze URL istendi, yeni yükleme yapıldı; kullanıcı spinner (loading) görür.
        #expect(await eventually { backend.calls.contains(.load(url2, .active)) })
        #expect(provider.requestedIDs == [episodeID])

        backend.emit(.firstFrameReady)
        #expect(await awaitState(.playing, on: engine))

        let calls = backend.calls
        let seekIndex = calls.lastIndex(of: .seek(42))
        let playIndex = calls.lastIndex(of: .playImmediately(1.0))
        #expect(seekIndex != nil)
        if let seekIndex, let playIndex {
            #expect(seekIndex < playIndex) // kaldığı kareye seek, sonra playImmediately
        }
    }

    @Test func kurtarmaSirasindaFailedGorulmez() async {
        let provider = URLProviderSpy(serving: [url2])
        let (engine, backend) = await playingEngine(provider: provider)

        backend.emit(.didFail(.playback(.signedURLExpired)))
        _ = await eventually { backend.calls.contains(.load(url2, .active)) }

        let state = await engine.currentState()
        #expect(state == .loading) // spinner; failed değil
    }

    @Test func ikinciArdisikHataYuzeyeCikar() async {
        let provider = URLProviderSpy(serving: [url2, url2])
        let (engine, backend) = await playingEngine(provider: provider)

        backend.emit(.didFail(.playback(.signedURLExpired)))
        _ = await eventually { backend.calls.contains(.load(url2, .active)) }
        backend.emit(.firstFrameReady)
        _ = await awaitState(.playing, on: engine)

        backend.emit(.didFail(.playback(.signedURLExpired)))

        #expect(await awaitState(.failed(.playback(.signedURLExpired)), on: engine))
        #expect(provider.callCount == 1) // ikinci otomatik deneme YOK
    }

    @Test func tazeURLAlinamazsaFailedaDusulur() async {
        let provider = URLProviderSpy(serving: [])
        let (engine, backend) = await playingEngine(provider: provider)

        backend.emit(.didFail(.playback(.signedURLExpired)))

        #expect(await awaitState(.failed(.playback(.signedURLExpired)), on: engine))
    }

    @Test func yeniPrepareKurtarmaHakkiniSifirlar() async {
        let provider = URLProviderSpy(serving: [url2, url2])
        let (engine, backend) = await playingEngine(provider: provider)

        backend.emit(.didFail(.playback(.signedURLExpired)))
        _ = await eventually { backend.calls.contains(.load(url2, .active)) }

        // Yeni bölüm hazırlanınca kurtarma sayacı sıfırlanır; hata yine kurtarılabilir.
        await engine.prepare(episodeID: episodeID, url: url1, bufferPolicy: .active)
        backend.emit(.firstFrameReady)
        _ = await awaitState(.readyAtFirstFrame, on: engine)

        backend.emit(.didFail(.playback(.signedURLExpired)))

        #expect(await eventually { provider.callCount == 2 })
    }
}
