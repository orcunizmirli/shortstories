import AppFoundation
@preconcurrency import GoogleMobileAds

/// SS-113 AdMob rewarded-ad merkezi yapılandırması + SDK başlatma (kompozisyon kökü). AdMob SDK tipleri
/// (`GADMobileAds`) yalnız App target'ında görünür; RewardsKit sağlayıcı-agnostik kalır (port arkası).
///
/// TODO(gerçek AdMob App ID/Unit ID): Aşağıdaki değerler Google'ın RESMİ TEST ID'leridir — dev'de uçtan
/// uca çalışır (SDK init crash etmez, test reklamı yüklenir/gösterilir), gerçek gelir ÜRETMEZ. Release
/// öncesi AdMob konsolundan alınan GERÇEK App ID + rewarded Ad Unit ID ile değiştirilecek (Yayıncı
/// Kimliği: pub-1147476807575834). `GADApplicationIdentifier` (Info.plist) bu App ID ile EŞLEŞMELİDİR —
/// eşleşmezse / eksikse SDK başlatmada CRASH eder.
enum AdMobConfiguration {
    /// AdMob App ID — Info.plist `GADApplicationIdentifier` ile AYNI olmalı. Şu an Google test App ID'si.
    /// TODO(gerçek AdMob App ID): AdMob konsolundan alınan `ca-app-pub-1147476807575834~XXXXXXXXXX`.
    static let applicationIdentifier = "ca-app-pub-3940256099942544~1458002511"

    /// Rewarded reklam birimi kimliği. Şu an Google resmi rewarded TEST unit'i (her zaman test reklamı döner).
    /// TODO(gerçek AdMob Unit ID): AdMob konsolundan alınan `ca-app-pub-1147476807575834/XXXXXXXXXX`.
    static let rewardedAdUnitID = "ca-app-pub-3940256099942544/1712485313"

    /// GoogleMobileAds SDK'sını BİR KEZ başlatır (app launch — `AppDelegate.didFinishLaunching`). Mediation
    /// adaptörleri hazır olunca `completionHandler` çağrılır; ilk reklam yüklemesi (`preload`) SDK'yı zaten
    /// tembel başlatır ama açık `start` başlatma gecikmesini önler. `GADApplicationIdentifier` (Info.plist)
    /// OLMADAN bu çağrı CRASH eder → test App ID Info.plist'te tanımlıdır.
    @MainActor
    static func start() {
        GADMobileAds.sharedInstance().start(completionHandler: nil)
    }
}
