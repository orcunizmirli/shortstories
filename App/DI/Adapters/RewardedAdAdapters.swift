import AppFoundation
import Foundation
import RewardsKit
import WalletKit

// SS-114 rewarded ad ile UnlockSheet açma — App kompozisyon kökündeki canlı köprüler. İki port ailesi
// birleşir: (1) RewardsKit `RewardedAdService` orkestrasyonu canlı `RewardedAdProviding` (AdMob TODO) +
// `AdUnlockGateway` (POST /rewards/ad-unlock) ile beslenir; (2) WalletKit-yerel `RewardedAdUnlocking`
// portu bu servisi UnlockSheet'e köprüler (WalletKit RewardsKit'i İMPORT ETMEZ — R2 feature izolasyonu).
//
// SERVER-OTORİTER (06 §9, R6): istemci cap saymaz/kredi vermez; karar server SSV'sindedir. VIP
// reklamsızlığı (06 §9.5) ve `ads.rewarded_enabled` bayrağı + A/B kolu adaptörde `availability`'den
// ÖNCE uygulanır (VIP'e reklam SDK'sı yoklanmaz / preload edilmez — zorunlu-reklam YOK).

// MARK: - WalletKit RewardedAdUnlocking ← RewardsKit RewardedAdService köprüsü

/// UnlockSheet reklam satırı portunun (WalletKit) canlı adaptörü: RewardsKit `RewardedAdService`'i sarar,
/// `isVIP`/`rewardedAdsEnabled`/`dailyCap`'i kompozisyon kökünden ENJEKTE eder ve RewardsKit karar/sonuç
/// tiplerini WalletKit-yerel tiplere eşler (saf `map` fonksiyonları izole test edilir).
struct RewardedAdUnlockingAdapter: WalletKit.RewardedAdUnlocking {
    /// `@MainActor` (dolayısıyla `Sendable`) orkestrasyon servisi — cross-actor `await` ile çağrılır.
    private let service: RewardsKit.RewardedAdService
    /// VIP durumu (canlı `WalletGateway`). VIP → reklamsız: preload no-op + availability gizli.
    private let isVIP: @Sendable () async -> Bool
    /// `ads.rewarded_enabled` ana şalteri (SS-024 remote flag). Kapalı → availability gizli.
    private let rewardedAdsEnabled: @Sendable () -> Bool
    /// Günlük cap (SS-024 `rewards.daily_ad_cap`, varsayılan 5) — yalnız GÖSTERİM ("Bugün N/M") + analitik;
    /// cap kararı server'ındır (istemci saymaz).
    private let dailyCap: @Sendable () -> Int?

    init(
        service: RewardsKit.RewardedAdService,
        isVIP: @escaping @Sendable () async -> Bool,
        rewardedAdsEnabled: @escaping @Sendable () -> Bool,
        dailyCap: @escaping @Sendable () -> Int?
    ) {
        self.service = service
        self.isVIP = isVIP
        self.rewardedAdsEnabled = rewardedAdsEnabled
        self.dailyCap = dailyCap
    }

    func preload() async {
        // VIP'e reklam init'i YOK (06 §9.5 reklamsızlık). `RewardedAdService.preload` VIP kontrolü yapmaz →
        // burada üst kapı: VIP kullanıcıya reklam SDK'sı ön-yüklenmez (zorunlu-reklam yok).
        guard await isVIP() == false else { return }
        await service.preload()
    }

    func availability() async -> WalletKit.RewardedAdUnlockAvailability {
        let vip = await isVIP()
        let decision = await service.availability(
            rewardedAdsEnabled: rewardedAdsEnabled(),
            isVIP: vip,
            // Server "kalan hak" ilk gösterimde ayrı endpoint'ten gelmiyor (bilinmiyor) → nil (satır etkin,
            // sayı gösterilmez). İşlem SONRASI kalan hak `watchAdToUnlock` yanıtından güncellenir.
            remaining: nil,
            resetsAt: nil
        )
        return Self.map(decision, dailyCap: dailyCap())
    }

