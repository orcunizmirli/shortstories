import Foundation

/// Analizin hangi yolla üretildiği. Kalite ölçümü ve UI rozetleri bunu kullanır.
public enum AnalyzerKind: String, Sendable, Codable, Hashable {
    /// Foundation Models (Apple Intelligence).
    case foundationModel
    /// Regex + `NLTagger` tabanlı deterministik yol (LLM'siz cihazlar ve fallback).
    case heuristic
}

/// Bir ekran görüntüsünün analiz yaşam döngüsündeki yeri.
public enum AnalysisStatus: Sendable, Codable, Hashable {
    case pending
    case analyzing
    case analyzed
    /// Kalıcı olarak başarısız; metin-yalnız indekslenmiş olabilir.
    case failed(reason: String)
    /// Kaynak asset Photos'tan silinmiş.
    case orphaned
}

/// Modelin ürettiği analiz sonucu (kalıcılıktan bağımsız).
public struct ShotAnalysis: Sendable, Codable, Hashable {
    public let category: ShotCategory
    public let categoryConfidence: Double
    /// En fazla ~6 kelime.
    public let title: String
    /// Bir–iki cümle.
    public let summary: String
    public let tags: [String]
    public let entities: [ExtractedEntity]
    public let analyzerKind: AnalyzerKind

    public init(
        category: ShotCategory,
        categoryConfidence: Double,
        title: String,
        summary: String,
        tags: [String],
        entities: [ExtractedEntity],
        analyzerKind: AnalyzerKind
    ) {
        self.category = category
        self.categoryConfidence = min(max(categoryConfidence, 0), 1)
        self.title = title
        self.summary = summary
        self.tags = tags
        self.entities = entities
        self.analyzerKind = analyzerKind
    }

    /// Kullanıcıya gösterilebilecek varlıklar: yalnız kaynak metinde doğrulananlar (KANON §6).
    public var displayableEntities: [ExtractedEntity] {
        entities.filter(\.isGrounded)
    }

    /// Hiçbir şey çıkaramamış, yalnız metin indekslemeye yarayan boş analiz.
    public static func empty(analyzerKind: AnalyzerKind) -> ShotAnalysis {
        ShotAnalysis(
            category: .other,
            categoryConfidence: 0,
            title: "",
            summary: "",
            tags: [],
            entities: [],
            analyzerKind: analyzerKind
        )
    }
}

/// Domain'in ana varlığı. Kalıcılık tipi (`ShotRecord`, SwiftData) `IndexKit` içindedir;
/// domain onu bilmez (05 §3).
public struct Shot: Sendable, Codable, Hashable, Identifiable {
    /// `PHAsset.localIdentifier`.
    public let assetIdentifier: String
    /// Ekran görüntüsünün çekilme tarihi.
    public let createdAt: Date
    public let indexedAt: Date?
    public let status: AnalysisStatus
    /// Analiz şeması sürümü — artınca kayıt yeniden analiz kuyruğuna girer (05 §5).
    public let schemaVersion: Int
    public let recognizedText: String
    public let ocrLanguages: [String]
    public let barcodePayloads: [String]
    public let analysis: ShotAnalysis
    /// Kullanıcı kategoriyi/başlığı elle düzeltti mi — yeniden analizde korunur.
    public let userCorrected: Bool

    public var id: String { assetIdentifier }

    public init(
        assetIdentifier: String,
        createdAt: Date,
        indexedAt: Date? = nil,
        status: AnalysisStatus = .pending,
        schemaVersion: Int = AnalysisSchema.currentVersion,
        recognizedText: String = "",
        ocrLanguages: [String] = [],
        barcodePayloads: [String] = [],
        analysis: ShotAnalysis = .empty(analyzerKind: .heuristic),
        userCorrected: Bool = false
    ) {
        self.assetIdentifier = assetIdentifier
        self.createdAt = createdAt
        self.indexedAt = indexedAt
        self.status = status
        self.schemaVersion = schemaVersion
        self.recognizedText = recognizedText
        self.ocrLanguages = ocrLanguages
        self.barcodePayloads = barcodePayloads
        self.analysis = analysis
        self.userCorrected = userCorrected
    }

    /// Bu kayıt güncel şemaya göre yeniden analiz edilmeli mi.
    public var needsReanalysis: Bool {
        if case .analyzed = status {
            return schemaVersion < AnalysisSchema.currentVersion
        }
        return false
    }
}

/// Analiz şeması sürümü.
///
/// `ShotAnalysis` alan kümesi, kategori listesi veya prompt sözleşmesi değişince **artırılır**
/// (04 §8). Artış kayıtları silmez; tembel yeniden analiz tetikler.
public enum AnalysisSchema {
    public static let currentVersion = 1
}
