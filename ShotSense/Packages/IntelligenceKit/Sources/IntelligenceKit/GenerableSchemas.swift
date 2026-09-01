import FoundationModels
import ShotCore

// Guided generation şemaları. Bu tipler modelin üretebileceği **tek** yapıdır: şema dışı
// çıktı imkânsızdır, dolayısıyla JSON ayrıştırma hatası diye bir şey yoktur (04 §4.1).
//
// Tasarım kuralı: **Optional kullanılmaz.** "Yok" durumu sentinel değerlerle (`.none`
// kategorisi, boş string, 0) ifade edilir. Sebep: şemayı olabildiğince yalın tutmak 3B
// modelde alan atlama oranını gözle görülür biçimde düşürür.

@Generable
enum GenerableCategory {
    case receipt
    case ticket
    case wifi
    case conversation
    case recipe
    case article
    case code
    case product
    case location
    case event
    case banking
    case shipping
    case identity
    case other

    var domainValue: ShotCategory {
        switch self {
        case .receipt: return .receipt
        case .ticket: return .ticket
        case .wifi: return .wifi
        case .conversation: return .conversation
        case .recipe: return .recipe
        case .article: return .article
        case .code: return .code
        case .product: return .product
        case .location: return .location
        case .event: return .event
        case .banking: return .banking
        case .shipping: return .shipping
        case .identity: return .identity
        case .other: return .other
        }
    }
}

@Generable
enum GenerableEntityKind {
    case date
    case amount
    case merchant
    case url
    case phone
    case email
    case iban
    case trackingNumber
    case flightNumber
    case address
    case wifiSSID
    case wifiPassword
    case verificationCode
    case person

    var domainValue: EntityKind {
        switch self {
        case .date: return .date
        case .amount: return .amount
        case .merchant: return .merchant
        case .url: return .url
        case .phone: return .phone
        case .email: return .email
        case .iban: return .iban
        case .trackingNumber: return .trackingNumber
        case .flightNumber: return .flightNumber
        case .address: return .address
        case .wifiSSID: return .wifiSSID
        case .wifiPassword: return .wifiPassword
        case .verificationCode: return .code
        case .person: return .person
        }
    }
}

@Generable
struct GenerableEntity {
    @Guide(description: "Bilginin türü")
    var kind: GenerableEntityKind

    @Guide(description: "Değerin ekranda yazdığı hâli, BİREBİR kopyalanmış. Tahmin etme.")
    var rawValue: String

    @Guide(description: """
    Makine biçimi: tarih için YYYY-MM-DD, tutar için nokta ondalıklı sayı (1234.56), \
    telefon için yalnız rakamlar. Diğer türlerde ham değerin aynısı.
    """)
    var normalizedValue: String

    @Guide(description: "Yalnız tutar için ISO-4217 kodu (TRY, USD, EUR). Bilinmiyorsa boş bırak.")
    var currencyCode: String
}

@Generable
struct GenerableAnalysis {
    @Guide(description: "Ekran görüntüsünün türü")
    var category: GenerableCategory

    @Guide(description: "En fazla 6 kelimelik, içeriği tanımlayan başlık. Tırnak kullanma.")
    var title: String

    @Guide(description: "Kullanıcının aylar sonra ne olduğunu hatırlamasını sağlayacak tek cümle.")
    var summary: String

    @Guide(description: "Aramada işe yarayacak, en fazla 5 anahtar kelime. Tekil ve küçük harf.")
    var tags: [String]

    @Guide(description: """
    Metinde AÇIKÇA görünen bilgiler. Görünmeyen hiçbir şeyi ekleme; emin değilsen atla.
    """)
    var entities: [GenerableEntity]
}

@Generable
enum GenerableDateRange {
    case unspecified
    case last7Days
    case last30Days
    case last90Days
    case thisYear
    case lastYear

    var domainValue: RelativeDateRange? {
        switch self {
        case .unspecified: return nil
        case .last7Days: return .last7Days
        case .last30Days: return .last30Days
        case .last90Days: return .last90Days
        case .thisYear: return .thisYear
        case .lastYear: return .lastYear
        }
    }
}

@Generable
struct GenerableSearchIntent {
    @Guide(description: "Sorgunun filtreye çevrilemeyen, aranacak kısmı. Yoksa boş bırak.")
    var freeText: String

    @Guide(description: "Kullanıcı belirli bir tür istiyorsa o tür, aksi hâlde other.")
    var category: GenerableCategory

    @Guide(description: "Kullanıcı zaman aralığı belirttiyse o aralık, aksi hâlde unspecified.")
    var dateRange: GenerableDateRange

    @Guide(description: "Alt tutar sınırı; belirtilmemişse 0.")
    var minAmount: Double

    @Guide(description: "Üst tutar sınırı; belirtilmemişse 0.")
    var maxAmount: Double
}
