import Testing
@testable import RewardsKit

/// SS-112 saf mantık (07 §4): görev ilerleme yüzdesi, tamamlanma eşiği, claim-edilebilirlik
/// (SERVER-otoriter — istemci ilerlemesi DEĞİL), ödül hesaplama, canlı overlay birleşimi ve
/// bilinmeyen-tip düşürme. Yan etkisiz, izole; para güvenliği (06 §, R6) burada bağlanır.
@Suite("SS-112 RewardTask/RewardTaskCatalog saf mantık")
struct RewardTaskCatalogTests {
    // MARK: - İlerleme yüzdesi (DSProgressBar girdisi)

    @Test func progressFractionIsRatioClampedToUnit() {
        #expect(RewardTask.fraction(progress: 0, target: 10) == 0)
        #expect(RewardTask.fraction(progress: 4, target: 10) == 0.4)
        #expect(RewardTask.fraction(progress: 10, target: 10) == 1)
        #expect(RewardTask.fraction(progress: 25, target: 10) == 1) // hedefi aşan ilerleme 1'e kırpılır
        #expect(RewardTask.fraction(progress: -3, target: 10) == 0)
    }

    @Test func progressFractionHandlesNonPositiveTarget() {
        #expect(RewardTask.fraction(progress: 0, target: 0) == 0)
        #expect(RewardTask.fraction(progress: 1, target: 0) == 1) // hedef yoksa ilerleme varsa dolu
    }

    // MARK: - Tamamlanma eşiği

    @Test func completionThresholdAtOrAboveTarget() {
        #expect(!RewardTask.isComplete(progress: 9, target: 10))
        #expect(RewardTask.isComplete(progress: 10, target: 10))
        #expect(RewardTask.isComplete(progress: 12, target: 10))
        #expect(RewardTask.mock(target: 10, progress: 3).isComplete == false)
        #expect(RewardTask.mock(target: 10, progress: 10).isComplete)
    }

    // MARK: - Claim-edilebilirlik: SERVER-otoriter (ilerleme DEĞİL) — para güvenliği (06 §, R6)

    @Test func claimabilityIsServerStateNotLocalProgress() {
        // Tamamlanmış ama sunucu henüz claimable yapmamış → claim EDİLEMEZ (istemci eşiği açmaz).
        let complete = RewardTask.mock(target: 10, progress: 10, state: .inProgress)
        #expect(complete.isComplete)
        #expect(complete.isClaimable == false)

        // Sunucu claimable yaptı → claim edilebilir.
        #expect(RewardTask.mock(target: 10, progress: 10, state: .claimable).isClaimable)
        // İlerleme hedefin altında ama sunucu claimable derse yine server kazanır (server-otoriter).
        #expect(RewardTask.mock(target: 10, progress: 2, state: .claimable).isClaimable)
        #expect(RewardTask.mock(state: .claimed).isClaimable == false)
        #expect(RewardTask.mock(state: .locked).isClaimable == false)
    }

    // MARK: - Görüntü durumu eşlemesi

    @Test func displayStatusMapsServerState() {
        #expect(RewardTask.displayStatus(for: .locked) == .locked)
        #expect(RewardTask.displayStatus(for: .inProgress) == .inProgress)
        #expect(RewardTask.displayStatus(for: .claimable) == .claimable)
        #expect(RewardTask.displayStatus(for: .claimed) == .claimed)
        #expect(RewardTask.displayStatus(for: .unknown) == .inProgress) // güvenli varsayılan (claim-edilemez)
    }

    // MARK: - Kind ileri uyumluluğu (UnknownDecodable kalıbı, 07 §4.3)

    @Test func kindRawValueRoundTrips() {
        for raw in ["watchMinutes", "favoriteSeries", "shareSeries", "enableNotifications", "linkAccount", "watchAd"] {
            #expect(RewardTask.Kind(rawValue: raw).rawValue == raw)
            #expect(RewardTask.Kind(rawValue: raw).isKnown)
        }
        let unknown = RewardTask.Kind(rawValue: "completeEpisodes")
        #expect(unknown == .unknown("completeEpisodes"))
        #expect(unknown.isKnown == false)
        #expect(unknown.rawValue == "completeEpisodes")
    }

    // MARK: - Katalog: görünürlük + rozet + ödül toplamı

