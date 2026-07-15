import Foundation

/// Görev merkezi görevi (SS-112) — RewardsKit-sahipli SAF domain değeri; 05 §2.9 `Mission`
/// sözleşmesinin istemci karşılığı. Ağ/Codable kaygısı burada YOKTUR: App adaptörü `GET /missions`
/// JSON'ını bu tipe map eder (kalıp: LibraryKit `LibrarySeriesInfo`, ProfileKit `WalletSummary`).
///
/// DOĞRULUK KAYNAĞI SUNUCUDUR (06 §, R6): `state`/`progress` server-otoriterdir. `isClaimable`
/// yalnız `state == .claimable`'a bakar — istemci `progress >= target` görsün diye ASLA claim'i
/// açmaz (canlı ilerleme overlay'i yalnız görüntülemedir; fraud kontrolü backend'te, 07 §4.3).
public struct RewardTask: Sendable, Equatable, Identifiable {
    /// Görev tipi (05 §2.9 `Mission.Kind`). Bilinmeyen değer ileri-uyumlu `.unknown(raw)` olur ve
    /// listeden düşülür (`UnknownDecodable` kalıbının domain karşılığı, 07 §4.3).
    public enum Kind: Sendable, Equatable, Hashable {
        case watchMinutes
        case favoriteSeries
        case shareSeries
        case enableNotifications
        case linkAccount
        case watchAd
        case unknown(String)

        public init(rawValue: String) {
            switch rawValue {
            case "watchMinutes": self = .watchMinutes
            case "favoriteSeries": self = .favoriteSeries
            case "shareSeries": self = .shareSeries
            case "enableNotifications": self = .enableNotifications
            case "linkAccount": self = .linkAccount
            case "watchAd": self = .watchAd
            default: self = .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .watchMinutes: "watchMinutes"
            case .favoriteSeries: "favoriteSeries"
            case .shareSeries: "shareSeries"
            case .enableNotifications: "enableNotifications"
            case .linkAccount: "linkAccount"
            case .watchAd: "watchAd"
            case let .unknown(raw): raw
            }
        }

        /// Bilinen (görüntülenebilir) tip mi — bilinmeyen tipler listeden düşülür (07 §4.3).
        public var isKnown: Bool {
            if case .unknown = self {
                false
            } else {
                true
            }
        }

        /// Registry `mission_type` değeri (08 §3.5 taksonomisi) — mission lifecycle analitiğinin TEK
        /// eşleme noktası. Registry yalnız 4 tip tanır; karşılığı olmayan kind (`linkAccount`/`watchAd`/
        /// `unknown`) için `nil` → o görev için `mission_progress`/`mission_complete` GÖNDERİLMEZ (§2.3).
        var analyticsMissionType: String? {
            switch self {
            case .watchMinutes: RewardsAnalytics.MissionType.watchTime
            case .favoriteSeries: RewardsAnalytics.MissionType.favorite
            case .shareSeries: RewardsAnalytics.MissionType.share
            case .enableNotifications: RewardsAnalytics.MissionType.pushOptin
            case .linkAccount, .watchAd, .unknown: nil
            }
        }
    }

    /// Görev durumu — SERVER-otoriter (05 §2.9 `Mission.State`). `claimable`'ı YALNIZ sunucu yapar
    /// (`progress >= target` olduğunda). `locked` ön koşulu tamamlanmamış görev (07 §4.2 uzantısı).
    public enum State: Sendable, Equatable {
        case locked
        case inProgress
        case claimable
        case claimed
        case unknown

        public init(rawValue: String) {
            switch rawValue {
            case "locked": self = .locked
            case "inProgress": self = .inProgress
            case "claimable": self = .claimable
            case "claimed": self = .claimed
            default: self = .unknown
            }
        }
    }

    /// Yenilenme politikası (05 §2.9 `Mission.ResetPolicy`). Görsel vade notu bundan türetilir
    /// (`daily` claim-edilebilir → "bugün sona erer"), istemci saati OKUNMADAN (07 §4.2).
    public enum ResetPolicy: Sendable, Equatable {
        case daily
        case weekly
        case oneTime
        case unknown

