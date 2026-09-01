import Foundation

// Bu dosya domain'in dış dünyaya açılan **tek** yüzeyidir. Her protokol bir adaptör paketi
// tarafından gerçeklenir; `LibraryKit` yalnız bu protokolleri görür (R3).

// MARK: - OCR

public protocol TextRecognizing: Sendable {
    /// Görsel verisini yapısal OCR çıktısına çevirir.
    ///
    /// Görsel `Data` olarak geçirilir (JPEG/PNG); domain `CGImage`/`UIImage` bilmez (R1).
    /// - Parameter languages: BCP-47 dil kodları, öncelik sırasıyla.
    func recognize(imageData: Data, languages: [String]) async throws -> RecognizedDocument
}

// MARK: - Analiz

public protocol ShotAnalyzing: Sendable {
    var kind: AnalyzerKind { get }
    /// Bu cihaz/oturum için kullanılabilir mi (Apple Intelligence kapalıysa `false`).
    var isAvailable: Bool { get async }

    /// OCR çıktısını sınıflandırır, özetler ve varlıkları çıkarır.
    /// Dönen varlıklar **henüz doğrulanmamıştır**; `ExtractionValidator` çağrısı pipeline'ın işidir.
    func analyze(_ document: RecognizedDocument) async throws -> ShotAnalysis

    /// Doğal dil arama sorgusunu yapılandırılmış niyete çevirir.
    /// Ayrıştırılamazsa `SearchIntent.plain(query)` döner — hata fırlatmaz.
    func parseSearchIntent(_ query: String) async -> SearchIntent
}

// MARK: - Fotoğraf kitaplığı

public enum ShotLibraryAuthorization: String, Sendable, Hashable {
    case notDetermined
    case denied
    /// Kullanıcı yalnız seçtiği görsellere erişim verdi.
    case limited
    case authorized
}

/// Kitaplıktan gelen ham asset tanımı (görsel verisi olmadan).
public struct ShotAsset: Sendable, Hashable, Identifiable {
    public let identifier: String
    public let createdAt: Date
    public let pixelWidth: Int
    public let pixelHeight: Int

    public var id: String { identifier }

    public init(identifier: String, createdAt: Date, pixelWidth: Int, pixelHeight: Int) {
        self.identifier = identifier
        self.createdAt = createdAt
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct ShotLibraryChange: Sendable, Hashable {
    public let inserted: [ShotAsset]
    public let removedIdentifiers: [String]

    public init(inserted: [ShotAsset], removedIdentifiers: [String]) {
        self.inserted = inserted
        self.removedIdentifiers = removedIdentifiers
    }
}

public protocol ShotSourcing: Sendable {
    var authorizationStatus: ShotLibraryAuthorization { get async }
    func requestAuthorization() async -> ShotLibraryAuthorization

    /// "Ekran Görüntüleri" akıllı albümündeki asset'ler, yeniden eskiye sıralı.
    func screenshots(newerThan date: Date?) async throws -> [ShotAsset]

    /// Analiz için görsel verisi. `maxPixelSize` uzun kenar sınırıdır (bellek koruması).
    func imageData(for identifier: String, maxPixelSize: Int) async throws -> Data

    /// Kitaplık değişikliklerinin canlı akışı (yeni screenshot, silme).
    func changes() -> AsyncStream<ShotLibraryChange>

    /// Kullanıcı onaylı silme. **Asla onaysız çağrılmaz** (KANON §8).
    func deleteAssets(identifiers: [String]) async throws
}

// MARK: - İndeks

public struct IndexCounts: Sendable, Hashable {
    public let total: Int
    public let analyzed: Int
    public let pending: Int
    public let failed: Int

    public init(total: Int, analyzed: Int, pending: Int, failed: Int) {
        self.total = total
        self.analyzed = analyzed
        self.pending = pending
        self.failed = failed
    }

    public var progress: Double {
        total > 0 ? Double(analyzed) / Double(total) : 0
    }
}

public protocol ShotIndexing: Sendable {
    func upsert(_ shot: Shot) async throws
    func upsert(_ shots: [Shot]) async throws
    func remove(assetIdentifiers: [String]) async throws
    func shot(assetIdentifier: String) async throws -> Shot?
    func search(_ query: SearchQuery) async throws -> [SearchResult]
    /// Kategoriye göre kitaplık listesi (nil = tümü), yeniden eskiye.
    func shots(category: ShotCategory?, limit: Int, offset: Int) async throws -> [Shot]
    /// Analiz bekleyen asset kimlikleri, öncelik sırasıyla.
    func pendingAssetIdentifiers(limit: Int) async throws -> [String]
    func counts() async throws -> IndexCounts
    /// Türev veriyi siler; kaynak görsellere dokunmaz (05 §6).
    func resetIndex() async throws
}

// MARK: - Aksiyonlar

public struct ReminderDraft: Sendable, Hashable {
    public let title: String
    public let notes: String?
    public let dueDate: Date?

    public init(title: String, notes: String? = nil, dueDate: Date? = nil) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
    }
}

public struct CalendarEventDraft: Sendable, Hashable {
    public let title: String
    public let notes: String?
    public let startDate: Date
    public let duration: TimeInterval

    public init(title: String, notes: String? = nil, startDate: Date, duration: TimeInterval = 3600) {
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.duration = duration
    }
}

public protocol ActionPerforming: Sendable {
    func createReminder(_ draft: ReminderDraft) async throws
    func createCalendarEvent(_ draft: CalendarEventDraft) async throws
}

// MARK: - Abonelik

public struct PurchasableProduct: Sendable, Hashable, Identifiable {
    public let identifier: String
    public let displayName: String
    public let displayPrice: String
    /// "yıl" / "ay" gibi yerelleştirilmiş periyot; tek seferlik üründe nil.
    public let periodDescription: String?
    public let hasIntroductoryOffer: Bool

    public var id: String { identifier }

    public init(
        identifier: String,
        displayName: String,
        displayPrice: String,
        periodDescription: String?,
        hasIntroductoryOffer: Bool
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.displayPrice = displayPrice
        self.periodDescription = periodDescription
        self.hasIntroductoryOffer = hasIntroductoryOffer
    }
}

public enum PurchaseOutcome: Sendable, Hashable {
    case purchased
    case pending
    case cancelled
}

public protocol EntitlementProviding: Sendable {
    var current: Entitlement { get async }
    /// Uygulama yaşam döngüsü boyunca dinlenen değişiklik akışı (`Transaction.updates`).
    func updates() -> AsyncStream<Entitlement>
    func availableProducts() async throws -> [PurchasableProduct]
    func purchase(productIdentifier: String) async throws -> PurchaseOutcome
    func restorePurchases() async throws
}

/// Free katman kota sayacı (cihazda tutulur, 06 §4).
public protocol QuotaMetering: Sendable {
    /// Kalan hak; Pro kullanıcıda `Int.max`.
    func remaining(_ capability: MeteredCapability) async -> Int
    /// Bir hak tüketir; hak yoksa `false` döner (çağıran paywall açar).
    func consume(_ capability: MeteredCapability) async -> Bool
}
