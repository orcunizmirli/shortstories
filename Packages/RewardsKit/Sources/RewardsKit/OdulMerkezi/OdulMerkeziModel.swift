import AppFoundation
import Observation

/// `OdulMerkezi` (Ödüller sekmesi) ekran modeli (SS-110/111). @Observable/@MainActor; SwiftUI View
/// ince kalır. Coin bakiyesi başlığı (`RewardsWalletReading` portu), günlük check-in takvimi + claim
/// (`CheckInService` portu, SAF döngü mantığı `CheckInCycle`), görev listesi alanı (SS-112 doldurur),
/// rewarded ad kartı alanı (F1'de flag ile gizli, SS-113), CoinMagazasi kısayolu (delegate).
///
/// PARA GÜVENLİĞİ (06 §, R6): claim SERVER-OTORİTER + idempotent. İstemci OPTİMİSTİK KREDİ VERMEZ —
/// bakiye/streak yalnız server yanıtından (`CheckInClaimResult`) yazılır. "Bugün claim edildi mi"
/// server-state'ten (`CheckInState.todayClaimed`) okunur, cihaz saatinden ASLA türetilmez (07 §3.2).
@MainActor
@Observable
public final class OdulMerkeziModel {
    /// Check-in alanının yükleme durumu (DSStateView sözleşmesi, 02 §3).
    public enum LoadState: Equatable, Sendable {
        case loading
        case loaded
        /// Genel hata — "Tekrar Dene".
        case failed
        /// Bağlantı yok — "Tekrar Dene".
        case offline
    }

    /// Claim başarısızlığı (transient; kredi VERİLMEZ). Offline'da buton "Bağlantı gerekli" der.
    public enum ClaimFailure: Equatable, Sendable {
        case offline
        case generic
    }

    /// Görev claim başarısızlığı — hangi görevin başarısız olduğunu taşır (satır-içi uyarı).
    public struct TaskClaimFailure: Equatable, Sendable {
        public let taskID: String
        public let reason: ClaimFailure

        public init(taskID: String, reason: ClaimFailure) {
            self.taskID = taskID
            self.reason = reason
        }
    }

    // MARK: - Durum (Observable)

    public private(set) var loadState: LoadState = .loading
    public private(set) var checkInState: CheckInState?
    /// Başlıktaki toplam coin bakiyesi (server-otoriter; port + claim yanıtı).
    public private(set) var coinBalance = 0
    /// Claim server yanıtını beklerken true (buton yükleniyor; çift-claim guard).
    public private(set) var isClaiming = false
    /// Başarılı claim sayacı — View haptic (SS-015) + coin uçuş animasyonunu bu token'la tetikler.
    /// Yalnız SERVER onayından SONRA artar (optimistik DEĞİL).
    public private(set) var claimCelebration = 0
    /// Son claim denemesinin başarısızlığı (offline/genel); başarıda/yeni denemede sıfırlanır.
    public private(set) var claimFailure: ClaimFailure?
    /// Rewarded ad kartı görünür mü — F1'de flag KAPALI (yapı var, gizli; SS-113 F2 açar).
    public let rewardedAdCardVisible: Bool
    /// Davet giriş kartı görünür mü — varsayılan flag KAPALI (yapı var, gizli; RWD-07 canlıda açar).
    public let referralCardVisible: Bool

    // MARK: - Görev merkezi durumu (SS-112; Observable)

    // Görev merkezi durumu — türetim/claim akışı `OdulMerkeziModel+Tasks.swift` uzantısındadır;
    // stored property'ler burada yaşar (extension'lar stored property tutamaz) ve `internal` erişimle
    // o dosyadan görülür.

