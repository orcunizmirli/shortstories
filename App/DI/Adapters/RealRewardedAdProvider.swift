import AppFoundation
import Foundation
@preconcurrency import GoogleMobileAds
import RewardsKit
import UIKit

/// SS-113 GERÇEK AdMob rewarded-ad adaptörü — RewardsKit `RewardedAdProviding` portunun canlı
/// uygulaması. AdMob `GADRewardedAd`'i port ARKASINA kapatır: SDK tipleri (`GADRewardedAd`,
/// `GADFullScreenContentDelegate`) BU sınıfın dışına çıkmaz; RewardsKit yalnız `AdWatchOutcome` görür.
///
/// `@MainActor`: AdMob yükleme/sunumu ana-thread sözleşmesidir (`present ... Must be called on the main
/// thread`). Tek reklam örneği (`loadedAd`) saklanır; sunum sonrası tek-kullanımlık atılır ve bir sonraki
/// yüzey için yeniden ön-yüklenir (envanter sheet'ler arası hazır).
///
/// SERVER-OTORİTER + SSV (06 §9.3/§9.4): İstemci ödülü KENDİ vermez. `.completed` yalnız server ad-unlock
/// SSV doğrulamasına götüren KANIT ZARFINI taşır. AdMob'da kanıt SERVER-taraflıdır: Google, reklam
/// tamamlanınca yayıncının SSV callback URL'ine (backend) imzalı bir istek gönderir — client'ta imzalı
/// payload BULUNMAZ. Bu yüzden `RewardProof.proofPayload` boştur; korelasyon `nonce` üzerinden yapılır:
/// `GADServerSideVerificationOptions.customRewardString = nonce` set edilir, aynı `nonce` gövdeyle
/// backend'e gider (APIAdUnlockGateway) → backend, Google'ın SSV callback'indeki `custom_data`
/// (customRewardString) ile bu `nonce`'u eşleştirip unlock'ı YAZAR. `userIdentifier` cihaz/kullanıcı
/// kimliğidir (SSV `user_id` parametresi).
///
/// TODO(backend SSV correlation): (1) `userIdentifier` şu an cihaz `identifierForVendor` — SS-021 backend
/// userId bağlanınca gerçek kullanıcı kimliğiyle değiştirilecek (kompozisyon kökünden enjekte). (2) Backend
/// `POST /rewards/ad-unlock` nonce'u Google SSV callback `custom_data`'sıyla korele etmeli; client-teslim
/// `.completed` TEK BAŞINA kredi vermez (server, SSV callback'i gelmeden unlock yazmaz — 06 §9.4).
@MainActor
final class RealRewardedAdProvider: NSObject, RewardedAdProviding {
    /// Ön-yüklenmiş, gösterime hazır tek reklam (tek-kullanımlık). `nil` → doldurma yok (`isAdAvailable` false).
    private var loadedAd: GADRewardedAd?
    /// Aktif sunumu `showAd() async`'e köprüleyen devamlılık — delegate/reward callback'leri buradan çözer.
    /// `nil` → sunum aktif değil (çift-resume koruması: yalnız ilk terminal callback resume eder).
    private var presentation: CheckedContinuation<AdWatchOutcome, Never>?
    /// Aktif sunumun ödül-korelasyon nonce'u (SSV `customRewardString`). Ödül kazanılırsa `RewardProof`e taşınır.
    private var activeNonce: String?
    /// `userDidEarnRewardHandler` tetiklendi mi (30 sn tamamlama). Dismiss'te `.completed` vs `.dismissedEarly` ayrımı.
    private var didEarnReward = false
    /// Devam eden bir `GADRewardedAd.load` var mı — eşzamanlı preload'ların İKİ yükleme ateşleyip birini
    /// leak etmesini önler (yalnız `loadedAd == nil` yetmez: load `await` sırasında loadedAd hâlâ nil'dir).
    private var isLoading = false

    private let logger = OSLogger(category: "AdMob")

    // MARK: - RewardedAdProviding

