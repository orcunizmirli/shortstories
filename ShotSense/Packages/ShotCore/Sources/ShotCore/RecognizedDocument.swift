import Foundation

/// Vision'ın yapısal OCR çıktısının çerçeveden bağımsız temsili.
///
/// `OCRKit` bu tipi üretir; domain ve `IntelligenceKit` yalnız bunu görür (R1/R2).
/// Yapı **bilinçli olarak korunur**: tablo hücrelerini erken düz metne ezmek fiş kalemi
/// çıkarımını gözle görülür biçimde bozar (04 §2).
public struct RecognizedDocument: Sendable, Codable, Hashable {
    public struct TextBlock: Sendable, Codable, Hashable {
        public let text: String
        /// Görselin üst kenarından normalize uzaklık (0 = üst, 1 = alt).
        /// Başlık heuristiği "üstte ve büyük" kuralını buradan uygular.
        public let verticalPosition: Double
        /// Bloğun normalize yüksekliği — punto büyüklüğü vekili.
        public let relativeHeight: Double
        public let confidence: Double

        public init(
            text: String,
            verticalPosition: Double = 0,
            relativeHeight: Double = 0,
            confidence: Double = 1
        ) {
            self.text = text
            self.verticalPosition = verticalPosition
            self.relativeHeight = relativeHeight
            self.confidence = confidence
        }
    }

    public struct Table: Sendable, Codable, Hashable {
        /// Satır bazlı hücre metinleri.
        public let rows: [[String]]

        public init(rows: [[String]]) {
            self.rows = rows
        }

        /// Prompt'a girecek boru-ayrılmış gösterim.
        public var flattened: String {
            rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
        }
    }

    public struct Barcode: Sendable, Codable, Hashable {
        public let payload: String
        /// `qr`, `ean13`, `pdf417` gibi sembol adı.
        public let symbology: String

        public init(payload: String, symbology: String) {
            self.payload = payload
            self.symbology = symbology
        }
    }

    public let blocks: [TextBlock]
    public let tables: [Table]
    public let lists: [[String]]
    public let barcodes: [Barcode]
    /// Vision'ın tanıdığı dil kodları (BCP-47).
    public let languages: [String]

    public init(
        blocks: [TextBlock] = [],
        tables: [Table] = [],
        lists: [[String]] = [],
        barcodes: [Barcode] = [],
        languages: [String] = []
    ) {
        self.blocks = blocks
        self.tables = tables
        self.lists = lists
        self.barcodes = barcodes
        self.languages = languages
    }

    /// İndeksleme ve grounding doğrulaması için kullanılan düz metin.
    public var fullText: String {
        var parts = blocks.map(\.text)
        parts.append(contentsOf: tables.map(\.flattened))
        parts.append(contentsOf: lists.map { $0.joined(separator: "\n") })
        parts.append(contentsOf: barcodes.map(\.payload))
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public var isEmpty: Bool {
        fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// LLM'e verilecek gösterim.
    ///
    /// Metin `maxCharacters` sınırını aşarsa **baştan ve sondan** korunarak kırpılır: ekran
    /// görüntülerinde başlık üstte, toplam/tarih altta olur; ortadan kesmek her ikisini de korur.
    public func promptRepresentation(maxCharacters: Int = 4000) -> String {
        var sections: [String] = []
        let body = blocks.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")
        if !body.isEmpty { sections.append(body) }
        for table in tables where !table.rows.isEmpty {
            sections.append("[TABLO]\n" + table.flattened)
        }
        for list in lists where !list.isEmpty {
            sections.append("[LİSTE]\n" + list.map { "- " + $0 }.joined(separator: "\n"))
        }
        for barcode in barcodes {
            sections.append("[BARKOD \(barcode.symbology)] \(barcode.payload)")
        }
        let joined = sections.joined(separator: "\n\n")
        guard joined.count > maxCharacters else { return joined }

        let headLength = maxCharacters * 3 / 4
        let tailLength = maxCharacters - headLength
        let head = joined.prefix(headLength)
        let tail = joined.suffix(tailLength)
        return head + "\n[…]\n" + tail
    }
}