    /// Görev kataloğu (server-otoriter; `TaskCatalogProviding` portundan). SAF `RewardTaskCatalog`
    /// türetimleri (`taskItems`/`claimableTaskCount`) bunun üstünde çalışır.
    var catalog = RewardTaskCatalog()
    /// Katalog en az bir kez yüklendi mi — `mission_progress`/`mission_complete` baseline'ı (ilk
    /// yüklemede milestone yok).
    var catalogLoadedOnce = false
    /// Canlı istemci-tarafı ilerleme overlay'i (`TaskProgressReading`); YALNIZ görüntüleme.
    var liveProgress: [RewardTask.Kind: Int] = [:]
    /// Şu an claim edilen görevin kimliği (satır spinner'ı + tek-seferde-bir claim guard'ı).
    public internal(set) var claimingTaskID: String?
    /// Bu oturumda başarıyla claim edilen (veya 409 ile `.claimed` senkronlanan) görev kimlikleri —
    /// eventual-consistency guard: server bayat `.claimable` döndürse bile bu görevler tazelemede
    /// `.claimed` tutulur ve `mission_complete` TEKRAR atılmaz (Fix 4).
    var claimedTaskIDs: Set<String> = []
    /// Başarılı görev claim sayacı — View haptic (SS-015) + coin uçuş animasyonunu tetikler. Yalnız
    /// SERVER onayından SONRA artar (optimistik DEĞİL).
    public internal(set) var taskClaimCelebration = 0
    /// Son görev claim denemesinin başarısızlığı; başarıda/yeni denemede sıfırlanır.
    public internal(set) var taskClaimFailure: TaskClaimFailure?

    // MARK: - Bağımlılıklar

    private let checkInService: any CheckInService
    let wallet: any RewardsWalletReading
    let taskCatalog: any TaskCatalogProviding
    private let taskProgress: any TaskProgressReading
    let rewardClaiming: any RewardClaiming
    let analytics: any AnalyticsTracking
    private let cycle: CheckInCycle
    /// Son-görülen streak kalıcılığı (08 §3.5 cold-launch `checkin_streak_break`; App `UserDefaults`'a
    /// bağlar). Varsayılan bellek-içi — additive/non-breaking (App adaptörleri değişmeden derlenir).
    private let lastSeenStreakStore: any LastSeenStreakStoring
    private weak var delegate: (any RewardsDelegate)?

    /// Şu an devam eden yükleme/tazeleme görevi; boşta iken `nil`. Yalnız EŞZAMANLI çift-yüklemeyi
    /// engeller (idempotent tazeleme) — tamamlanınca serbest kalır, sonraki onAppear yeniden tazeler.
    private var loadTask: Task<Void, Never>?
    /// İlk (tam) yükleme tamamlandı mı — sonraki tazeleme bakiye/ilerleme yeniden okumadan check-in +
    /// görev çeker (07 §4/§4.4).
    private var hasLoaded = false
    /// Claim/409 sonrası beklenen OTORİTER bakiye. Bayat akış değeri bunu EZEMEZ (coin-kaybı riski,
    /// 06 §5.2 "eski değer yeniyi ezmez"); akış bu değere yakaladığında temizlenir ve canlı akış devam
    /// eder. Fix 1: coinBalance reconciliation.
    private var awaitedBalance: Int?
    /// Check-in state generation'ı — her OTORİTER yazımda (claim başarı/409) artırılır. `refreshCheckIn`
    /// bunu `status()` await'inden ÖNCE yakalar, apply'dan ÖNCE karşılaştırır: await sırasında araya giren
    /// bir claim generation'ı bump'larsa bayat pre-claim status DÜŞÜRÜLÜR (sahte streak_break + buton
    /// regresyonu önlenir). Tek actor-hop karşılaştırma → TOCTOU'suz.
    private var checkInGeneration = 0

    public init(
        checkInService: any CheckInService,
        wallet: any RewardsWalletReading,
        taskCatalog: any TaskCatalogProviding,
        taskProgress: any TaskProgressReading,
        rewardClaiming: any RewardClaiming,
        analytics: any AnalyticsTracking,
        featureFlags: any FeatureFlagReading,
        delegate: (any RewardsDelegate)?,
        cycle: CheckInCycle = CheckInCycle(),
        lastSeenStreakStore: any LastSeenStreakStoring = InMemoryLastSeenStreakStore()
    ) {
        self.checkInService = checkInService
        self.wallet = wallet
        self.taskCatalog = taskCatalog
        self.taskProgress = taskProgress
        self.rewardClaiming = rewardClaiming
        self.analytics = analytics
        self.cycle = cycle
        self.lastSeenStreakStore = lastSeenStreakStore
        self.delegate = delegate
        rewardedAdCardVisible = featureFlags.value(for: RewardsFlags.rewardedAdCard)
        referralCardVisible = featureFlags.value(for: RewardsFlags.referralCard)
    }

