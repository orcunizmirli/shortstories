import AppFoundation
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

/// İmzalı URL sağlayıcı testleri (04 §6.4, 05 §8.1): tazelik eşiği (`isUsable`),
/// tek uçuşlu coalesced yenileme ve invalidate akışı — sahte saat + mock authorizer.
struct PlaybackAuthorizationProviderTests {
    private let episodeID = EpisodeID("e1")

    @Test func ilkIstekAuthorizeCagirirVeCachelenir() async throws {
        let clock = ClockBox()
        let service = PlaybackServicingSpy(expiresAt: clock.now.addingTimeInterval(600))
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)

        let first = try await provider.authorization(for: episodeID)
        let second = try await provider.authorization(for: episodeID)

        #expect(service.authorizeCallCount == 1) // taze yetki cache'ten döner
        #expect(first.playbackURL == second.playbackURL)
    }

    @Test func esikGecilinceYenidenAuthorizeEdilir() async throws {
        // 05 §8.1: expiresAt - 60 sn eşiğini geçmiş yetkiyle oynatma BAŞLATILMAZ.
        let clock = ClockBox()
        let service = PlaybackServicingSpy(expiresAt: clock.now.addingTimeInterval(120))
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)
        _ = try await provider.authorization(for: episodeID)

        clock.advance(by: 70) // kalan 50 sn < 60 sn leeway
        service.setExpiry(clock.now.addingTimeInterval(600))
        _ = try await provider.authorization(for: episodeID)

        #expect(service.authorizeCallCount == 2)
    }

    @Test func esGorevlerTekUcuslaBirlestirilir() async throws {
        // Coalesced istek (04 §6.4 kural 2): aynı bölüm için eşzamanlı istekler tek authorize.
        let clock = ClockBox()
        let service = PlaybackServicingSpy(expiresAt: clock.now.addingTimeInterval(600))
        service.setDelay(nanoseconds: 50_000_000)
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)

        try await withThrowingTaskGroup(of: PlaybackAuthorization.self) { group in
            for _ in 0 ..< 5 {
                group.addTask { try await provider.authorization(for: episodeID) }
            }
            for try await _ in group {}
        }

        #expect(service.authorizeCallCount == 1)
    }

    @Test func farkliBolumlerAyriUcuslardir() async throws {
        let clock = ClockBox()
        let service = PlaybackServicingSpy(expiresAt: clock.now.addingTimeInterval(600))
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)

        _ = try await provider.authorization(for: EpisodeID("e1"))
        _ = try await provider.authorization(for: EpisodeID("e2"))

        #expect(service.authorizeCallCount == 2)
    }

    @Test func freshAuthorizationCacheiAtlar() async throws {
        // 410 kurtarması: taze yetki zorunlu — cache'teki hâlâ "usable" görünse bile.
        let clock = ClockBox()
        let service = PlaybackServicingSpy(expiresAt: clock.now.addingTimeInterval(600))
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)
        _ = try await provider.authorization(for: episodeID)

        _ = try await provider.freshAuthorization(for: episodeID)

        #expect(service.authorizeCallCount == 2)
    }

    @Test func invalidateSonrakiIstegiYenidenAuthorizeEttirir() async throws {
        let clock = ClockBox()
        let service = PlaybackServicingSpy(expiresAt: clock.now.addingTimeInterval(600))
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)
        _ = try await provider.authorization(for: episodeID)

        await provider.invalidate(episodeID)
        _ = try await provider.authorization(for: episodeID)

        #expect(service.authorizeCallCount == 2)
    }

    @Test func authorizeHatasiYuzdurulur() async {
        let clock = ClockBox()
        let service = PlaybackServicingSpy()
        service.setFailure(.playback(.signedURLExpired))
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)

        await #expect(throws: AppError.self) {
            _ = try await provider.authorization(for: self.episodeID)
        }
    }

    @Test func hataliUcusCachelenmez() async throws {
        let clock = ClockBox()
        let service = PlaybackServicingSpy(expiresAt: clock.now.addingTimeInterval(600))
        service.setFailure(.network(.offline))
        let provider = PlaybackAuthorizationProvider(service: service, now: clock.nowProvider)
        _ = try? await provider.authorization(for: episodeID)

        service.setFailure(nil)
        let recovered = try await provider.authorization(for: episodeID)

        #expect(recovered.episodeId == episodeID)
    }
}
