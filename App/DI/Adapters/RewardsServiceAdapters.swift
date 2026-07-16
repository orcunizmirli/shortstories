import AppFoundation
import Foundation
import RewardsKit

// RewardsKit server-otoriter portlarının canlı adaptörleri (SS-111/112, R8). Portlar RewardsKit'te
// tanımlı (tüketici); App onları `APIClient`'a (üretici) köprüler ve JSON ↔ SAF domain (`CheckInState`/
// `RewardTask`) eşlemesini yapar. RewardsKit ağ/JSON/UUID/timezone GÖRMEZ.
//
// TRANSPORT ayrıntıları (05 §9) adaptördedir: her claim POST'u `Idempotency-Key` (UUID v4) taşır →
// APIClient yanıtsız claim'i AYNI anahtarla güvenle tekrarlar (server dedup). IANA timezone artık claim
// gövdesinde DEĞİL, `X-Timezone` header'ında ve HER istekte gönderilir (05 §2.9; `TimezoneInterceptor`,
// Support/) — sunucu "bugün" penceresini buradan çözer (cihaz saatinden türetilmez), GET okumalar dahil.

// MARK: - Check-in (GET /rewards/checkin, POST /rewards/checkin/claim)

/// RewardsKit `CheckInService` → `APIClient`. 409 ALREADY_CLAIMED: APIClient gövdeyi tipli hataya
/// çevirmeden `.network(.server(status: 409))` yüzdürdüğü için adaptör TAZE durumu ayrı `status()`
/// ile çeker ve `CheckInClaimError.alreadyClaimed(fresh)`'e sarar (model sessizce senkronlar).
struct APICheckInService: CheckInService {
    private let client: any APIClientProtocol
    private let makeIdempotencyKey: @Sendable () -> String

    init(
        client: any APIClientProtocol,
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.client = client
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    func status() async throws -> CheckInState {
        try await client.send(CheckInStatusEndpoint()).state
    }

    func claim() async throws -> CheckInClaimResult {
        do {
            return try await client.send(
                CheckInClaimEndpoint(key: makeIdempotencyKey())
            ).result
        } catch AppError.network(.server(status: 409)) {
            // Bugün zaten alınmış: taze durumu çek, sessiz senkron için sar.
            let fresh = try await status()
            throw CheckInClaimError.alreadyClaimed(fresh)
        }
    }
}

private struct CheckInStatusEndpoint: Endpoint {
    typealias Response = CheckInStateWire

    var path: String {
        "/rewards/checkin"
    }

    var method: HTTPMethod {
        .get
    }
}

private struct CheckInClaimEndpoint: Endpoint {
    typealias Response = CheckInClaimResultWire

    let key: String

    var path: String {
        "/rewards/checkin/claim"
    }

    var method: HTTPMethod {
        .post
    }

    /// Gövde YOK: timezone artık `X-Timezone` header'ındadır (`TimezoneInterceptor`); idempotency key
    /// header ile taşınır. Sunucu bugün penceresini header'dan çözer.
    var idempotencyKey: String? {
        key
    }
}

// MARK: - Görev kataloğu + claim (GET /missions, POST /missions/{id}/claim)

/// RewardsKit `TaskCatalogProviding` → `APIClient` (`GET /missions`). Bilinmeyen `kind`/`state`
/// ileri-uyumlu `.unknown`'a düşürülür (wire → domain eşlemesinde `rawValue` init'leri).
struct APITaskCatalogProvider: TaskCatalogProviding {
    private let client: any APIClientProtocol

    init(client: any APIClientProtocol) {
        self.client = client
    }

    func tasks() async throws -> [RewardTask] {
        try await client.send(MissionsEndpoint()).missions.map(\.task)
    }
}

/// RewardsKit `RewardClaiming` → `APIClient` (`POST /missions/{id}/claim`). 409 MISSION_NOT_CLAIMABLE:
/// taze kataloğu çekip görevi bulur ve `RewardClaimError.notClaimable(fresh)`'e sarar; katalogda
/// görev kaybolmuşsa (nadir) taşıma hatası yüzer.
struct APIRewardClaiming: RewardClaiming {
    private let client: any APIClientProtocol
    private let makeIdempotencyKey: @Sendable () -> String

    init(
        client: any APIClientProtocol,
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.client = client
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    func claimTask(id: String) async throws -> RewardTaskClaimResult {
        do {
            return try await client.send(
                MissionClaimEndpoint(missionID: id, key: makeIdempotencyKey())
            ).result
        } catch AppError.network(.server(status: 409)) {
            let fresh = try await client.send(MissionsEndpoint()).missions.map(\.task)
            guard let task = fresh.first(where: { $0.id == id }) else { throw AppError.network(.server(status: 409)) }
            // Taze görev sunucu-otoriter durumu taşır (`.claimed`/claim-edilemez); model sessiz senkronlar.
            throw RewardClaimError.notClaimable(task)
        }
    }
}

private struct MissionsEndpoint: Endpoint {
    typealias Response = MissionListWire

    var path: String {
        "/missions"
    }

    var method: HTTPMethod {
        .get
    }
}

private struct MissionClaimEndpoint: Endpoint {
    typealias Response = MissionClaimResultWire

    let missionID: String
    let key: String