    // MARK: - Türetimler (SAF; View doğrudan okur)

    /// Check-in takvimi hücreleri (past/today/upcoming + bonus).
    public var calendar: [CheckInDayCell] {
        cycle.calendar(for: checkInState)
    }

    /// Bugün ödül alınabilir mi — yüklenmiş VE server "todayClaimed == false" diyorsa.
    public var canClaimToday: Bool {
        loadState == .loaded && checkInState?.todayClaimed == false
    }

    /// Kesintisiz gün sayısı (streak sayacı başlığı).
    public var streakDays: Int {
        checkInState?.streakDays ?? 0
    }

    /// Bugün 7. gün streak bonusu mu (rozet/animasyon).
    public var isStreakBonusDay: Bool {
        checkInState.map { cycle.isStreakBonusDay(cycleDay: $0.cycleDay) } ?? false
    }

    /// Bugünün ödülü (buton etiketi "Ödülü Al · N coin") — takvim bugün hücresiyle TEK kaynak
    /// (`cycle.todayReward`): server-otoriter + schedule/tablo fallback (server 0 verince buton 0 göstermesin).
    public var todayReward: Int {
        checkInState.map { cycle.todayReward(for: $0) } ?? 0
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        trackScreenView()
        startRefreshIfIdle()
    }