    @Test func visibleTasksDropUnknownKinds() {
        let catalog = RewardTaskCatalog(tasks: [
            .mock(id: "a", kind: .watchMinutes),
            .mock(id: "b", kind: .unknown("completeEpisodes")),
            .mock(id: "c", kind: .favoriteSeries)
        ])
        #expect(catalog.visibleTasks.map(\.id) == ["a", "c"])
        #expect(catalog.items().map(\.id) == ["a", "c"]) // hücreler de bilinmeyeni düşürür
    }

    @Test func claimableCountAndRewardTotal() {
        let catalog = RewardTaskCatalog(tasks: [
            .mock(id: "a", rewardCoins: 20, state: .claimable),
            .mock(id: "b", rewardCoins: 15, state: .claimable),
            .mock(id: "c", rewardCoins: 10, state: .inProgress),
            .mock(id: "d", kind: .unknown("x"), rewardCoins: 30, state: .claimable) // bilinmeyen sayılmaz
        ])
        #expect(catalog.claimableCount == 2)
        #expect(catalog.claimableRewardTotal == 35)
    }

    // MARK: - Canlı ilerleme birleşimi (YALNIZ görüntüleme; server taban)

    @Test func itemsMergeLiveProgressAsDisplayFloorMax() {
        let catalog = RewardTaskCatalog(tasks: [.mock(kind: .watchMinutes, target: 10, progress: 4)])
        // Canlı overlay server'ın önünde → çubuk ilerler (görüntüleme).
        let ahead = catalog.items(liveProgress: [.watchMinutes: 8])
        #expect(ahead[0].displayedProgress == 8)
        // Canlı overlay server'ın gerisinde (bayat) → server tabanı korunur.
        let behind = catalog.items(liveProgress: [.watchMinutes: 1])
        #expect(behind[0].displayedProgress == 4)
        // Overlay hedefi aşarsa hücre hedefe kırpılır.
        let over = catalog.items(liveProgress: [.watchMinutes: 99])
        #expect(over[0].displayedProgress == 10)
    }

    @Test func liveOverlayDoesNotAffectClaimability() {
        // Overlay hedefi doldursa bile server state inProgress → claim-edilemez (fraud güvenliği).
        let catalog = RewardTaskCatalog(tasks: [.mock(kind: .watchMinutes, target: 10, progress: 2, state: .inProgress)])
        let item = catalog.items(liveProgress: [.watchMinutes: 10])[0]
        #expect(item.displayedProgress == 10)
        #expect(item.progressFraction == 1)
        #expect(item.isClaimable == false)
        #expect(item.status == .inProgress)
    }

    struct MergeCase: Sendable {
        let server: Int
        let live: Int?
        let target: Int
        let expected: Int
    }

    static let mergeCases: [MergeCase] = [
        MergeCase(server: 4, live: nil, target: 10, expected: 4), // overlay yok → server
        MergeCase(server: 4, live: 7, target: 10, expected: 7), // overlay önde → overlay
        MergeCase(server: 4, live: 2, target: 10, expected: 4), // overlay bayat → server
        MergeCase(server: 4, live: 20, target: 10, expected: 10), // hedefe kırp
        MergeCase(server: -5, live: 3, target: 10, expected: 3), // negatif server tabanı 0'a çekilir
        MergeCase(server: 8, live: 8, target: 0, expected: 8) // hedef yok → kırpma yok
    ]

