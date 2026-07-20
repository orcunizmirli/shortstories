import AppFoundation
import Foundation

/// Rewarded ad köprüsü orkestrasyonu (SS-113). Ön-yükleme yönetimi + görünürlük kararı + izle→unlock
/// akışını koordine eder; provider (SDK portu), gateway (server ödül teyidi) ve A/B varyantı ENJEKTE
/// edilir. UnlockSheet (SS-114) ve OdulMerkezi reklam kartı bu servisi kullanır. @MainActor: reklam
/// sunumu ana-thread'dir ve akış UI-bitişiktir.
///
/// PARA GÜVENLİĞİ (06 §, R6): SERVER-OTORİTER. İstemci cap SAYMAZ, ödül KREDİLEMEZ, kilit AÇMAZ —
/// karar server'ındır. `.completed` yalnız server SSV doğrulamasına götüren kanıtı taşır; unlock/kredi
/// `AdUnlockGateway` yanıtından gelir. Erken kapatma / hata → ödül YOK. VIP reklamsızlığı korunur:
/// yüzeyi VIP'e `availability` gizler ve App VIP'e `preload` çağırmaz (zorunlu-reklam YOK).
@MainActor
public final class RewardedAdService {
    private let provider: any RewardedAdProviding
    private let gateway: any AdUnlockGateway
    private let analytics: any AnalyticsTracking
    private let variant: RewardedAdVariant

    public init(
        provider: any RewardedAdProviding,
        gateway: any AdUnlockGateway,
        analytics: any AnalyticsTracking,
        variant: RewardedAdVariant = .default
    ) {
        self.provider = provider
        self.gateway = gateway
        self.analytics = analytics
        self.variant = variant
    }

    /// Enjekte edilen A/B kolu (SS-154) — yüzey vurgusu/sıralaması için UnlockSheet okuyabilir (docs/08 E2).
    public var abVariant: RewardedAdVariant {
        variant
    }

    // MARK: - Ön-yükleme (06 §9.3)

    /// Reklamı ön-yükler (yüzey görünmeden ÖNCE). VIP'e ASLA çağrılmaz (App kompozisyonu; reklamsızlık).
    public func preload() async {
        await provider.preload()
    }

    // MARK: - Görünürlük (SAF karar + provider fill köprüsü)

    /// Yüzey görünürlüğünü çözer: VIP + A/B kolu ÜST kapılarını uygular, ardından provider doldurmasını
    /// (fill) okuyup SAF `RewardedAdAvailability` kararıyla birleştirir. `remaining`/`resetsAt` SERVER'dan
    /// gelir (istemci cap saymaz, 05 §963); `rewardedAdsEnabled` SS-024 remote flag, `isVIP` App'ten
    /// (WalletKit entitlement) enjekte edilir.
    ///
    /// VIP REKLAMSIZLIĞI (06 §9.5) + A/B kontrol kolu: yüzey hiç yoksa reklam SDK'sını YOKLAMA (VIP'e ad
    /// init yok, zorunlu-reklam YOK) — fill sorgusu yalnız yüzey gerçekten olabilirken yapılır.
    public func availability(
        rewardedAdsEnabled: Bool,
        isVIP: Bool,
        remaining: Int?,
        resetsAt: Date? = nil
    ) async -> RewardedAdAvailability {
        guard !isVIP, variant.surfaceEnabled else { return .hidden }
        let hasFill = await provider.isAdAvailable()
        return RewardedAdAvailability.evaluate(
            rewardedAdsEnabled: rewardedAdsEnabled,
            hasFill: hasFill,
            remaining: remaining,
            resetsAt: resetsAt
        )
    }

    // MARK: - İzle → unlock (server-otoriter, SSV)

