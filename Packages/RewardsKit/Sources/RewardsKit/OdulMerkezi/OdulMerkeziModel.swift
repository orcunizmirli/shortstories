import AppFoundation
import Observation

/// `OdulMerkezi` (Ödüller sekmesi) ekran modeli (SS-110/111). @Observable/@MainActor; coin bakiyesi
/// başlığı + günlük check-in takvimi/claim (`CheckInService`/`CheckInCycle`) + görev listesi (SS-112).
/// PARA GÜVENLİĞİ (06 §, R6): claim SERVER-OTORİTER + idempotent; istemci optimistik KREDİ VERMEZ
/// (bakiye/streak yalnız server yanıtından); "bugün claim edildi mi" server-state'ten (07 §3.2).
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
    /// Başarılı claim sayacı — View haptic + coin animasyonu (yalnız SERVER onayından sonra artar).
    public private(set) var claimCelebration = 0
    /// Son claim denemesinin başarısızlığı (offline/genel); başarıda/yeni denemede sıfırlanır.
    public private(set) var claimFailure: ClaimFailure?
    /// Rewarded ad kartı görünür mü — F1'de flag KAPALI (yapı var, gizli; SS-113 F2 açar).
    public let rewardedAdCardVisible: Bool
    /// Davet giriş kartı görünür mü — varsayılan flag KAPALI (yapı var, gizli; RWD-07 canlıda açar).
    public let referralCardVisible: Bool

    // MARK: - Görev merkezi durumu (SS-112; Observable)

    // Görev merkezi stored property'leri (türetim/claim akışı `OdulMerkeziModel+Tasks.swift`'te; `internal`).

    /// Görev kataloğu (server-otoriter; `TaskCatalogProviding`). SAF türetimler bunun üstünde çalışır.
    var catalog = RewardTaskCatalog()
    /// Katalog en az bir kez yüklendi mi — mission_progress/complete baseline'ı (ilk yüklemede yok).
    var catalogLoadedOnce = false
    /// Canlı istemci-tarafı ilerleme overlay'i (`TaskProgressReading`); YALNIZ görüntüleme.
    var liveProgress: [RewardTask.Kind: Int] = [:]
    /// Şu an claim edilen görevin kimliği (satır spinner'ı + tek-seferde-bir claim guard'ı).
    public internal(set) var claimingTaskID: String?
    /// Bu oturumda claim edilen (veya 409'da senkron) görev id'leri — eventual-consistency guard: server
    /// bayat `.claimable` dönse bile `.claimed` tutulur, `mission_complete` tekrar atılmaz (Fix 4).
    var claimedTaskIDs: Set<String> = []
    /// Başarılı görev claim sayacı — View haptic + coin animasyonu (yalnız SERVER onayından sonra).
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
    /// Son-görülen streak kalıcılığı (08 §3.5 cold-launch break; App UserDefaults'a bağlar).
    private let lastSeenStreakStore: any LastSeenStreakStoring
    private weak var delegate: (any RewardsDelegate)?

    /// Devam eden yükleme/tazeleme görevi (boşta nil) — yalnız eşzamanlı çift-yüklemeyi engeller.
    private var loadTask: Task<Void, Never>?
    /// İlk (tam) yükleme tamamlandı mı — sonraki tazeleme yalnız check-in + görev çeker (07 §4.4).
    private var hasLoaded = false
    /// Uygulanmış en yüksek cüzdan-akış version'ı (audit MEDIUM applyBalance donması): applyBalance yalnız
    /// STRICTLY-NEWER version'ı uygular (bayat düşük değer düşürülür, meşru spend uygulanır). Claim iyimser
    /// gösterir, version bump ETMEZ → sonraki (daha yüksek version) akış onaylar. Snapshot yokken `Int.min`.
    private var lastAppliedBalanceVersion = Int.min
    /// Check-in state generation'ı — her OTORİTER yazımda (claim başarı/409) artar. refreshCheckIn'i
    /// status() await'i öncesi yakalar/apply öncesi karşılaştırır: araya giren claim bayat pre-claim
    /// status'ü düşürür (sahte streak_break + buton regresyonu; tek actor-hop → TOCTOU'suz).
    private var checkInGeneration = 0
    /// Hesap-değişimi epoch'u — YALNIZ resetForAccountSwitch'te artar. TÜM apply-after-await yolları
    /// (claim/load/refreshTasks/runRefresh) await ÖNCESİ yakalar, apply ÖNCESİ `guard epoch == accountEpoch`
    /// ile karşılaştırır: switch uçuştaki isteğin ortasına girerse önceki hesabın yanıtı yeni hesaba
    /// YAZILMAZ (WalletStore accountEpoch deseni; SS-132 cross-account). `internal`: `+Tasks` de fence eder.
    var accountEpoch = 0

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
        let epoch = accountEpoch
        if hasLoaded {
            await refreshTasks()
            await refreshCheckIn()
        } else {
            await load()
            guard epoch == accountEpoch else { return } // switch olduysa hasLoaded YAPMA + loadTask'ı EZME
            hasLoaded = true
        }
        // Yalnız GÜNCEL epoch'un görevi loadTask'ı bıraksın (bayat/switch-öncesi görev yenisini ezmesin; #2 fix).
        guard epoch == accountEpoch else { return }
        loadTask = nil
    }

    /// Testler için: askıdaki ilk yükleme görevini bekler (deterministik).
    func pendingWork() async {
        await loadTask?.value
    }

    /// İlk yükleme: bakiye portu + görev kataloğu/ilerlemesi + check-in durumu. Görevler İKİNCİL:
    /// katalog hatası ekranı düşürMEZ (best-effort), yükleme durumunu check-in yönetir.
    public func load() async {
        let epoch = accountEpoch
        let balance = await wallet.currentBalance()
        let progress = await taskProgress.currentProgress()
        guard epoch == accountEpoch else { return } // hesap-değişimi fence'i (uçuştaki load → yeni hesaba yazma)
        coinBalance = balance.balance
        lastAppliedBalanceVersion = balance.version // baseline: sonraki replay (aynı version) düşürülür
        liveProgress = progress
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
            // Uçuştaki status() await sırasında araya giren claim generation'ı bump'larsa bayat pre-claim
            // status'ü düşür (sahte checkin_streak_break + buton regresyonu; claim zaten .loaded + state yazdı).
            guard generation == checkInGeneration else { return }
            applyLoadedState(state)
            loadState = .loaded
            // Görev listesi (missionSection) yalnız .loaded'da görünür → mission_view (08 §3.5).
            analytics.trackMissionView(missionIDs: catalog.visibleTasks.map(\.id))
        } catch {
            // Fix (self-review2): CATCH da generation-fence'li (başarı yolu gibi). Aksi halde araya giren
            // claim/reset SONRASI status() THROW ederse loadState .failed'e düşüp para-ekranını tam-ekran
            // hataya kırardı (başarılı claim'e rağmen buton regresyonu, throw yolu / B'de sahte hata).
            guard generation == checkInGeneration else { return }
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
                for await update in balances {
                    await self?.applyBalance(update)
                }
            }
            group.addTask { [weak self] in
                for await progress in progressUpdates {
                    await self?.applyLiveProgress(progress)
                }
            }
        }
    }

    private func applyBalance(_ update: RewardsBalanceUpdate) {
        // audit MEDIUM (donma fix): yalnız STRICTLY-NEWER version uygulanır → bayat düşük değer (pre-claim
        // replay) düşürülür, MEŞRU düşüş (spend, daha yüksek version) uygulanır. Value-heuristic (`>= awaited`)
        // çoklu-stale ile meşru-spend'i ayıramadığından başlık bayat-YÜKSEK DONUYORDU (bu fix'in özü).
        guard update.version > lastAppliedBalanceVersion else { return }
        lastAppliedBalanceVersion = update.version
        coinBalance = update.balance
    }

    /// OTORİTER bakiye kredisi (claim/409 sonrası): başlığı İYİMSER günceller (server yanıtından); version bump
    /// ETMEZ → sonraki (daha yüksek version) akış onaylar, bayat akış krediyi EZEMEZ. `+Tasks` da kullanır.
    func applyAuthoritativeBalance(_ balance: Int) {
        coinBalance = balance
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
        let epoch = accountEpoch
        do {
            let result = try await checkInService.claim()
            guard epoch == accountEpoch else { return } // hesap-değişimi fence'i (uçuştaki claim → yeni hesaba yazma)
            // SERVER-OTORİTER kredi (optimistik DEĞİL); bayat akış bu krediyi ezemez (Fix 1).
            applyAuthoritativeBalance(result.coinBalance)
            applyClaimedCheckInState(result.checkin) // generation bump + son-görülen streak persist
            claimCelebration += 1 // haptic + coin uçuş animasyonu (View tetikler)
            analytics.trackCheckinClaim(
                streakDay: result.checkin.cycleDay,
                coinReward: result.reward.coins,
                isStreakBonus: result.reward.isStreakBonus
            )
            // Başarılı check-in = POZİTİF an (RTG-01): puanlama istemi (yalnız GERÇEK claim, 409'da DEĞİL).
            delegate?.rewardsDidClaimCheckIn(streakDay: result.checkin.cycleDay)
        } catch let CheckInClaimError.alreadyClaimed(fresh) {
            // 409 ALREADY_CLAIMED: sessiz senkron (hata gösterme); kredi zaten düşmüş → başlığı tazele (Fix 2).
            guard epoch == accountEpoch else { return }
            let balance = await wallet.currentBalance()
            guard epoch == accountEpoch else { return }
            applyClaimedCheckInState(fresh) // generation bump + son-görülen streak persist
            applyAuthoritativeBalance(balance.balance)
        } catch {
            // Kredi VERİLMEZ; kullanıcı retry. #5 fence: switch SONRASI çözülen A hatası B'ye YAZILMASIN.
            guard epoch == accountEpoch else { return }
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

    /// Claim (başarı/409) OTORİTER check-in state'ini uygular: checkInState + generation bump (uçuştaki
    /// refreshCheckIn bayat status'ü düşürsün) + son-görülen streak persist (Fix 7: claim-sonrası app-kill →
    /// cold-launch yanlış previousStreakLength'i önler). Kırılma tespiti YAPMAZ (claim "ilk gözlem" değil).
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
}

// MARK: - Hesap değişimi sıfırlama (05 §3.3 / SS-132)

public extension OdulMerkeziModel {
    /// Hesap değişiminde hesap-ÖZEL bellek-içi durumu sıfırlar (model TabCoordinator ömrü boyu yaşar →
    /// sıfırlanmazsa cross-account: sahte streak_break, yanlış .claimed pin, bayat coinBalance, A hata banner'ı).
    /// accountEpoch/checkInGeneration bump uçuştakini fence eder; hasLoaded=false tam-yükletir.
    func resetForAccountSwitch() {
        accountEpoch += 1 // uçuştaki claim/load/refreshTasks yanıtlarını fence et (önceki hesap → yeni'ye yazmasın)
        checkInGeneration += 1
        checkInState = nil
        coinBalance = 0
        lastAppliedBalanceVersion = Int.min // yeni hesap: baseline sıfırla → ilk load version'ı yakalar
        catalog = RewardTaskCatalog()
        catalogLoadedOnce = false
        liveProgress = [:]
        claimedTaskIDs.removeAll()
        hasLoaded = false
        loadState = .loading
        lastSeenStreakStore.reset()
        claimFailure = nil // #5 fix: YERLEŞMİŞ A hata banner'ları B'ye sızmasın (load/refresh temizlemez)
        taskClaimFailure = nil
        // #2 fix: uçuştaki yüklemeyi iptal + loadTask serbest → yoksa onAppear reload'u boğulur (sonsuz .loading).
        loadTask?.cancel()
        loadTask = nil
    }
}