    @Test(arguments: mergeCases)
    func mergedProgressRules(_ testCase: MergeCase) {
        #expect(
            RewardTaskCatalog.mergedProgress(server: testCase.server, live: testCase.live, target: testCase.target)
                == testCase.expected
        )
    }

    // MARK: - Vade notu (istemci saati OKUNMAZ; resetPolicy'den saf)

    @Test func expiryNoteOnlyForClaimableByResetPolicy() {
        let daily = RewardTaskCatalog(tasks: [.mock(state: .claimable, resetPolicy: .daily)]).items()[0]
        #expect(daily.expiryNote == .today)
        let weekly = RewardTaskCatalog(tasks: [.mock(state: .claimable, resetPolicy: .weekly)]).items()[0]
        #expect(weekly.expiryNote == .thisWeek)
        let oneTime = RewardTaskCatalog(tasks: [.mock(state: .claimable, resetPolicy: .oneTime)]).items()[0]
        #expect(oneTime.expiryNote == nil)
        // Claim-edilebilir değilse vade notu yok (henüz yanacak ödül yok).
        let inProgress = RewardTaskCatalog(tasks: [.mock(state: .inProgress, resetPolicy: .daily)]).items()[0]
        #expect(inProgress.expiryNote == nil)
    }

    // MARK: - Yeni tamamlanan tespiti (mission_complete milestone'u; ilk yüklemede yok)

    @Test func newlyClaimableEmptyOnFirstLoad() {
        let current = RewardTaskCatalog(tasks: [.mock(id: "a", state: .claimable)])
        #expect(current.newlyClaimable(comparedTo: nil).isEmpty)
    }

    @Test func newlyClaimableDetectsTransitionToClaimable() {
        let previous = RewardTaskCatalog(tasks: [
            .mock(id: "a", state: .inProgress),
            .mock(id: "b", state: .claimable) // zaten claimable → tekrar sayılmaz
        ])
        let current = RewardTaskCatalog(tasks: [
            .mock(id: "a", state: .claimable), // yeni tamamlandı
            .mock(id: "b", state: .claimable)
        ])
        #expect(current.newlyClaimable(comparedTo: previous).map(\.id) == ["a"])
    }

    // MARK: - %50 ilk geçiş tespiti (mission_progress milestone'u; server ilerlemesi, ilk yüklemede yok)

    @Test func newlyHalfwayEmptyOnFirstLoad() {
        let current = RewardTaskCatalog(tasks: [.mock(target: 10, progress: 8)])
        #expect(current.newlyHalfway(comparedTo: nil).isEmpty)
    }

    @Test func newlyHalfwayDetectsCrossingFiftyPercent() {
        let previous = RewardTaskCatalog(tasks: [
            .mock(id: "a", target: 10, progress: 3), // %30
            .mock(id: "b", target: 10, progress: 7) // zaten %70 → tekrar sayılmaz
        ])
        let current = RewardTaskCatalog(tasks: [
            .mock(id: "a", target: 10, progress: 6), // %30 → %60 ilk geçiş
            .mock(id: "b", target: 10, progress: 9)
        ])
        #expect(current.newlyHalfway(comparedTo: previous).map(\.id) == ["a"])
    }

    @Test func hasReachedHalfwayUsesServerProgressAtOrAboveHalf() {
        #expect(RewardTaskCatalog.hasReachedHalfway(.mock(target: 10, progress: 4)) == false) // %40
        #expect(RewardTaskCatalog.hasReachedHalfway(.mock(target: 10, progress: 5))) // %50 sınır dahil
        #expect(RewardTaskCatalog.hasReachedHalfway(.mock(target: 10, progress: 9)))
    }

    // MARK: - mission_type taksonomisi (08 §3.5; RewardTask.Kind tek eşleme noktası)

    @Test func analyticsMissionTypeMapsRegistryTaxonomy() {
        #expect(RewardTask.Kind.watchMinutes.analyticsMissionType == "watch_time")
        #expect(RewardTask.Kind.favoriteSeries.analyticsMissionType == "favorite")
        #expect(RewardTask.Kind.shareSeries.analyticsMissionType == "share")
        #expect(RewardTask.Kind.enableNotifications.analyticsMissionType == "push_optin")
        // Registry karşılığı olmayan kind'ler → nil (mission lifecycle event'i atılmaz).
        #expect(RewardTask.Kind.linkAccount.analyticsMissionType == nil)
        #expect(RewardTask.Kind.watchAd.analyticsMissionType == nil)
        #expect(RewardTask.Kind.unknown("x").analyticsMissionType == nil)
    }

    // MARK: - F2 watchAd flag gate (SS-113): rewarded ad KAPALI iken watchAd görevleri düşer

    @Test func visibleTasksDropWatchAdWhenRewardedAdDisabled() {
        let tasks: [RewardTask] = [
            .mock(id: "a", kind: .watchMinutes),
            .mock(id: "ad", kind: .watchAd, rewardCoins: 30, state: .claimable)
        ]
        let disabled = RewardTaskCatalog(tasks: tasks, rewardedAdEnabled: false)
        #expect(disabled.visibleTasks.map(\.id) == ["a"]) // watchAd render edilmez
        #expect(disabled.claimableCount == 0)
        #expect(disabled.items().map(\.id) == ["a"])

        let enabled = RewardTaskCatalog(tasks: tasks, rewardedAdEnabled: true)
        #expect(enabled.visibleTasks.map(\.id) == ["a", "ad"]) // flag açık → görünür (F2)
        #expect(enabled.claimableCount == 1)
    }
}