    /// Tazeleme görevini başlatır — ilk çağrı TAM yükler, sonrakiler check-in + görev tazeler (07 §4/
    /// §4.4: her görünürlükte tazele). Guard YALNIZ eşzamanlı çift-yüklemeyi engeller; görev tamamlanınca
    /// `loadTask` serbest kalır (idempotent tazeleme — ömür boyu tek-sefer DEĞİL).
    private func startRefreshIfIdle() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in await self?.runRefresh() }
    }

    /// İlk çağrıda `load()` (bakiye + ilerleme + katalog + check-in), sonraki çağrılarda yalnız katalog +
    /// check-in tazeler. Tamamlanınca `loadTask`'ı serbest bırakır → sonraki onAppear yeniden tazeleyebilir.
    private func runRefresh() async {
        if hasLoaded {
            await refreshTasks()
            await refreshCheckIn()
        } else {
            await load()
            hasLoaded = true
        }
        loadTask = nil
    }

    /// Testler için: askıdaki ilk yükleme görevini bekler (deterministik).
    func pendingWork() async {
        await loadTask?.value
    }

    /// İlk yükleme: bakiye portu + görev kataloğu/ilerlemesi + check-in durumu. Görevler İKİNCİL:
    /// katalog hatası ekranı düşürMEZ (best-effort), yükleme durumunu check-in yönetir.
    public func load() async {
        coinBalance = await wallet.currentBalance()
        liveProgress = await taskProgress.currentProgress()
        await refreshTasks()
        await refreshCheckIn()
    }

    /// Hata durumundan "Tekrar Dene" — görev kataloğunu + check-in durumunu yeniden çeker.
    public func retry() async {
        loadState = .loading
        await refreshTasks()
        await refreshCheckIn()
    }

    private func refreshCheckIn() async {
        let generation = checkInGeneration
        do {
            let state = try await checkInService.status()
            // Uçuştaki status(), await sırasında araya giren bir claim'in TAZE state'ini EZMESİN: claim
            // generation'ı bump'lar → bayat pre-claim status düşürülür (sahte checkin_streak_break + buton
            // regresyonu önlenir). Claim zaten loadState=.loaded + otoriter checkInState yazdı.
            guard generation == checkInGeneration else { return }
            applyLoadedState(state)
            loadState = .loaded
            // Görev listesi (missionSection) yalnız .loaded'da görünür → mission_view (08 §3.5).
            analytics.trackMissionView(missionIDs: catalog.visibleTasks.map(\.id))
        } catch {
            loadState = Self.loadFailure(for: error)
        }
    }

    /// Canlı bakiye + görev ilerleme akışlarını dinler. View `.task` ile sürer → ekran kaybolunca
    /// OTOMATİK iptal (task-group çocukları da iptal olur). İlk yükleme snapshot'ından sonra abone olur.
    /// Akışlar (Sendable) önce alınır; her değer @MainActor apply metoduyla uygulanır (bölge-izolasyon).
    public func observeUpdates() async {
        // İlk yükleme henüz olmadıysa başlat (yalnız .task kullanan View); olduysa mevcut/biten görevi
        // bekle — tazeleme onAppear'ın işi, burada gereksiz ikinci fetch tetiklenmez.
        if !hasLoaded {
            startRefreshIfIdle()
        }
        await loadTask?.value
        let balances = wallet.balanceUpdates()
        let progressUpdates = taskProgress.progressUpdates()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                for await balance in balances {
                    await self?.applyBalance(balance)
                }
            }
            group.addTask { [weak self] in
                for await progress in progressUpdates {
                    await self?.applyLiveProgress(progress)
                }
            }
        }
    }

    private func applyBalance(_ balance: Int) {
        // Fix 1 + audit MEDIUM: claim/409 sonrası beklenen OTORİTER bakiye varken yalnız BAYAT (awaited'in
        // ALTINDAKI, claim öncesi in-flight) akış değeri onu EZMESİN. Akış otoriter değere YETİŞİNCE ya da
        // AŞINCA (eşzamanlı yeni kredi: görev/VIP/ad) guard temizlenir → canlı güncelleme devam eder.
        // EXACT-match guard, awaited hiç yeniden yayılmazsa (409 read broadcast tetiklemez / version-guard
        // snapshot'ı düşürür) kalıcı DONUYORDU: awaited'i atlayan yeni değer düşürülüp başlık sonraki tüm
        // güncellemeleri yutuyordu. `>=` bunu önler (bayat-ALT değer yine düşürülür).
        if let awaited = awaitedBalance {
            guard balance >= awaited else { return }
            awaitedBalance = nil
        }
        coinBalance = balance
    }

    /// OTORİTER bakiye kredisi (claim yanıtı / 409 sonrası cüzdan okuması): başlığı günceller ve akışın
    /// bu değere yakalamasını bekler — araya giren BAYAT akış değeri krediyi ezemez (Fix 1). Görev claim
    /// akışı (`+Tasks` uzantısı) da kullanır → `internal`.
    func applyAuthoritativeBalance(_ balance: Int) {
        coinBalance = balance
        awaitedBalance = balance
    }

    private func applyLiveProgress(_ progress: [RewardTask.Kind: Int]) {
        liveProgress = progress
    }

    // MARK: - Claim (server-otoriter, idempotent)

    /// Günlük ödülü talep eder. Guard: yüklenmiş, bugün alınmamış, halihazırda claim edilmiyor
    /// (çift-claim UI'dan tetiklenemez). Başarı → server bakiyesi/durumu + haptic/animasyon +
    /// `checkin_claim`. 409 → sessiz senkron (toast yok). Offline/hata → kredi YOK, buton retry.
    public func claimToday() async {
        guard let current = checkInState, !current.todayClaimed, !isClaiming, loadState == .loaded else {
            return
        }
        isClaiming = true
        claimFailure = nil
        defer { isClaiming = false }
        do {
            let result = try await checkInService.claim()
            // SERVER-OTORİTER kredi: bakiye ve durum YALNIZ server yanıtından (optimistik DEĞİL).
            applyAuthoritativeBalance(result.coinBalance) // Fix 1: bayat akış bu krediyi ezemez
            applyClaimedCheckInState(result.checkin) // generation bump + son-görülen streak persist
            claimCelebration += 1 // haptic + coin uçuş animasyonu (View tetikler)
            analytics.trackCheckinClaim(
                streakDay: result.checkin.cycleDay,
                coinReward: result.reward.coins,
                isStreakBonus: result.reward.isStreakBonus
            )
            // Başarılı check-in = POZİTİF an (RTG-01): App koordinatörü puanlama istemini burada
            // değerlendirir. Yalnız GERÇEK claim'de (idempotent 409 ALREADY_CLAIMED yolunda DEĞİL).
            delegate?.rewardsDidClaimCheckIn(streakDay: result.checkin.cycleDay)
        } catch let CheckInClaimError.alreadyClaimed(fresh) {
            // 409 ALREADY_CLAIMED: durumu sessizce senkronla, hata gösterme (idempotent tekrar). Kredi
            // ZATEN düşmüştür → başlığı otoriter cüzdandan tazele (Fix 2: bayat başlık kalmasın).
            applyClaimedCheckInState(fresh) // generation bump + son-görülen streak persist
            await applyAuthoritativeBalance(wallet.currentBalance())
        } catch {
            // Kredi VERİLMEZ; son bilinen durum korunur, kullanıcı tekrar deneyebilir.
            claimFailure = Self.claimFailure(for: error)
        }
    }

    // MARK: - Navigasyon niyetleri (delegate → App)

    /// Bakiye kartı / "Coin Al" → CoinMagazasi (02 §4.9).
    public func openCoinStore() {
        delegate?.rewardsOpensCoinStore()
    }

    /// Davet giriş kartı → App `DavetMerkezi`'yi sunar (RWD-07). Kart yalnız flag açıkken görünür.
    public func openReferral() {
        delegate?.rewardsOpensReferral()
    }

    // MARK: - İç: analitik

    private func trackScreenView() {
        analytics.track("screen_view", parameters: ["screen_name": .string("odul_merkezi")])
    }

    /// Claim (başarı/409) OTORİTER check-in state'ini uygular: checkInState yazılır, generation bump'lanır
    /// (uçuştaki refreshCheckIn bayat status'ü düşürsün) ve son-görülen streak KALICI kılınır. Son'u
    /// olmadan claim sonrası app-kill → cold-launch, önceki (bayat, daha düşük) tabana göre yanlış
    /// `checkin_streak_break` previousStreakLength'i raporlardı (08 §3.5 KPI doğruluğu, Fix 7). Kırılma
    /// tespiti YAPMAZ — claim bir "ilk gözlem" değil (streak yalnız ilerler).
    private func applyClaimedCheckInState(_ state: CheckInState) {
        checkInState = state
        checkInGeneration += 1
        lastSeenStreakStore.setLastSeenStreak(state.streakDays)
    }

    /// Check-in takvimi görünür olduğunda (08 §3.5). Streak kırılması önceki duruma göre tespit
    /// edilirse `checkin_streak_break` de atılır. `checkInState` GÜNCELLENMEDEN önce çağrılır.
    private func applyLoadedState(_ state: CheckInState) {
        // Kırılma tespiti: oturum içindeyse (previous var) bellek-içi karşılaştırma; SOĞUK AÇILIŞTA
        // (previous nil) KALICI son-görülen streak ile karşılaştır (Fix 6). Kırılmalar çoğu kez
        // oturumlar-arasıdır; cold-launch'ta emit edilmezse win-back KPI kör kalır (08 §3.5).
        let brk: StreakBreak? = if let previous = checkInState {
            cycle.detectStreakBreak(previous: previous, current: state)
        } else {
            cycle.detectStreakBreak(lastSeenStreak: lastSeenStreakStore.lastSeenStreak(), current: state)
        }
        if let brk {
            analytics.trackCheckinStreakBreak(
                brokenAtDay: brk.brokenAtDay,
                previousStreakLength: brk.previousStreakLength
            )
        }
        checkInState = state
        // Güncel server streak'ini kalıcı kıl → bir sonraki (soğuk) açılışın karşılaştırma tabanı; ayrıca
        // "istemci ilk gördüğünde 1 kez": sonraki tazeleme (warm) aynı kırılmayı TEKRAR atmaz.
        lastSeenStreakStore.setLastSeenStreak(state.streakDays)
        analytics.trackCheckinView(currentStreakDay: state.cycleDay, canClaimToday: !state.todayClaimed)
    }

    // MARK: - İç: hata eşleme

    private static func loadFailure(for error: Error) -> LoadState {
        isConnectivity(error) ? .offline : .failed
    }

    static func claimFailure(for error: Error) -> ClaimFailure {
        isConnectivity(error) ? .offline : .generic
    }

    private static func isConnectivity(_ error: Error) -> Bool {
        guard case let AppError.network(networkError) = error else { return false }
        return networkError == .offline || networkError == .timeout
    }
}
