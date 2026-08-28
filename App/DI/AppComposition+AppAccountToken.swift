import AppFoundation
import Foundation

extension AppComposition {
    /// Kurulum-kararlı StoreKit `appAccountToken`'ı çözer (audit LOW): preferences'ta varsa onu kullan;
    /// yoksa üret + persist et → aynı kurulumun TÜM satın-almaları AYNI token'ı taşır (işlem→hesap
    /// attribution). Fresh `UUID()` her launch'ta değişip korelasyonu bozuyordu. `nonisolated`: yalnız
    /// preferences okur/yazar, actor state'e dokunmaz (init'ten senkron çağrılabilir, test-edilebilir).
    nonisolated static func resolveAppAccountToken(preferences: any PreferencesStoring) -> UUID {
        let key = PreferenceKey(name: "storekit.app_account_token", default: "")
        if let parsed = UUID(uuidString: preferences.value(for: key)) {
            return parsed
        }
        let token = UUID()
        preferences.set(token.uuidString, for: key)
        return token
    }
}