    /// Reklamı ön-yükler (yüzey açılmadan ÖNCE). Zaten yüklüyse no-op (yan etkisiz tekrar). Yükleme
    /// başarısızsa `loadedAd` `nil` kalır → sessizce `isAdAvailable == false` (yüzey gizlenir, 06 §9.5).
    func preload() async {
        guard loadedAd == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            loadedAd = try await GADRewardedAd.load(
                withAdUnitID: AdMobConfiguration.rewardedAdUnitID,
                request: GADRequest()
            )
        } catch {
            // Doldurma yok / ağ hatası: sessiz. PII kuralı — hata gövdesi loglanmaz, yalnız kilometre taşı.
            loadedAd = nil
            logger.info("admob: rewarded preload doldurma yok")
        }
    }

    /// Saf okuma: gösterime hazır ön-yüklenmiş reklam VAR mı (SDK'yı başlatmaz). Fill kararının girdisi.
    func isAdAvailable() async -> Bool {
        loadedAd != nil
    }

    /// Reklamı gösterir ve sonucu `AdWatchOutcome`'a köprüler. Yüklü reklam yoksa `.noFill`; sunum bağlamı
    /// (root VC) çözülemezse `.failed`. Ödül kazanılıp kapatılırsa `.completed(proof)`, erken kapatma
    /// `.dismissedEarly`, sunum hatası `.failed`. Reklam tek-kullanımlıktır → sunum sonrası yeniden yüklenir.
    func showAd() async -> AdWatchOutcome {
        // Yeniden-giriş koruması: bir sunum zaten aktifken (continuation askıda) ikinci showAd saklanan
        // continuation'ı EZER → ilk çağrı sonsuza askıda kalır + ödül nonce'u çapraz-bağlanır. @MainActor,
        // `present` altındaki `await` suspension'ında reentrancy gerçektir (loadedAd sunum sırasında preload
        // ile yeniden dolabilir), bu yüzden loadedAd DEĞİL, aktif-sunum kapısı kullanılır — envanter tüketilmez.
        guard presentation == nil else { return .failed }
        guard let ad = loadedAd else { return .noFill }
        loadedAd = nil // tek-kullanımlık: present edilen reklam yeniden gösterilemez.

        guard let root = Self.rootViewController() else {
            logger.error("admob: root view controller çözülemedi → gösterim başarısız")
            // Reklam harcanmadı sayılır; bir sonraki fırsat için yeniden yükle.
            Task { await preload() }
            return .failed
        }

        let nonce = UUID().uuidString
        activeNonce = nonce
        didEarnReward = false

        // SSV korelasyonu: customRewardString = nonce (backend Google SSV callback'iyle eşler);
        // userIdentifier = cihaz/kullanıcı kimliği (SSV `user_id`). Sunumdan ÖNCE set edilmeli.
        let options = GADServerSideVerificationOptions()
        options.customRewardString = nonce
        options.userIdentifier = Self.userIdentifier()
        ad.serverSideVerificationOptions = options
        ad.fullScreenContentDelegate = self

        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<AdWatchOutcome, Never>) in
            presentation = continuation
            ad.present(fromRootViewController: root) { [weak self] in
                // 30 sn tamamlama şartı karşılandı (Google reward callback'i). Ödül kararı yine server SSV'de;
                // burada yalnız dismiss'te `.completed` üretmek için işaretlenir (istemci KREDİ VERMEZ).
                self?.didEarnReward = true
            }
        }

        // Sonraki yüzey için envanteri yeniden hazırla (VIP'e ulaşmaz — VIP'te showAd hiç çağrılmaz).
        Task { await preload() }
        return outcome
    }

    // MARK: - Yardımcılar

    /// Sunum bağlamı: anahtar pencerenin EN ÜSTTEKİ sunulan view controller'ı. UnlockSheet MODAL sunulduğu
    /// için taban root zaten bir sunum yapıyordur (`presentedViewController != nil`) → reklam TABAN root'tan
    /// present edilirse UIKit ikinci sunumu reddeder (`didFailToPresent` → `.failed`, reklamla kilit HİÇ
    /// açılmaz). Bu yüzden sunulan zincirin en üstüne inilir. Port UIKit'e bağlanmaz → çözüm ADAPTÖR içinde.
    private static func rootViewController() -> UIViewController? {
        guard let keyRoot = keyWindowRoot() else { return nil }
        return topmostViewController(from: keyRoot)
    }

    /// Anahtar pencerenin TABAN root view controller'ı (sunulan modal'a henüz inilmemiş).
    private static func keyWindowRoot() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    /// Sunulan (`presentedViewController`) zincirinin en üstüne iner — reklam, o an ekranda sunum yapan
    /// (UnlockSheet gibi) VC'nin üstünden present edilmeli; taban root'tan present "sunum devam ederken"
    /// hatası verir. Test edilebilir saf fonksiyon (izole `topmostViewController(from:)` suite'i).
    static func topmostViewController(from base: UIViewController) -> UIViewController {
        var top = base
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// SSV `user_id` — şu an cihaz kimliği (best-effort). TODO(backend SSV correlation): SS-021 backend
    /// userId ile değiştirilecek (kompozisyon kökünden enjekte; kullanıcı-bazlı cap/dedup için gerçek kimlik).
    private static func userIdentifier() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    /// Devamlılığı TEK KEZ çözer (çift-resume koruması: ilk terminal callback kazanır, sonrakiler no-op).
    private func finish(_ outcome: AdWatchOutcome) {
        guard let continuation = presentation else { return }
        presentation = nil
        activeNonce = nil
        didEarnReward = false
        continuation.resume(returning: outcome)
    }
}

// MARK: - GADFullScreenContentDelegate (sunum yaşam döngüsü → AdWatchOutcome)

// `@preconcurrency`: GADFullScreenContentDelegate `nonisolated` (ObjC) sözleşmedir; SDK bu callback'leri
// ana-thread'de çağırır → `@MainActor` metotlarla karşılamak güvenlidir (runtime izolasyon kontrolü).
extension RealRewardedAdProvider: @preconcurrency GADFullScreenContentDelegate {
    /// Sunum başarısız (SDK/sunum hatası) → ödül YOK. Reklam harcandı; bir sonraki için `showAd` yeniden yükler.
    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        logger.error("admob: rewarded sunum başarısız")
        finish(.failed)
    }

    /// Reklam kapandı. Ödül kazanıldıysa `.completed` (kanıt zarfı: nonce ile SSV korelasyonu, boş payload);
    /// aksi halde erken kapatma → `.dismissedEarly` (ödül YOK, hak düşmez).
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        if didEarnReward, let nonce = activeNonce {
            finish(.completed(RewardProof(provider: "admob", nonce: nonce, proofPayload: [:])))
        } else {
            finish(.dismissedEarly)
        }
    }
}
