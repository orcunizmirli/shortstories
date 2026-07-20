/// Rewarded ad SDK PORTU (SS-113, 06 §9.3 normatif sözleşme). RewardsKit yüzeyleri (UnlockSheet,
/// OdulMerkezi) yalnız bu protokolü görür; reklam SDK'sı tipleri (AdMob `GADRewardedAd` vb.) bu
/// imzalarda GÖRÜNEMEZ. Somut sağlayıcı (aktif aday: AdMob) port ARKASINA ertelenir ve DI
/// kompozisyonunda (App) bağlanır — sağlayıcı değişimi = yeni adaptör + DI; başka modül dokunmaz.
///
/// TODO(SS-113 prep): Gerçek `GADRewardedAd` adaptörü (`AdMobRewardedAdController`) App/AdBridge
/// altında bu porta uyar; AdMob SDK paketi + App-ID + SSV yapılandırması (06 §9.4) prep adımıdır.
/// Test/preview için `MockRewardedAdProvider` enjekte edilir.
///
/// `Sendable`: adaptör aktör-izole (AdMob sunumu MainActor) olabilir; async gereksinimleri
/// izole metotlarla karşılanır (çağrı `await` ile hop eder). `showAd()` sunum bağlamını (root VC)
/// adaptörün İÇİNDE çözer — port UIKit'e bağlanmaz.
public protocol RewardedAdProviding: Sendable {
    /// Ön-yükleme (06 §9.3): UnlockSheet gösterilmeden ÖNCE / OdulMerkezi kartı görünmeden tetiklenir
    /// (kilitli bölüme yaklaşırken prefetch sinyaliyle, 04) — yüzey açıldığında reklam hazır olsun.
    /// Yan etkisiz tekrar edilebilir; başarısız yükleme sessizce `isAdAvailable == false` bırakır.
    func preload() async

    /// Doldurma (fill) kontrolü: ön-yüklenmiş gösterime hazır reklam VAR mı. SAF okuma (SDK'yı
    /// başlatmaz) — `RewardedAdAvailability` kararının fill girdisi. Doldurma yoksa kart gizlenir (06 §9.5).
    func isAdAvailable() async -> Bool

    /// Reklamı gösterir ve sonucu döndürür (06 §9.3). Ödül YALNIZ 30 sn tamamlama şartı karşılanınca
    /// (sağlayıcının reward callback'i) `.completed(proof)` olur; erken kapatma `.dismissedEarly`
    /// (ödül YOK, hak düşmez). Kanıt (`RewardProof`) sağlayıcı-bağımsız zarftır; server SSV ile doğrular.
    func showAd() async -> AdWatchOutcome
}

/// Bir reklam gösterim turunun sonucu (06 §9.3). İstemci ödülü KENDİ vermez — `.completed` yalnız
/// server ad-unlock doğrulamasına (SSV) götüren kanıtı taşır; kredi/unlock kararı server-otoriterdir.
public enum AdWatchOutcome: Sendable, Equatable {
    /// 30 sn tamamlama şartı karşılandı (sağlayıcı reward callback'i). Taşınan `RewardProof` server'a
    /// iletilir; unlock/kredi server SSV doğrulamasından SONRA gerçekleşir (istemci KREDİ VERMEZ).
    case completed(RewardProof)
    /// Kullanıcı reklamı sonuna kadar izlemeden kapattı → ödül YOK, günlük hak düşmez (06 §9.3).
    case dismissedEarly
    /// Gösterim başarısız (SDK/sunum hatası) → ödül YOK.
    case failed
    /// Gösterilecek reklam yok (doldurma başarısız / envanter boş) → yüzey gizlenir/devre dışı (06 §9.5).
    case noFill
}

/// Sağlayıcı-bağımsız ödül kanıtı zarfı (06 §9.3, 05 §4.7). Server `provider` alanına göre doğrulayıcı
/// seçer (AdMob → SSV); kanıt opak `proofPayload` içinde taşınır. Sağlayıcı değişimi bu zarfı
/// DEĞİŞTİRMEZ — yalnız yeni `provider` değeri + server tarafında yeni doğrulayıcı eklenir.
public struct RewardProof: Sendable, Equatable {
    /// Aktif sağlayıcı kimliği (ör. "admob"). Server doğrulayıcı seçimi (05 §4.7 `proof.provider`).
    public let provider: String
    /// Tek kullanımlık idempotency anahtarı; sağlayıcının S2S callback'iyle eşleşir (05 §5.2, 06 §9.4).
    public let nonce: String
    /// Sağlayıcıya özgü opak kanıt alanları (05 §4.7 `proofPayload`). İstemci İÇERİĞİNİ yorumlamaz.
    public let proofPayload: [String: String]

    public init(provider: String, nonce: String, proofPayload: [String: String]) {
        self.provider = provider
        self.nonce = nonce
        self.proofPayload = proofPayload
    }
}
