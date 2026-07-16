import AppFoundation
import AppTrackingTransparency
import ProfileKit
import UserNotifications

// SS-064 / SS-156 — Onboarding izin adımının DIŞ SİSTEM portları. Kanon §2 (StoreKit/AppleSignIn
// sarmalı kalıbı): `UNUserNotificationCenter` (bildirim izni) ve `ATTrackingManager` (App Tracking
// Transparency) doğrudan model'e değil, App'te tanımlı bu dar portlar arkasına alınır → `OnboardingModel`
// testleri gerçek sistem izni OLMADAN (fake port'larla) koşar. Canlı sarmalar App kompozisyon kökünde
// (`AppComposition.makeOnboardingModel`) bağlanır.

// MARK: - Bildirim izni (SS-140 tetikleyicisi — istem Onboarding'den gelir)

/// Sistem bildirim izni İSTEME portu (SS-140; 01 ONB-05). `NotificationPermissionStatusProviding`
/// (ProfileKit — Ayarlar salt-OKUMA) ile karıştırılmamalı: bu port sistem diyaloğunu TETİKLER ve
/// sonucu döner. İstem yalnız uygulama-içi ön-izin ("Şimdi değil" değilse) sonrası çağrılır — hak
/// yakılmaz (01 ONB-05 kabul kriteri).
public protocol NotificationAuthorizationRequesting: Sendable {
    /// Sistem bildirim izni diyaloğunu sunar ve sonucu döner. Zaten belirlenmişse sistem yeni diyalog
    /// göstermeden mevcut kararı döndürür.
    func requestAuthorization() async -> NotificationAuthorizationResult
}

/// Bildirim izni sistem diyaloğu sonucu — analitiğe `grant`/`deny` olarak yansır (08 §3.1).
public enum NotificationAuthorizationResult: Sendable, Equatable {
    case granted
    case denied
}

/// Canlı `UNUserNotificationCenter` sarması. Durumsuzdur → `Sendable`.
public struct LiveNotificationAuthorizationRequester: NotificationAuthorizationRequesting {
    public init() {}

    public func requestAuthorization() async -> NotificationAuthorizationResult {
        let center = UNUserNotificationCenter.current()
        let granted = await (try? center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted ? .granted : .denied
    }
}

// MARK: - App Tracking Transparency (SS-156)

/// ATT istemi portu (SS-156; 08 §9.1). İstem YALNIZ Onboarding'de, değer önerisinden sonra ve remote
/// config bayrağı açıkken sunulur; sistem diyaloğu yaşam boyu yalnız bir kez gösterilebilir → model
/// önce `currentStatus`'u okuyup yalnız `.notDetermined` iken `requestAuthorization()` çağırır.
public protocol AppTrackingRequesting: Sendable {
    /// Anlık ATT yetki durumu (senkron okuma) — model istem gösterip göstermeyeceğine bununla karar verir.
    var currentStatus: AppTrackingAuthorizationResult { get }
    /// ATT sistem diyaloğunu sunar ve sonucu döner.
    func requestAuthorization() async -> AppTrackingAuthorizationResult
}

/// ATT yetki durumu — analitik `action` alanına `authorized|denied|restricted|not_determined` map edilir (08 §3.1/§9.1).
public enum AppTrackingAuthorizationResult: Sendable, Equatable {
    case authorized
    case denied
    case restricted
    case notDetermined

    /// `onboarding_att_prompt.action` kanonik değeri (08 §3.1) — snake_case.
    public var analyticsAction: String {
        switch self {
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .notDetermined: "not_determined"
        }
    }

    init(_ status: ATTrackingManager.AuthorizationStatus) {
        switch status {
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .notDetermined: self = .notDetermined
        @unknown default: self = .notDetermined
        }
    }
}

/// Canlı `ATTrackingManager` sarması. Durumsuzdur → `Sendable`.
public struct LiveAppTrackingRequester: AppTrackingRequesting {
    public init() {}

    public var currentStatus: AppTrackingAuthorizationResult {
        AppTrackingAuthorizationResult(ATTrackingManager.trackingAuthorizationStatus)
    }

    public func requestAuthorization() async -> AppTrackingAuthorizationResult {
        await withCheckedContinuation { continuation in
            ATTrackingManager.requestTrackingAuthorization { status in
                continuation.resume(returning: AppTrackingAuthorizationResult(status))
            }
        }
    }
}

// MARK: - Dil yazma portu (SS-161)

/// Onboarding dil-seçimi YAZMA portu — canlı uygulama ProfileKit `LanguagePreferenceService`'e bağlanır
/// (kanon: "seçim LanguagePreferenceService'e yazılır"). Model dar port'u alır (interface segregation);
/// `LanguagePreferenceService` zaten aynı imzayı taşıdığından retroaktif olarak uyar (aşağıda).
public protocol OnboardingLanguageWriting: Sendable {
    /// Uygulama dilini ayarlar; değer gerçekten değiştiyse `true` döner.
    @discardableResult
    func setAppLanguage(_ value: AppLanguage) -> Bool
}

extension LanguagePreferenceService: OnboardingLanguageWriting {}

// MARK: - Tercih anahtarları + flag

/// Onboarding-özel UserDefaults anahtarları (03 §9). Onboarding-tamamlandı bayrağı kanonik olarak
/// `PreferenceKeys.onboardingCompleted`tir (AppFoundation) — Faz 2 launch routing onu okur.
public enum OnboardingPreferenceKeys {
    /// Tür tercihi — virgülle ayrılmış genre ID'leri (ilk For You sinyali; 01 ONB-04). Atlanırsa boş kalır.
    public static let selectedGenres = PreferenceKey(name: "onboarding.selected_genres", default: "")
}

/// Onboarding remote-config flag'leri (03 §11, 08 §9.1).
public enum OnboardingFlags {
    /// ATT istemi Onboarding'de gösterilsin mi (08 §9.1 kararı): Faz 1'de üçüncü taraf reklam SDK'sı
    /// olmadığından VARSAYILAN KAPALI; Faz 2 (AdMob) öncesinde remote config ile açılır. Kapalıyken
    /// `onboarding_att_prompt` hiç üretilmez.
    public static let attPromptEnabled = FlagKey(name: "onboarding.att_prompt_enabled", default: false)
}
