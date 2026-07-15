/// Görev merkezi görsel hücresi (SS-112) — SAF görüntüleme değeri; `OdulMerkeziView` listeyi
/// doğrudan render eder. `RewardTaskCatalog.items(liveProgress:)` üretir; izole test edilir.
///
/// `displayedProgress` sunucu ilerlemesi (taban) ile canlı istemci-tarafı overlay'in birleşimidir
/// ve YALNIZ görüntülemedir; `status`/`isClaimable` server `state`'ine dayanır (06 §, R6).
public struct RewardTaskItem: Sendable, Equatable, Identifiable {
    /// Claim-edilebilir görevin gün/hafta sonu yanma uyarısı (07 §4.2 — sessiz yakma karanlık kalıp).
    /// İstemci saati OKUNMADAN `resetPolicy`'den türetilir.
    public enum ExpiryNote: Sendable, Equatable {
        case today
        case thisWeek
    }

    public let id: String
    public let kind: RewardTask.Kind
    public let title: String
    public let rewardCoins: Int
    public let target: Int
    /// Görüntülenen ilerleme = max(server ilerleme, canlı overlay), 0...target'a kırpılı (görüntüleme).
    public let displayedProgress: Int
    public let status: RewardTask.DisplayStatus
    public let resetPolicy: RewardTask.ResetPolicy

    public init(
        id: String,
        kind: RewardTask.Kind,
        title: String,
        rewardCoins: Int,
        target: Int,
        displayedProgress: Int,
        status: RewardTask.DisplayStatus,
        resetPolicy: RewardTask.ResetPolicy
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rewardCoins = rewardCoins
        self.target = target
        self.displayedProgress = displayedProgress
        self.status = status
        self.resetPolicy = resetPolicy
    }

    /// İlerleme yüzdesi (0...1, DSProgressBar).
    public var progressFraction: Double {
        RewardTask.fraction(progress: displayedProgress, target: target)
    }

    /// Görüntülenen ilerleme tamamlanma eşiğini aştı mı (GÖRSEL). Claim-edilebilirlik bu DEĞİL —
    /// canlı overlay eşiği doldursa bile claim `isClaimable` (server `state`) ile açılır (06 §, R6).
    public var isComplete: Bool {
        RewardTask.isComplete(progress: displayedProgress, target: target)
    }

    /// Claim edilebilir mi — server-otoriter görüntü durumundan (`isClaimable` server `state`'i taşır).
    public var isClaimable: Bool {
        status == .claimable
    }

    /// Vade uyarısı — yalnız claim-edilebilir görevde; `resetPolicy`'den saf (istemci saati YOK).
    public var expiryNote: ExpiryNote? {
        guard status == .claimable else { return nil }
        switch resetPolicy {
        case .daily: return .today
        case .weekly: return .thisWeek
        case .oneTime, .unknown: return nil
        }
    }
}

/// Görev kataloğunun SAF koleksiyon mantığı (SS-112, 07 §4): görünürlük filtresi (bilinmeyen tip
/// düşürme), canlı ilerleme birleşimi, claim-edilebilir sayısı/ödül toplamı ve "yeni tamamlanan"
/// tespiti. Yan etkisiz, izole test edilir. Katalog TAMAMEN backend'ten gelir — istemcide sabit
/// görev YOKTUR (07 §4.1); bu tip yalnız sunucudan gelen listeyi türetir.
public struct RewardTaskCatalog: Sendable, Equatable {
    public let tasks: [RewardTask]
    /// Rewarded ad kartı flag'i (`rewards.rewarded_ad_card_enabled`, F2/SS-113). KAPALI iken `watchAd`
    /// görevleri `visibleTasks`'ten düşer — F1'de kart gizli olduğundan görev de RENDER EDİLMEZ.
    public let rewardedAdEnabled: Bool

    public init(tasks: [RewardTask] = [], rewardedAdEnabled: Bool = true) {
        self.tasks = tasks
        self.rewardedAdEnabled = rewardedAdEnabled
    }