    var path: String {
        "/missions/\(missionID.pathSegmentEscaped)/claim"
    }

    var method: HTTPMethod {
        .post
    }

    /// Gövde YOK: timezone `X-Timezone` header'ında (`TimezoneInterceptor`), idempotency key header ile.
    var idempotencyKey: String? {
        key
    }
}

// MARK: - Wire ↔ domain eşlemeleri

// (`String.pathSegmentEscaped` App-yerel yardımcısı `Support/HTTPWire.swift`'te tanımlıdır.)

struct CheckInStateWire: Decodable, Sendable {
    let cycleDay: Int
    let todayClaimed: Bool
    let todayReward: Int
    let schedule: [DayRewardWire]
    let streakDays: Int
    let streakBonusAt: Int?
    let streakBonusCoins: Int?

    struct DayRewardWire: Decodable, Sendable {
        let day: Int
        let coins: Int
        let claimed: Bool
    }

    var state: CheckInState {
        CheckInState(
            cycleDay: cycleDay,
            todayClaimed: todayClaimed,
            todayReward: todayReward,
            schedule: schedule.map { CheckInState.DayReward(day: $0.day, coins: $0.coins, claimed: $0.claimed) },
            streakDays: streakDays,
            streakBonusAt: streakBonusAt,
            streakBonusCoins: streakBonusCoins
        )
    }
}

/// Cüzdanın claim-sonrası server-otoriter durumu (05 §2.5 / §4.7 `wallet`). `coinBalance` bu iki
/// keseden TÜRETİLİR (05 §2.5: toplam = satın alınan + kazanılan); istemci başka türlü hesaplamaz.
/// Tanınmayan ek alanlar (`version`, `earnedExpiringSoon`, ...) yutulur (05 §1 kural 10).
struct WalletBalanceWire: Decodable, Sendable {
    let purchasedCoins: Int
    let earnedCoins: Int

    var coinBalance: Int {
        purchasedCoins + earnedCoins
    }
}

/// Claim'de kredilenen ödül (05 §4.7 `reward{coins,bucket,expiresAt}`). Wire'da `isStreakBonus` alanı
/// YOKTUR — domain bayrağı `bucket`ten türetilir: standart `earned`/`purchased` bucket'ları düzenli
/// ödüldür (false); sunucu bir streak bonusunu ayrı bucket ile işaretlerse true. `bucket` opsiyonel
/// tutulur ki eksik/tanınmayan değer decode'u ÇÖKERTMESİN (05 §1 kural 10).
/// TODO(SS-11x, RewardsKit/sözleşme): 7. gün streak bonusu sözleşmede ayrı bir sinyal taşımıyor
/// (`bucket` her zaman "earned"). Analitik `is_streak_bonus` daima false kalır; gerçek 7. gün tespiti
/// ya sözleşmeye ayrı alan/bucket eklenmesini ya da `checkin` state'inden türetmeyi gerektirir (RewardsKit
/// `RewardTaskClaimResult`/model dokunuşu — bu PR kapsamı dışı: App yalnız).
struct ClaimedRewardWire: Decodable, Sendable {
    let coins: Int
    let bucket: String?
    let expiresAt: Date?

    /// Streak bonusunu işaretleyen (varsayımsal) ayrı bucket değeri; standart keseler bunun dışındadır.
    static let streakBonusBucket = "streakBonus"

    var reward: ClaimedReward {
        ClaimedReward(coins: coins, isStreakBonus: bucket == Self.streakBonusBucket, expiresAt: expiresAt)
    }
}

struct CheckInClaimResultWire: Decodable, Sendable {
    let reward: ClaimedRewardWire
    let checkin: CheckInStateWire
    let wallet: WalletBalanceWire

    var result: CheckInClaimResult {
        // Server-otoriter bakiye: üst-seviye `coinBalance` YOK; `wallet` kesesinden türetilir.
        CheckInClaimResult(reward: reward.reward, checkin: checkin.state, coinBalance: wallet.coinBalance)
    }
}

struct MissionWire: Decodable, Sendable {
    let id: String
    let kind: String
    let title: String
    let rewardCoins: Int
    let target: Int
    let progress: Int
    let state: String
    let resetPolicy: String
    let expiresAt: Date?

    var task: RewardTask {
        RewardTask(
            id: id,
            kind: RewardTask.Kind(rawValue: kind),
            title: title,
            rewardCoins: rewardCoins,
            target: target,
            progress: progress,
            state: RewardTask.State(rawValue: state),
            resetPolicy: RewardTask.ResetPolicy(rawValue: resetPolicy),
            expiresAt: expiresAt
        )
    }
}

/// `GET /missions` yanıt zarfı (05 satır 941: `{ "missions": [Mission, ...] }`).
struct MissionListWire: Decodable, Sendable {
    let missions: [MissionWire]
}

struct MissionClaimResultWire: Decodable, Sendable {
    let reward: ClaimedRewardWire
    let mission: MissionWire
    let wallet: WalletBalanceWire

    var result: RewardTaskClaimResult {
        // Server-otoriter bakiye: üst-seviye `coinBalance` YOK; `wallet` kesesinden türetilir.
        RewardTaskClaimResult(reward: reward.reward, task: mission.task, coinBalance: wallet.coinBalance)
    }
}
