import AppFoundation
import ContentKit
import Foundation
import LibraryKit
import ProfileKit
import WalletKit
import XCTest
@testable import ShortSeriesApp

/// Port adaptörlerinin SAF (yan etkisiz) dönüşüm mantığının izole testleri (App/DI). Ağ/graf
/// KURULMADAN yalnız değer→değer eşlemeleri doğrulanır; canlı graf doğrulaması derleme (Faz 3) +
/// entegrasyondadır. Bu hedef CI'da koşmaz (App target CI dışı) — Xcode/lokal doğrulama içindir.
final class AdapterTransformTests: XCTestCase {
    // MARK: - WalletSummary eşlemesi

    func testWalletSummaryMapsTotalCoinsAndVIP() {
        let summary = WalletGatewaySummaryReading.summary(
            balance: CoinBalance(purchasedCoins: 30, earnedCoins: 12),
            subscription: vip(expiresAt: Date(timeIntervalSince1970: 1000))
        )
        XCTAssertEqual(summary.coinBalance, 42)
        XCTAssertTrue(summary.isVIP)
        XCTAssertEqual(summary.vipRenewalDate, Date(timeIntervalSince1970: 1000))
    }

    func testWalletSummaryDropsRenewalWhenNotVIP() {
        // VIP değilken yenileme tarihi TAŞINMAZ (satır "VIP'e geç" tanıtımına düşer).
        let summary = WalletGatewaySummaryReading.summary(
            balance: CoinBalance(purchasedCoins: 0, earnedCoins: 0),
            subscription: .none
        )
        XCTAssertEqual(summary.coinBalance, 0)
        XCTAssertFalse(summary.isVIP)
        XCTAssertNil(summary.vipRenewalDate)
    }

    // MARK: - Listem katalog JOIN eşlemesi

    func testSeriesInfoMapping() {
        let info = CatalogLibraryReading.info(from: sampleSeries)
        XCTAssertEqual(info.id, SeriesID("s1"))
        XCTAssertEqual(info.title, "Test Dizi")
        XCTAssertEqual(info.coverURL, URL(string: "https://cdn.example.com/s1.jpg"))
        XCTAssertTrue(info.isAvailable)
    }

    // MARK: - Hesap bağlama istek gövdesi (sağlayıcı-bağımsız, POST /auth/link)

    func testLinkRequestBodyApple() {
        // Apple: provider "apple" + identityToken kalıbı; verificationToken TAŞINMAZ.
        let body = AuthLinkRequestBody.make(from: .apple(AppleCredential(
            identityToken: "apple.jwt",
            authorizationCode: "auth_a",
            userIdentifier: "apple_user",
            email: "a@x.com",
            fullName: "A B"
        )))
        XCTAssertEqual(body.provider, "apple")
        XCTAssertEqual(body.identityToken, "apple.jwt")
        XCTAssertNil(body.verificationToken)
        XCTAssertEqual(body.authorizationCode, "auth_a")
        XCTAssertEqual(body.userIdentifier, "apple_user")
        XCTAssertEqual(body.email, "a@x.com")
        XCTAssertEqual(body.fullName, "A B")
    }

    func testLinkRequestBodyGoogle() {
        // Google: provider "google" + identityToken (idToken); Apple-özel alanlar (userIdentifier/fullName) nil.
        let body = AuthLinkRequestBody.make(from: .google(GoogleCredential(
            idToken: "google.idtoken",
            authorizationCode: "auth_g",
            email: "g@x.com"
        )))
        XCTAssertEqual(body.provider, "google")
        XCTAssertEqual(body.identityToken, "google.idtoken")
        XCTAssertNil(body.verificationToken)
        XCTAssertEqual(body.authorizationCode, "auth_g")
        XCTAssertNil(body.userIdentifier)
        XCTAssertEqual(body.email, "g@x.com")
        XCTAssertNil(body.fullName)
    }

    func testLinkRequestBodyEmailUsesVerificationTokenNotIdentityToken() {
        // E-posta identityToken kalıbına UYMAZ (05 §4.2.1): opak verificationToken; identityToken nil.
        let body = AuthLinkRequestBody.make(from: .email(EmailCredential(
            email: "u@x.com",
            verificationToken: "opaque.verify.token"
        )))
        XCTAssertEqual(body.provider, "email")
        XCTAssertNil(body.identityToken)
        XCTAssertEqual(body.verificationToken, "opaque.verify.token")
        XCTAssertNil(body.authorizationCode)
        XCTAssertNil(body.userIdentifier)
        XCTAssertEqual(body.email, "u@x.com")
        XCTAssertNil(body.fullName)
    }

    func testLinkRequestBodyProviderMatchesCredentialProvider() {
        // provider alanı tek kaynaktan (credential.provider.rawValue) türer.
        let apple = LinkCredential.apple(AppleCredential(identityToken: "t", userIdentifier: "u"))
        let google = LinkCredential.google(GoogleCredential(idToken: "t"))
        let email = LinkCredential.email(EmailCredential(email: "e@x.com", verificationToken: "t"))
        XCTAssertEqual(AuthLinkRequestBody.make(from: apple).provider, AuthProvider.apple.rawValue)
        XCTAssertEqual(AuthLinkRequestBody.make(from: google).provider, AuthProvider.google.rawValue)
        XCTAssertEqual(AuthLinkRequestBody.make(from: email).provider, AuthProvider.email.rawValue)
    }

    // MARK: - Hesap bağlama conflict eşlemesi

