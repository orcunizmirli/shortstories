import AppFoundation
import AppFoundationTestSupport
import Foundation
import Testing
@testable import ContentKit

/// PlaybackAPI davranış testleri — imzalı URL authorize sözleşmesi (05 §4.4, §8.1).
struct PlaybackAPITests {
    private let mock = MockAPIClient()
    private var api: PlaybackAPI {
        PlaybackAPI(client: mock)
    }

    @Test func authorizeEpisodeIdGovdesiyleGonderilir() async throws {
        try mock.stub("/playback/authorize", with: .success(Fixtures.data("playback_authorize")))

        let auth = try await api.authorize(episodeId: EpisodeID("ep_5410be"))

        #expect(auth.episodeId == EpisodeID("ep_5410be"))
        #expect(auth.playbackURL.absoluteString
            == "https://cdn.shortseries.app/hls/ep_5410be/master.m3u8?tk=eyJ...&exp=1783190400")
        #expect(auth.drm == nil)

        let endpoint = try #require(mock.receivedEndpoints.first as? PlaybackAuthorizeEndpoint)
        #expect(endpoint.method == .post)
        let body = try #require(endpoint.body as? PlaybackAuthorizeEndpoint.RequestBody)
        #expect(body.episodeId == "ep_5410be")
    }

    @Test func fairplayYanitiDrmBlogunuTasir() async throws {
        try mock.stub("/playback/authorize", with: .success(Fixtures.data("playback_authorize_fairplay")))

        let auth = try await api.authorize(episodeId: EpisodeID("ep_5410be"))

        let drm = try #require(auth.drm)
        #expect(drm.scheme == .fairplay)
        #expect(drm.licenseURL.absoluteString == "https://drm.shortseries.app/fps/license")
    }

    /// 05 §8.1 yenileme kuralı: `expiresAt - 60 sn` eşiğini geçmiş yetkiyle oynatma/prefetch
    /// BAŞLATILMAZ; SS-022 player tarafı bu yardımcıyla aynı authorize ucundan tazeler.
    @Test func yenilemeEsigiGecmisYetkiKullanilmaz() async throws {
        try mock.stub("/playback/authorize", with: .success(Fixtures.data("playback_authorize")))
        let auth = try await api.authorize(episodeId: EpisodeID("ep_5410be"))
        // expiresAt: 2026-07-11T12:00:00Z

        #expect(auth.isUsable(at: isoDate("2026-07-11T11:58:59Z")))
        #expect(!auth.isUsable(at: isoDate("2026-07-11T11:59:00Z"))) // eşik: expiresAt - 60 sn
        #expect(!auth.isUsable(at: isoDate("2026-07-11T12:00:01Z")))
    }

    /// Oynatma yetkisi kritik yoldur ama otomatik retry almaz (03 §8.3; kurtarma
    /// akışı 05 §8.1'de player tarafındadır).
    @Test func authorizeEndpointiOtomatikRetryAlmaz() {
        let endpoint = PlaybackAuthorizeEndpoint(episodeId: EpisodeID("ep_x"))

        #expect(endpoint.retryPolicy == .never)
        #expect(endpoint.path == "/playback/authorize")
        #expect(endpoint.cachePolicy == .networkOnly) // yanıt no-store'dur (05 §7.2)
    }

    @Test func kilitliBolumHatasiYuzeyeCikar() async throws {
        // 403 EPISODE_LOCKED → AppError tipli case eşlemesi AppFoundation'dadır (05 §10.3);
        // ContentKit eşleme yapmaz, tipli hatayı aynen yüzdürür.
        mock.stub("/playback/authorize", throwing: .content(.episodeLockedStateStale))

        await #expect(throws: AppError.content(.episodeLockedStateStale)) {
            _ = try await api.authorize(episodeId: EpisodeID("ep_kilitli"))
        }
    }

    /// 410 SIGNED_URL_EXPIRED → `.playback(.signedURLExpired)` eşlemesi de
    /// AppFoundation'dadır; ContentKit tipli hatayı aynen yüzdürür (05 §8.1, §10.3).
    @Test func suresiDolmusImzaliUrlHatasiYuzeyeCikar() async throws {
        mock.stub("/playback/authorize", throwing: .playback(.signedURLExpired))

        await #expect(throws: AppError.playback(.signedURLExpired)) {
            _ = try await api.authorize(episodeId: EpisodeID("ep_suresi_dolmus"))
        }
    }
}
