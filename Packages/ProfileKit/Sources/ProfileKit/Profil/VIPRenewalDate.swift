import Foundation

/// VIP yenileme tarihini uygulama diline (SS-161) göre biçimlendiren SAF, izole test edilebilir
/// yardımcı. Cihaz `Locale.current` yerine seçili UYGULAMA DİLİ kullanılır (review #13): tarih,
/// uygulamanın gösterildiği dile göre render edilmelidir, cihaz bölgesine göre değil.
enum VIPRenewalDate {
    static func text(_ date: Date, appLanguage: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage.code)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
