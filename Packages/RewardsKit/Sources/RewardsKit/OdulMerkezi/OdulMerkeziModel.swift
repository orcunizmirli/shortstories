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
    /// Check-in claim eventual-consistency pini (task `claimedTaskIDs` simetriği): claim-sonrası warm refresh'te
    /// server bayat pre-claim (todayClaimed=false) dönerse downgrade'i düşürür; server onaylayınca (todayClaimed) düşer.
    private var checkInClaimedPin = false
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
    weak var delegate: (any RewardsDelegate)? // internal: `+Tasks` extension'ı claim-credit bildirimi için erişir

    /// Devam eden yükleme/tazeleme görevi (boşta nil) — yalnız eşzamanlı çift-yüklemeyi engeller.
    private var loadTask: Task<Void, Never>?
    /// İlk (tam) yükleme tamamlandı mı — sonraki tazeleme yalnız check-in + görev çeker (07 §4.4).
    private var hasLoaded = false
    /// Uygulanmış en yüksek cüzdan-akış version'ı (audit MEDIUM donma fix): applyBalance yalnız STRICTLY-NEWER uygular;
    /// claim version bump ETMEZ (sonraki akış onaylar). Snapshot yokken `Int.min`.
    private var lastAppliedBalanceVersion = Int.min
    /// Check-in state generation'ı — her OTORİTER yazımda (claim başarı/409) artar. refreshCheckIn status() await'i
    /// öncesi yakalar/apply öncesi karşılaştırır: araya giren claim bayat pre-claim status'ü düşürür (tek actor-hop).
    private var checkInGeneration = 0
    /// Hesap-değişimi epoch'u — YALNIZ resetForAccountSwitch'te artar. TÜM apply-after-await yolları await ÖNCESİ
    /// yakalar, apply ÖNCESİ `guard epoch == accountEpoch`: switch araya girerse önceki hesabın yanıtı YAZILMAZ (SS-132).
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
        // KOŞULSUZ (version-guard'sız): hesaplar-arası version monoton değil → baseline sıfırlanır (yeni hesabı self-heal).
        coinBalance = balance.balance
        lastAppliedBalanceVersion = balance.version
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
            // Uçuştaki status() await'inde araya giren claim generation'ı bump'larsa bayat pre-claim status'ü düşür.
            guard generation == checkInGeneration else { return }
            applyLoadedState(state)
            loadState = .loaded
            // Görev listesi (missionSection) yalnız .loaded'da görünür → mission_view (08 §3.5).
            analytics.trackMissionView(missionIDs: catalog.visibleTasks.map(\.id))
        } catch {
            // CATCH da generation-fence'li (başarı yolu gibi): araya giren claim/reset SONRASI status() throw ederse
            // loadState .failed'e düşüp para-ekranını (başarılı claim'e rağmen) tam-ekran hataya kırmasın (self-review2).
            guard generation == checkInGeneration else { return }
            loadState = Self.loadFailure(for: error)
        }
    }

    /// Canlı bakiye + görev ilerleme akışlarını dinler. View `.task` ile sürer → ekran kaybolunca OTOMATİK iptal.
    /// İlk yükleme sonrası abone olur; akışlar (Sendable) önce alınır, her değer @MainActor apply ile (bölge-izolasyon).
    public func observeUpdates() async {
        // İlk yükleme yoksa başlat (yalnız .task kullanan View); varsa mevcut/biten görevi bekle (tazeleme onAppear'ın).
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
        // Cross-account poison guard: canlı stream yalnız otoriter baseline (load) SONRASI uygulanır → switch
        // penceresinde bayat eski-hesap emisyonu (version hesaplar-arası monoton değil) poison'lamaz (self-review).
        guard hasLoaded else { return }
        // audit MEDIUM (donma fix): yalnız STRICTLY-NEWER version uygulanır (bayat replay düşer, MEŞRU spend uygulanır).
        guard update.version > lastAppliedBalanceVersion else { return }
        lastAppliedBalanceVersion = update.version
        coinBalance = update.balance
    }

    /// OTORİTER bakiye kredisi (claim/409): başlığı İYİMSER günceller; version bump ETMEZ → sonraki akış onaylar.
    func applyAuthoritativeBalance(_ balance: Int) {
        coinBalance = balance
    }

    private func applyLiveProgress(_ progress: [RewardTask.Kind: Int]) {
        liveProgress = progress
    }

    // MARK: - Claim (server-otoriter, idempotent)

    /// Günlük ödülü talep eder. Guard: yüklenmiş, bugün alınmamış, claim edilmiyor (çift-claim UI'dan tetiklenemez).
    /// Başarı → server bakiyesi/durumu + haptic + `checkin_claim`. 409 → sessiz senkron. Offline/hata → kredi YOK.
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
            delegate?.rewardsDidCreditBalance() // #2: App WalletStore.refresh → Profil/CoinShop başlıkla yakınsar
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

    /// Claim (başarı/409) OTORİTER check-in state'ini uygular: checkInState + generation bump + claim-pin + son-görülen
    /// streak persist (Fix 7: claim-sonrası app-kill → cold-launch yanlış previousStreakLength). Kırılma tespiti YAPMAZ.
    private func applyClaimedCheckInState(_ state: CheckInState) {
        checkInState = state
        checkInGeneration += 1
        checkInClaimedPin = true // claim-sonrası bayat pre-claim status downgrade'ini engelle (server onaylayınca düşer)
        lastSeenStreakStore.setLastSeenStreak(state.streakDays)
    }

    /// Check-in takvimi görünür olduğunda (08 §3.5); streak kırılması tespit edilirse `checkin_streak_break` atılır.
    private func applyLoadedState(_ state: CheckInState) {
        // Claim-pin reconcile (task reconcileClaimed Fix 4 simetriği): claim-sonrası warm refresh'te server bayat
        // pre-claim dönerse DÜŞÜR (buton regresyonu/sahte streak_break önle); todayClaimed onaylanınca pin düşer.
        if checkInClaimedPin {
            guard state.todayClaimed else { return }
            checkInClaimedPin = false
        }
        // Kırılma tespiti: oturum-içi (previous var) bellek karşılaştırması; SOĞUK AÇILIŞTA (previous nil) KALICI
        // son-görülen streak ile (Fix 6 — kırılmalar çoğu kez oturumlar-arası; cold-launch'ta emitlenmezse KPI kör).
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
        // Güncel server streak'ini kalıcı kıl → sonraki (soğuk) açılışın karşılaştırma tabanı + warm refresh aynı
        // kırılmayı TEKRAR atmaz ("istemci ilk gördüğünde 1 kez").
        lastSeenStreakStore.setLastSeenStreak(state.streakDays)
        analytics.trackCheckinView(currentStreakDay: state.cycleDay, canClaimToday: !state.todayClaimed)
    }
}

// MARK: - Hesap değişimi sıfırlama (05 §3.3 / SS-132)

public extension OdulMerkeziModel {
    /// Hesap değişiminde hesap-ÖZEL bellek-içi durumu sıfırlar (model TabCoordinator ömrü boyu yaşar → cross-account:
    /// sahte streak_break, yanlış pin, bayat coinBalance, A banner'ı). accountEpoch/checkInGeneration bump fence'ler.
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
        checkInClaimedPin = false // A'nın claim-pini B'nin meşru pre-claim status'ünü düşürmesin
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
