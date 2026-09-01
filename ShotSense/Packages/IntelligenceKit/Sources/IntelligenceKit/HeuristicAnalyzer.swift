import AppFoundation
import Foundation
import ShotCore

/// LLM kullanmadan çalışan, tamamen deterministik analiz yolu.
///
/// **Rolü iki katmanlıdır** (KANON §5):
/// 1. Apple Intelligence bulunmayan cihazlarda **tek** analiz yoludur — ürün eksiksiz çalışır.
/// 2. LLM'li cihazlarda taban sonuçtur: model başarısız olur, kapatılırsa veya guardrail'e
///    takılırsa arayüz asla boş kalmaz.
///
/// Tümüyle saf ve senkron olduğu için (~15 ms) altın kümede CI'da ölçülür (04 §7).
public struct HeuristicAnalyzer: ShotAnalyzing {
    public let kind: AnalyzerKind = .heuristic

    private let classifier: CategoryClassifier
    private let extractor: EntityExtractor
    private let validator: ExtractionValidator

    public init(
        classifier: CategoryClassifier = CategoryClassifier(),
        extractor: EntityExtractor = EntityExtractor(),
        validator: ExtractionValidator = ExtractionValidator()
    ) {
        self.classifier = classifier
        self.extractor = extractor
        self.validator = validator
    }

    public var isAvailable: Bool {
        get async { true }
    }

    public func analyze(_ document: RecognizedDocument) async throws -> ShotAnalysis {
        analyzeSynchronously(document)
    }

    /// Senkron giriş noktası: `FoundationModelAnalyzer` bunu taban sonuç olarak kullanır.
    public func analyzeSynchronously(_ document: RecognizedDocument) -> ShotAnalysis {
        let text = document.fullText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty(analyzerKind: .heuristic)
        }

        let (category, confidence) = classifier.classify(text)
        let entities = validator.validate(extractor.extract(from: text), against: text)

        return ShotAnalysis(
            category: category,
            categoryConfidence: confidence,
            title: TitleHeuristic.title(from: document.blocks),
            summary: Self.summary(from: document),
            tags: Self.tags(from: text, category: category),
            entities: entities,
            analyzerKind: .heuristic
        )
    }

    public func parseSearchIntent(_ query: String) async -> SearchIntent {
        SearchIntentHeuristic.parse(query)
    }

    // MARK: - Özet

    /// İlk iki "anlamlı" satırı özet sayar.
    ///
    /// Anlamlı = en az 3 kelime içeren satır. Ekran görüntülerinde tek kelimelik satırlar
    /// düğme etiketi veya menü öğesidir; özet olarak işe yaramaz.
    static func summary(from document: RecognizedDocument, maximumLength: Int = 180) -> String {
        let sentences = document.blocks
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.split(separator: " ").count >= 3 }
            .prefix(2)

        let joined = sentences.joined(separator: " ")
        guard joined.count > maximumLength else { return joined }
        return String(joined.prefix(maximumLength)) + "…"
    }

    // MARK: - Etiketler

    /// Türkçe + İngilizce durak kelimeler. Liste kısa tutulur: amaç dilbilimsel doğruluk değil,
    /// etiket listesinin "ve, için, the, and" ile dolmasını engellemektir.
    ///
    /// Girdiler **katlanmış** (aksansız, küçük harf) yazılır, çünkü karşılaştırma
    /// `TextNormalizer.tokenize` çıktısıyla yapılır: "için" tokenı "icin" olarak gelir ve
    /// aksanlı yazılmış bir durak kelime hiçbir zaman eşleşmezdi.
    static let stopWords: Set<String> = [
        "ve", "ile", "icin", "bir", "bu", "su", "da", "de", "mi", "ne", "her", "daha",
        "olarak", "gibi", "veya", "ama", "cok", "en", "var", "yok", "sonra", "once",
        "the", "and", "for", "with", "this", "that", "you", "your", "are", "was",
        "from", "have", "has", "not", "all", "can", "will", "but", "out", "get",
    ]

    static func tags(from text: String, category: ShotCategory, limit: Int = 5) -> [String] {
        var frequencies: [String: Int] = [:]
        for token in TextNormalizer.tokenize(text) {
            guard token.count >= 4, !stopWords.contains(token), !token.allSatisfy(\.isNumber)
            else { continue }
            frequencies[token, default: 0] += 1
        }

        // En sık geçen ayırt edici sözcükler; eşitlikte alfabetik sıra deterministiklik sağlar
        // (aynı görsel her analizde aynı etiketleri üretmelidir).
        let ranked = frequencies
            .filter { $0.value >= 2 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(limit)
            .map(\.key)

        return Array(ranked)
    }
}