    /// Reklamı gösterir ve 30 sn tamamlama şartı karşılanırsa server ad-unlock isteğini tetikler.
    /// Sonuç SERVER-OTORİTERdir — istemci kredi VERMEZ:
    /// - `.completed` → gateway `POST /rewards/ad-unlock` → başarı `.unlocked`, 429 `.capReached`,
    ///   SSV reddi `.rewardRejected`, transport hatası `.failed`.
    /// - `.dismissedEarly` → `.dismissedEarly` (ödül YOK, hak düşmez, fail event'i ATILMAZ — kullanıcı seçimi).
    /// - `.noFill` / `.failed` → aynı sonuç (ödül YOK).
    ///
    /// `dailyCap` (SS-024 config) yalnız analitik `daily_cap`/`ads_used_today` içindir; karar/cap
    /// server'ındır — `adsUsedToday` server'ın verdiği KALAN HAK'tan türetilir (istemci saymaz).
    public func watchAdToUnlock(
        target: AdRewardTarget,
        placement: RewardedAdPlacement,
        dailyCap: Int? = nil
    ) async -> AdUnlockResult {
        analytics.trackRewardedAdStart(placement: placement.rawValue, dailyCap: dailyCap)
        let outcome = await provider.showAd()
        switch outcome {
        case let .completed(proof):
            return await completeUnlock(target: target, proof: proof, placement: placement, dailyCap: dailyCap)
        case .dismissedEarly:
            // 30 sn şartı karşılanmadı → ödül YOK, hak düşmez (06 §9.3). Fail event'i atılmaz.
            return .dismissedEarly
        case .noFill:
            analytics.trackRewardedAdFail(placement: placement.rawValue, dailyCap: dailyCap)
            return .noFill
        case .failed:
            analytics.trackRewardedAdFail(placement: placement.rawValue, dailyCap: dailyCap)
            return .failed
        }
    }

    /// `.completed` sonrası server ödül teyidi. Kanıt zarfı gateway'e iletilir; sonuç server-otoriterdir.
    private func completeUnlock(
        target: AdRewardTarget,
        proof: RewardProof,
        placement: RewardedAdPlacement,
        dailyCap: Int?
    ) async -> AdUnlockResult {
        do {
            let result = try await gateway.requestAdUnlock(AdUnlockRequest(target: target, proof: proof))
            analytics.trackRewardedAdComplete(
                placement: placement.rawValue,
                adsUsedToday: Self.adsUsedToday(dailyCap: dailyCap, remaining: result.remainingToday),
                dailyCap: dailyCap
            )
            return .unlocked(result)
        } catch let AdUnlockError.capReached(resetsAt) {
            analytics.trackRewardedAdFail(placement: placement.rawValue, dailyCap: dailyCap)
            return .capReached(resetsAt: resetsAt)
        } catch AdUnlockError.rewardRejected {
            analytics.trackRewardedAdFail(placement: placement.rawValue, dailyCap: dailyCap)
            return .rewardRejected
        } catch {
            // Transport/ağ hatası: reklam izlendi ama teyit ulaşmadı. Kredi VERİLMEZ; S2S callback
            // geldiyse server yine işler, istemci snapshot'tan güncel durumu görür (06 §9.3/§9.4).
            analytics.trackRewardedAdFail(placement: placement.rawValue, dailyCap: dailyCap)
            return .failed
        }
    }

    /// Analitik `ads_used_today` = cap − kalan hak. SERVER'ın verdiği `remaining`'den TÜRETİLİR (istemci
    /// saymaz) ve yalnız RAPORLAMA içindir; her ikisi de bilinmiyorsa `nil` (event alanı eklenmez).
    private static func adsUsedToday(dailyCap: Int?, remaining: Int?) -> Int? {
        guard let dailyCap, let remaining else { return nil }
        return max(0, dailyCap - remaining)
    }
}

/// İzle→unlock akışının SERVER-OTORİTER sonucu (SS-113). İstemci bu sonuca göre UI'ı günceller;
/// kredi/unlock kararı `.unlocked` içindeki server yanıtındadır.
public enum AdUnlockResult: Sendable, Equatable {
    /// Server SSV doğruladı → kilit açıldı / coin verildi (server-otoriter `AdUnlockOutcome`).
    case unlocked(AdUnlockOutcome)
    /// Kullanıcı reklamı erken kapattı → ödül YOK, hak düşmez.
    case dismissedEarly
    /// Gösterilecek reklam yoktu → ödül YOK (yüzey doldurma-yok durumuna döner).
    case noFill
    /// Gösterim/transport hatası → ödül YOK.
    case failed
    /// Günlük cap doldu (429) → ödül YOK; yüzey capReached'e geçer. `resetsAt` server'dan.
    case capReached(resetsAt: Date?)
    /// Server kanıtı reddetti (SSV) → ödül YOK, kilit açılmaz.
    case rewardRejected
}

/// Rewarded ad yüzeyi (analitik `placement` boyutu, docs/08 §3.5). rawValue event parametresidir.
public enum RewardedAdPlacement: String, Sendable, Equatable {
    case unlockSheet = "unlock_sheet"
    case odulMerkezi = "odul_merkezi"
}