    /// Görüntülenebilir görevler — bilinmeyen tipler güvenle düşülür (ileri uyumluluk, 07 §4.3); ayrıca
    /// rewarded ad flag'i KAPALI iken `watchAd` görevleri de düşer (F2 gate, SS-113).
    public var visibleTasks: [RewardTask] {
        tasks.filter { $0.kind.isKnown && (rewardedAdEnabled || $0.kind != .watchAd) }
    }

    /// Claim-edilebilir görev sayısı (Ödüller sekme rozeti, 07 §4.4).
    public var claimableCount: Int {
        visibleTasks.filter(\.isClaimable).count
    }

    /// Şu an claim ile kazanılabilecek toplam coin (claim-edilebilir görevlerin ödül toplamı).
    public var claimableRewardTotal: Int {
        visibleTasks.filter(\.isClaimable).reduce(0) { $0 + $1.rewardCoins }
    }

    /// Canlı ilerleme overlay'ini (tipe göre, YALNIZ görüntüleme) birleştirip hücreleri türetir.
    /// Server ilerlemesi tabandır; overlay yalnız çubuğu daha tepkili ilerletir, claim'i AÇMAZ.
    public func items(liveProgress: [RewardTask.Kind: Int] = [:]) -> [RewardTaskItem] {
        visibleTasks.map { task in
            let merged = Self.mergedProgress(
                server: task.progress,
                live: liveProgress[task.kind],
                target: task.target
            )
            return RewardTaskItem(
                id: task.id,
                kind: task.kind,
                title: task.title,
                rewardCoins: task.rewardCoins,
                target: task.target,
                displayedProgress: merged,
                status: task.displayStatus,
                resetPolicy: task.resetPolicy
            )
        }
    }

    /// Önceki katalogda claim-edilebilir OLMAYAN ama şimdi olan görevler (`mission_complete` milestone'u).
    /// İlk yüklemede (`previous == nil`) baseline yoktur → boş (kalıp: `detectStreakBreak`).
    public func newlyClaimable(comparedTo previous: RewardTaskCatalog?) -> [RewardTask] {
        guard let previous else { return [] }
        let before = Dictionary(
            previous.visibleTasks.map { ($0.id, $0.isClaimable) },
            uniquingKeysWith: { first, _ in first }
        )
        return visibleTasks.filter { $0.isClaimable && before[$0.id] != true }
    }

    /// İlerlemesi %50 eşiğini İLK KEZ geçen görevler (`mission_progress` milestone'u, 08 §3.5 — hacim
    /// kontrolü: yalnız 50 checkpoint'i). Eşik SERVER ilerlemesinden türetilir (canlı overlay DEĞİL —
    /// doğruluk kaynağı sunucu). İlk yüklemede (`previous == nil`) baseline yoktur → boş.
    public func newlyHalfway(comparedTo previous: RewardTaskCatalog?) -> [RewardTask] {
        guard let previous else { return [] }
        let before = Dictionary(
            previous.visibleTasks.map { ($0.id, Self.hasReachedHalfway($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        return visibleTasks.filter { Self.hasReachedHalfway($0) && before[$0.id] != true }
    }

    /// Görev SERVER ilerlemesi %50 eşiğini aştı mı (mission_progress girdisi; görüntü overlay'i değil).
    static func hasReachedHalfway(_ task: RewardTask) -> Bool {
        task.progressFraction >= 0.5
    }

    /// Görüntülenen ilerleme birleşimi: server tabanı ile canlı overlay'in maksimumu, 0...target'a
    /// kırpılı (`target <= 0` ise kırpma yok). Monotonik-artan bir metrik varsayar.
    static func mergedProgress(server: Int, live: Int?, target: Int) -> Int {
        let base = max(server, 0)
        let candidate = max(base, live ?? base)
        guard target > 0 else { return candidate }
        return min(candidate, target)
    }
}
