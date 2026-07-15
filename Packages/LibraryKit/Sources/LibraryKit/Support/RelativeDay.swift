import Foundation

/// "Devam Et" kartındaki son izleme zamanı etiketinin SAF türetimi (02 §4.12: "dün").
/// Takvim günü farkına indirger; lokalize metni View çizer (tip yalnız kategoriyi taşır).
public enum RelativeDay: Equatable, Sendable {
    case today
    case yesterday
    /// 2...6 gün önce.
    case daysAgo(Int)
    /// 1...3 hafta önce.
    case weeksAgo(Int)
    /// 4+ hafta önce.
    case longAgo

    /// Takvim günü farkını kategoriye eşler. Gelecek tarih (cihaz saati ileri) `today` sayılır
    /// (negatif fark bugüne kırpılır). `calendar` çağırandan gelir (lokalize hafta başlangıcı).
    public static func between(_ date: Date, and now: Date, calendar: Calendar) -> RelativeDay {
        let start = calendar.startOfDay(for: date)
        let end = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        switch days {
        case ..<1:
            return .today
        case 1:
            return .yesterday
        case 2 ... 6:
            return .daysAgo(days)
        case 7 ... 27:
            return .weeksAgo(days / 7)
        default:
            return .longAgo
        }
    }
}
