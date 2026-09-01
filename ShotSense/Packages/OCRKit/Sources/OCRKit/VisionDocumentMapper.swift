import AppFoundation
import Foundation
import ShotCore
import Vision

/// `RecognizeDocumentsRequest` çıktısını domain tipine çeviren **tek** yer.
///
/// ⚠️ Bu dosya, Vision'ın iOS 26 belge-yapısı API'sine (`DocumentObservation` konteyner
/// hiyerarşisi) dokunan yegâne dosyadır ve bilinçli olarak küçük tutulmuştur: API yüzeyi yeni
/// olduğundan, Xcode ile ilk derlemede uyarlama gerekirse değişiklik buraya sınırlı kalır.
/// `VisionTextRecognizer` bu yol tamamen başarısız olsa bile metin ve barkod üretmeye devam eder.
enum VisionDocumentMapper {
    static func structure(in imageData: Data, languages: [String]) async -> DocumentStructure {
        var request = RecognizeDocumentsRequest()
        request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }

        do {
            let observations = try await request.perform(on: imageData)
            guard let document = observations.first?.document else { return .empty }
            return DocumentStructure(
                tables: document.tables.map(mapTable),
                lists: document.lists.map(mapList)
            )
        } catch {
            // Yapı olmadan da ürün çalışır; bu yüzden hata yükseltilmez, yalnız kaydedilir.
            Log.warning(.ocr, "Belge yapısı tanınamadı, metin-yalnız devam ediliyor")
            return .empty
        }
    }

    private static func mapTable(_ table: DocumentObservation.Container.Table)
        -> RecognizedDocument.Table {
        let rows = table.rows.map { row in
            row.map { cell in
                cell.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Tamamen boş satırlar (birleştirilmiş hücrelerden doğar) fiş kalemi çıkarımında
        // gürültüdür; prompt'a girmeden elenir.
        return RecognizedDocument.Table(rows: rows.filter { $0.contains { !$0.isEmpty } })
    }

    private static func mapList(_ list: DocumentObservation.Container.List) -> [String] {
        list.items.map { item in
            item.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }
}