    func testLinkConflictMapping() {
        let conflict = APIAccountLinkingService.linkConflict(
            from: AuthLinkWire.ConflictWire(
                existingAccountMasked: "a•••@x.com",
                switchToken: "tok_123",
                willDiscardGuestData: true
            )
        )
        XCTAssertEqual(conflict.existingAccountMasked, "a•••@x.com")
        XCTAssertEqual(conflict.switchToken, "tok_123")
        XCTAssertTrue(conflict.willDiscardGuestData)
    }

    // MARK: - İzleme ilerlemesi eşlemeleri

    func testWatchProgressRecordToDomain() {
        let record = WatchProgressRecord(
            episodeID: EpisodeID("e7"),
            seriesID: SeriesID("s1"),
            positionSec: 42,
            durationSec: 100,
            completed: false,
            watchedAt: Date(timeIntervalSince1970: 2000)
        )
        let progress = ContinueWatchingHistoryReading.watchProgress(from: record)
        XCTAssertEqual(progress.episodeId, EpisodeID("e7"))
        XCTAssertEqual(progress.seriesId, SeriesID("s1"))
        XCTAssertEqual(progress.positionSec, 42)
        XCTAssertEqual(progress.durationSec, 100)
        XCTAssertFalse(progress.completed)
        XCTAssertEqual(progress.watchedAt, Date(timeIntervalSince1970: 2000))
    }

    func testWatchProgressWireRoundTrip() {
        let record = WatchProgressRecord(
            episodeID: EpisodeID("e1"),
            seriesID: SeriesID("s2"),
            positionSec: 15.5,
            durationSec: 90,
            completed: true,
            watchedAt: Date(timeIntervalSince1970: 3000)
        )
        let restored = WatchProgressWire(record: record).record
        XCTAssertEqual(restored, record)
    }

    // MARK: - Analitik registry doğrulaması

    func testRegistryValidatesKnownEvent() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("checkin_claim"), .valid)
        XCTAssertEqual(AnalyticsEventRegistry.validate("screen_view"), .valid)
    }

    func testRegistryFlagsUnregisteredButWellFormed() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("totally_new_event"), .unregistered)
    }

    func testRegistryFlagsMalformed() {
        XCTAssertEqual(AnalyticsEventRegistry.validate("CheckIn"), .malformed)
        XCTAssertEqual(AnalyticsEventRegistry.validate("checkin_"), .malformed)
        XCTAssertEqual(AnalyticsEventRegistry.validate(""), .malformed)
        XCTAssertEqual(AnalyticsEventRegistry.validate("2fast"), .malformed)
    }

    func testAnalyticsParameterDescriptionIsDeterministic() {
        let description = AppAnalyticsTracker.describe([
            "b_key": .int(2),
            "a_key": .string("x"),
            "c_flag": .bool(true)
        ])
        // Anahtarlar sıralı (deterministik gözlem).
        XCTAssertEqual(description, "{a_key=x, b_key=2, c_flag=true}")
    }

    // MARK: - Rewards wire → domain eşlemeleri

    func testMissionWireMapsUnknownKindAndState() {
        let wire = MissionWire(
            id: "m1",
            kind: "watchMinutes",
            title: "10 dakika izle",
            rewardCoins: 20,
            target: 10,
            progress: 4,
            state: "inProgress",
            resetPolicy: "daily",
            expiresAt: nil
        )
        let task = wire.task
        XCTAssertEqual(task.id, "m1")
        XCTAssertEqual(task.kind, .watchMinutes)
        XCTAssertEqual(task.state, .inProgress)
        XCTAssertEqual(task.resetPolicy, .daily)

        let unknown = MissionWire(
            id: "m2",
            kind: "teleportToMars",
            title: "?",
            rewardCoins: 0,
            target: 1,
            progress: 0,
            state: "quantum",
            resetPolicy: "eon",
            expiresAt: nil
        ).task
        XCTAssertEqual(unknown.kind, .unknown("teleportToMars"))
        XCTAssertEqual(unknown.state, .unknown)
        XCTAssertEqual(unknown.resetPolicy, .unknown)
    }

    func testCheckInStateWireMapping() {
        let wire = CheckInStateWire(
            cycleDay: 3,
            todayClaimed: false,
            todayReward: 20,
            schedule: [CheckInStateWire.DayRewardWire(day: 1, coins: 10, claimed: true)],
            streakDays: 3,
            streakBonusAt: 7,
            streakBonusCoins: 100
        )
        let state = wire.state
        XCTAssertEqual(state.cycleDay, 3)
        XCTAssertFalse(state.todayClaimed)
        XCTAssertEqual(state.todayReward, 20)
        XCTAssertEqual(state.schedule.count, 1)
        XCTAssertEqual(state.schedule.first?.coins, 10)
        XCTAssertEqual(state.streakBonusAt, 7)
        XCTAssertEqual(state.streakBonusCoins, 100)
    }

    // MARK: - Fixtures

    private func vip(expiresAt: Date) -> SubscriptionStatus {
        SubscriptionStatus(
            isVIP: true,
            plan: .monthly,
            expiresAt: expiresAt,
            willAutoRenew: true,
            isInGracePeriod: false,
            isInIntroOffer: false,
            dailyBonusCoins: 0,
            dailyBonusClaimedToday: false
        )
    }

    private var sampleSeries: Series {
        Series(
            id: SeriesID("s1"),
            title: "Test Dizi",
            synopsis: "…",
            coverURL: URL(string: "https://cdn.example.com/s1.jpg")!,
            bannerURL: nil,
            genres: [],
            tags: [],
            episodeCount: 10,
            releasedEpisodeCount: 10,
            freeEpisodeCount: 3,
            releaseState: .completed,
            nextEpisodeAt: nil,
            stats: SeriesStats(viewCount: 0, favoriteCount: 0, trendingRank: nil),
            localeInfo: LocaleInfo(audioLanguage: "en", subtitleLanguages: ["en"]),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
