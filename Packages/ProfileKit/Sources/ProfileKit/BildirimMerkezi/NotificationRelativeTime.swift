import Foundation

/// `BildirimMerkezi` satır zaman damgasının göreli biçimi (02 §4.15: "başlık + gövde + zaman").
/// Saf/deterministik (test kancası: `now` enjekte edilir) — `RelativeDateTimeFormatter`'ın OS/locale'e
/// bağlı çıktısı yerine sabit Türkçe kova biçimi kullanır (snapshot-mantık testi stabil olsun).
///
/// Kovalar: `< 1 dk → "şimdi"`, `< 1 sa → "{n} dk"`, `< 1 g → "{n} sa"`, `< 1 hafta → "{n} g"`,
/// üzeri `"{n} hafta"`. Türkçe sayıdan sonra çoğul eki almaz (biçim tekil kalır). Gelecekteki tarih
/// (cihaz saati kayması) → "şimdi" (negatif süre gösterilmez).
enum NotificationRelativeTime {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * 60
    private static let day: TimeInterval = 24 * 60 * 60
    private static let week: TimeInterval = 7 * 24 * 60 * 60

    static func string(for date: Date, relativeTo now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= minute else { return "şimdi" } // < 1 dk veya gelecekteki tarih
        switch seconds {
        case ..<hour:
            return "\(Int(seconds / minute)) dk"
        case ..<day:
            return "\(Int(seconds / hour)) sa"
        case ..<week:
            return "\(Int(seconds / day)) g"
        default:
            return "\(Int(seconds / week)) hafta"
        }
    }
}