        public init(rawValue: String) {
            switch rawValue {
            case "daily": self = .daily
            case "weekly": self = .weekly
            case "oneTime": self = .oneTime
            default: self = .unknown
            }
        }
    }

    /// Görev kartının görüntü durumu (kilitli/ilerliyor/tamamlandı-claim-edilebilir/claim-edildi).
    /// View bunu tam kapsamlı `switch`'ler; `.unknown` state güvenli varsayılan `.inProgress`'e düşer.
    public enum DisplayStatus: Sendable, Equatable {
        case locked
        case inProgress
        case claimable
        case claimed
    }

    public let id: String
    public let kind: Kind
    /// Sunucudan lokalize başlık (istemci lokalize ETMEZ — `Text(verbatim:)` ile render edilir).
    public let title: String
    /// Earned kesesine yazılacak ödül (server-otoriter).
    public let rewardCoins: Int
    /// Hedef değer (dakika, adet…).
    public let target: Int
    /// Mevcut ilerleme — SERVER hesaplar (doğruluk kaynağı; claim-edilebilirlik girdisi sunucuda).
    public let progress: Int
    public let state: State
    public let resetPolicy: ResetPolicy
    /// Görevin kendisinin bitiş zamanı (earned coin vadesi DEĞİL); yoksa nil.
    public let expiresAt: Date?

    public init(
        id: String,
        kind: Kind,
        title: String,
        rewardCoins: Int,
        target: Int,
        progress: Int,
        state: State,
        resetPolicy: ResetPolicy,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.rewardCoins = rewardCoins
        self.target = target
        self.progress = progress
        self.state = state
        self.resetPolicy = resetPolicy
        self.expiresAt = expiresAt
    }

    /// Aynı görevin `.claimed` kopyası (eventual-consistency guard: yerel claim kaydı korunur — server
    /// bayat `.claimable` döndürdüğünde satır `.claimed`'ten geri döndürülmez, 07 §4.2 idempotency).
    func markingClaimed() -> RewardTask {
        RewardTask(
            id: id,
            kind: kind,
            title: title,
            rewardCoins: rewardCoins,
            target: target,
            progress: progress,
            state: .claimed,
            resetPolicy: resetPolicy,
            expiresAt: expiresAt
        )
    }

    // MARK: - Saf türetimler (izole test edilir)

    /// Claim edilebilir mi — YALNIZ `state == .claimable` (SERVER-otoriter). İstemci ilerlemesi
    /// `target`'a ulaşsa bile sunucu onaylamadıkça claim AÇILMAZ (06 §, R6 para güvenliği).
    public var isClaimable: Bool {
        state == .claimable
    }

    /// İlerleme tamamlanma eşiği aşıldı mı (görsel; claim-edilebilirlik bu DEĞİL, `isClaimable`'dır).
    public var isComplete: Bool {
        Self.isComplete(progress: progress, target: target)
    }

    /// İlerleme yüzdesi (0...1, DSProgressBar girdisi).
    public var progressFraction: Double {
        Self.fraction(progress: progress, target: target)
    }

    /// Görüntü durumu (server `state`'inden saf eşleme).
    public var displayStatus: DisplayStatus {
        Self.displayStatus(for: state)
    }

    /// İlerleme yüzdesi (0...1). `target <= 0` ise ilerleme varsa 1, yoksa 0.
    public static func fraction(progress: Int, target: Int) -> Double {
        guard target > 0 else { return progress > 0 ? 1 : 0 }
        return min(max(Double(progress) / Double(target), 0), 1)
    }

    /// Tamamlanma eşiği: `progress >= target` (target > 0). `target <= 0` ise `progress > 0`.
    public static func isComplete(progress: Int, target: Int) -> Bool {
        target > 0 ? progress >= target : progress > 0
    }

    /// Server `state` → görüntü durumu. `.unknown` güvenli varsayılan `.inProgress` (claim-edilemez).
    public static func displayStatus(for state: State) -> DisplayStatus {
        switch state {
        case .locked: .locked
        case .inProgress, .unknown: .inProgress
        case .claimable: .claimable
        case .claimed: .claimed
        }
    }
}