    func watchAdToUnlock(episodeID: EpisodeID) async -> WalletKit.RewardedAdUnlockResult {
        let result = await service.watchAdToUnlock(
            target: .episode(id: episodeID.rawValue),
            placement: .unlockSheet,
            dailyCap: dailyCap()
        )
        return Self.map(result)
    }

    // MARK: - Saf eşlemeler (RewardsKit → WalletKit) — izole test

    /// RewardsKit görünürlük kararı → WalletKit satır durumu; `dailyCap` config'ten gösterime enjekte edilir.
    static func map(
        _ availability: RewardsKit.RewardedAdAvailability,
        dailyCap: Int?
    ) -> WalletKit.RewardedAdUnlockAvailability {
        switch availability {
        case let .available(remaining):
            .available(remaining: remaining, dailyCap: dailyCap)
        case let .capReached(resetsAt):
            .capReached(resetsAt: resetsAt, dailyCap: dailyCap)
        case .hidden:
            .hidden
        }
    }

    /// RewardsKit izle→unlock sonucu → WalletKit sonucu (server-otoriter `remainingToday` taşınır).
    static func map(_ result: RewardsKit.AdUnlockResult) -> WalletKit.RewardedAdUnlockResult {
        switch result {
        case let .unlocked(outcome):
            .unlocked(remainingToday: outcome.remainingToday)
        case .dismissedEarly:
            .dismissedEarly
        case .noFill:
            .noFill
        case .failed:
            .failed
        case let .capReached(resetsAt):
            .capReached(resetsAt: resetsAt)
        case .rewardRejected:
            .rewardRejected
        }
    }
}

// MARK: - Canlı AdUnlockGateway (POST /rewards/ad-unlock, SSV + Idempotency-Key)

/// RewardsKit `AdUnlockGateway` → `APIClient` (`POST /rewards/ad-unlock`, 05 §4.7). Sağlayıcı-bağımsız
/// kanıt zarfını gövdeye yazar; `Idempotency-Key` (UUID v4) header'da taşınır → APIClient yanıtsız isteği
/// AYNI anahtarla güvenle tekrarlar (server dedup, nonce eşlemesi). Kalıp: `APIRewardClaiming`.
///
/// SERVER-OTORİTER + SSV (06 §9.4): istemci client callback'ine güvenmez; server `provider`'a göre
/// doğrulayıcı seçer (AdMob → S2S imzalı callback), unlock + cap sayacını YAZAR. 429 → cap doldu,
/// 422 → kanıt reddi; diğer taşıma hataları `AppError` olarak yüzer (RewardedAdService `.failed`e çevirir).
struct APIAdUnlockGateway: AdUnlockGateway {
    private let client: any APIClientProtocol
    private let makeIdempotencyKey: @Sendable () -> String

    init(
        client: any APIClientProtocol,
        makeIdempotencyKey: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.client = client
        self.makeIdempotencyKey = makeIdempotencyKey
    }

    func requestAdUnlock(_ request: AdUnlockRequest) async throws -> AdUnlockOutcome {
        do {
            let wire = try await client.send(
                AdUnlockEndpoint(payload: AdUnlockRequestBody(request: request), key: makeIdempotencyKey())
            )
            // Server-otoriter snapshot: `target` istekle eşleşir (idempotent tekrar da aynısını döner);
            // `remainingToday`/`coinBalance` yalnız GÖSTERİM (istemci bunlarla cüzdanı mutasyona uğratmaz).
            return AdUnlockOutcome(
                target: request.target,
                remainingToday: wire.remainingToday,
                coinBalance: wire.wallet?.coinBalance
            )
        } catch AppError.network(.server(status: 429)) {
            // 429 AD_UNLOCK_CAP_REACHED (05 §4.7): günlük cap doldu. `resetsAt` gövdesi API katmanında
            // tipli taşınmadığından nil (UI "Yarın yeni hakların olacak"); ödül YOK.
            throw AdUnlockError.capReached(resetsAt: nil)
        } catch AppError.network(.server(status: 422)) {
            // 422: server SSV kanıtı reddetti (06 §9.4 sahte/eşleşmeyen kanıt) → kilit AÇILMAZ, ödül YOK.
            throw AdUnlockError.rewardRejected
        }
        // Diğer AppError (offline/timeout/5xx/…) YUKARI fırlar → `RewardedAdService` `.failed`e çevirir
        // (S2S callback gelirse server yine işler; istemci snapshot'tan güncel durumu görür, 06 §9.3).
    }
}

