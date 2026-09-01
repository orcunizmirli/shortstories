import Foundation

/// Doğal dil sorgusundan çıkarılan yapılandırılmış niyet.
///
/// Kullanıcıya **çip olarak gösterilir** (02 §2.3): modelin ne anladığı görünür olmalı ve
/// tek dokunuşla geri alınabilmelidir. Sessizce uygulanan filtre, bulunamayan sonuç demektir.
public struct SearchIntent: Sendable, Codable, Hashable {
    /// Anlamsal/anahtar kelime araması için kalan serbest metin.
    public let freeText: String
    public let category: ShotCategory?
    public let dateRange: RelativeDateRange?
    public let minAmount: Double?
    public let maxAmount: Double?

    public init(
        freeText: String,
        category: ShotCategory? = nil,
        dateRange: RelativeDateRange? = nil,
        minAmount: Double? = nil,
        maxAmount: Double? = nil
    ) {
        self.freeText = freeText
        self.category = category
        self.dateRange = dateRange
        self.minAmount = minAmount
        self.maxAmount = maxAmount
    }

    /// Hiçbir filtre çıkarılamadıysa sorgu ham metin olarak aranır (hata gösterilmez).
    public static func plain(_ text: String) -> SearchIntent {
        SearchIntent(freeText: text)
    }

    public var hasFilters: Bool {
        category != nil || dateRange != nil || minAmount != nil || maxAmount != nil
    }
}

/// Göreli tarih aralıkları. Mutlak tarih yerine göreli kullanılır, çünkü model tarih aritmetiğinde
/// güvenilmezdir; aralığı `DateProviding` ile domain hesaplar.
public enum RelativeDateRange: String, Sendable, Codable, CaseIterable, Hashable {
    case last7Days
    case last30Days
    case last90Days
    case thisYear
    case lastYear

    /// Verilen "şimdi"ye göre kapalı-açık aralık üretir.
    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .last7Days:
            return interval(daysBack: 7, now: now, calendar: calendar)
        case .last30Days:
            return interval(daysBack: 30, now: now, calendar: calendar)
        case .last90Days:
            return interval(daysBack: 90, now: now, calendar: calendar)
        case .thisYear:
            guard let start = calendar.dateInterval(of: .year, for: now)?.start else { return nil }
            return DateInterval(start: start, end: now)
        case .lastYear:
            guard
                let thisYearStart = calendar.dateInterval(of: .year, for: now)?.start,
                let lastYearStart = calendar.date(byAdding: .year, value: -1, to: thisYearStart)
            else { return nil }
            return DateInterval(start: lastYearStart, end: thisYearStart)
        }
    }

    private func interval(daysBack: Int, now: Date, calendar: Calendar) -> DateInterval? {
        guard let start = calendar.date(byAdding: .day, value: -daysBack, to: now) else { return nil }
        return DateInterval(start: start, end: now)
    }
}

/// İndekse gönderilen tam sorgu.
public struct SearchQuery: Sendable, Hashable {
    public let intent: SearchIntent
    /// Filtrelerin uygulanacağı mutlak aralık (`intent.dateRange` çözülmüş hâli).
    public let dateInterval: DateInterval?
    public let limit: Int

    public init(intent: SearchIntent, dateInterval: DateInterval? = nil, limit: Int = 60) {
        self.intent = intent
        self.dateInterval = dateInterval
        self.limit = max(1, limit)
    }

    /// Niyeti verilen saate göre çözerek sorgu üretir.
    public static func resolving(
        _ intent: SearchIntent,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 60
    ) -> SearchQuery {
        SearchQuery(
            intent: intent,
            dateInterval: intent.dateRange?.interval(now: now, calendar: calendar),
            limit: limit
        )
    }

    /// Bir kaydın filtrelerden geçip geçmediği. Skorlamadan **önce** uygulanır (04 §6).
    public func matchesFilters(_ shot: Shot) -> Bool {
        if let category = intent.category, shot.analysis.category != category { return false }
        if let interval = dateInterval, !interval.contains(shot.createdAt) { return false }

        if intent.minAmount != nil || intent.maxAmount != nil {
            let amounts = shot.analysis.displayableEntities.compactMap(\.amountValue)
            guard !amounts.isEmpty else { return false }
            if let minAmount = intent.minAmount, !amounts.contains(where: { $0 >= minAmount }) {
                return false
            }
            if let maxAmount = intent.maxAmount, !amounts.contains(where: { $0 <= maxAmount }) {
                return false
            }
        }
        return true
    }
}

/// Sıralanmış arama sonucu.
public struct SearchResult: Sendable, Hashable, Identifiable {
    public let shot: Shot
    public let score: Double
    /// Skorun bileşenleri — sıralama regresyon testleri ve hata ayıklama için.
    public let termScore: Double
    public let semanticScore: Double
    public let recencyScore: Double
    /// Eşleşmenin geçtiği kısa metin parçası (UI'da vurgulanır).
    public let snippet: String

    public var id: String { shot.assetIdentifier }

    public init(
        shot: Shot,
        score: Double,
        termScore: Double = 0,
        semanticScore: Double = 0,
        recencyScore: Double = 0,
        snippet: String = ""
    ) {
        self.shot = shot
        self.score = score
        self.termScore = termScore
        self.semanticScore = semanticScore
        self.recencyScore = recencyScore
        self.snippet = snippet
    }
}