/// `POST /rewards/ad-unlock` — sağlayıcı-bağımsız kanıt + hedef (05 §4.7). Idempotent (key header'da).
private struct AdUnlockEndpoint: Endpoint {
    typealias Response = AdUnlockResponseWire

    let payload: AdUnlockRequestBody
    let key: String

    var path: String {
        "/rewards/ad-unlock"
    }

    var method: HTTPMethod {
        .post
    }

    var idempotencyKey: String? {
        key
    }

    var body: (any Encodable)? {
        payload
    }
}

/// İstek gövdesi (05 §4.7 sağlayıcı-bağımsız İÇ-İÇE zarf): hedef + opak kanıt alt-nesnesi (`proof`).
/// Kanıt (provider/nonce/proofPayload) `proof` altında toplanır — düzleştirilMEZ; aksi halde backend
/// `proof` nesnesini bulamaz → SSV doğrulayamaz → kilit AÇILMAZ. Spec `rewardType` alanı TANIMLAMAZ.
/// `episodeId`: `.episode` yolunda present (§4.7 örneği), `.coinReward` yolunda omit (opsiyonel nil →
/// synthesized `encodeIfPresent` ile alan taşınmaz; §4.7 coinReward'ı belgelemez, `proof` yine gönderilir).
private struct AdUnlockRequestBody: Encodable, Sendable {
    /// Sağlayıcı-bağımsız kanıt zarfı (05 §4.7 `proof` / 06 §9.3 `RewardProof`). `proofPayload` opak
    /// [String:String] (NORMATİF tip); istemci içeriğini yorumlamaz.
    struct Proof: Encodable, Sendable {
        let provider: String
        let nonce: String
        let proofPayload: [String: String]
    }

    let episodeId: String?
    let proof: Proof

    init(request: AdUnlockRequest) {
        switch request.target {
        case let .episode(id):
            episodeId = id
        case .coinReward:
            episodeId = nil
        }
        proof = Proof(
            provider: request.proof.provider,
            nonce: request.proof.nonce,
            proofPayload: request.proof.proofPayload
        )
    }
}

/// Yanıt zarfı (05 §4.7; `POST /wallet/unlock` ile aynı `wallet` kesesi). Tanınmayan alanlar yutulur.
private struct AdUnlockResponseWire: Decodable, Sendable {
    let remainingToday: Int?
    let wallet: WalletBalanceWire?
}

// MARK: - Yer tutucu reklam sağlayıcısı (AdMob prep TODO)

/// AdMob `AdMobRewardedAdController` bağlanana dek güvenli yer tutucu (SS-113 prep). Doldurma YOK →
/// `availability` her zaman `.hidden` (bayrak açık olsa bile reklam satırı görünmez); gösterim `.noFill`.
///
/// TODO(SS-113 prep): `RewardsKit/AdBridge` altında gerçek `GADRewardedAd` adaptörü (06 §9.3/§9.4:
/// SSV `serverSideVerificationOptions`, App-ID + AdMob SDK paketi + consent SS-156). Bu porta uyar; DI'da
/// bu yer tutucu onunla değiştirilir — başka modül dokunmaz (sağlayıcı-agnostik sözleşme).
struct PlaceholderRewardedAdProvider: RewardedAdProviding {
    func preload() async {}

    func isAdAvailable() async -> Bool {
        false // AdMob bağlanana dek envanter yok → satır gizli kalır (feature bayrağı açık olsa bile).
    }

    func showAd() async -> AdWatchOutcome {
        .noFill
    }
}
