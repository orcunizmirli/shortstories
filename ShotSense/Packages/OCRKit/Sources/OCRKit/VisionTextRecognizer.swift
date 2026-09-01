import AppFoundation
import CoreGraphics
import Foundation
import ShotCore
import Vision

/// `TextRecognizing` portunun Vision gerçeklemesi.
///
/// Üç isteği birlikte koşar ve tek `RecognizedDocument` üretir:
/// 1. `RecognizeTextRequest` — satır düzeyi metin + konum (başlık heuristiği için).
/// 2. `DetectBarcodesRequest` — bilet/ödeme QR'ları.
/// 3. `RecognizeDocumentsRequest` — tablo yapısı (yalnız iOS 26+, `usesDocumentStructure` açıkken).
///
/// Üçü **bağımsızdır**: yapısal tanıma başarısız olursa metin ve barkodlar yine döner. OCR'ın
/// tamamen boş dönmesi ancak metin tanıma da başarısız olursa mümkündür.
public struct VisionTextRecognizer: TextRecognizing {
    private let configuration: OCRConfiguration

    public init(configuration: OCRConfiguration = .default) {
        self.configuration = configuration
    }

    public func recognize(imageData: Data, languages: [String]) async throws -> RecognizedDocument {
        let requestedLanguages = languages.isEmpty ? configuration.languages : languages

        async let blocks = recognizeTextBlocks(in: imageData, languages: requestedLanguages)
        async let barcodes = recognizeBarcodes(in: imageData)
        async let structure = recognizeStructure(in: imageData, languages: requestedLanguages)

        let (textBlocks, barcodeResults, structureResult) = await (blocks, barcodes, structure)

        guard !textBlocks.isEmpty || !barcodeResults.isEmpty else {
            // Hiçbir şey tanınmadıysa bu bir hata değildir: meme, oyun ekranı veya düz renk
            // olabilir. Pipeline bunu `.other` kategorisiyle metin-yalnız indeksler (04 §3).
            Log.debug(.ocr, "Tanınan içerik yok")
            return RecognizedDocument(languages: requestedLanguages)
        }

        return RecognizedDocument(
            blocks: textBlocks,
            tables: structureResult.tables,
            lists: structureResult.lists,
            barcodes: barcodeResults,
            languages: requestedLanguages
        )
    }

    // MARK: - Metin

    private func recognizeTextBlocks(
        in imageData: Data,
        languages: [String]
    ) async -> [RecognizedDocument.TextBlock] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Ekran görüntülerinde çoğu metin arayüz etiketidir; dil düzeltmesi marka adlarını
        // ve kod parçalarını bozabildiği için kapalıdır.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }

        do {
            let observations = try await request.perform(on: imageData)
            return observations.compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let confidence = Double(candidate.confidence)
                guard confidence >= configuration.minimumConfidence else { return nil }

                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }

                // Birim boyutlu görsele yansıtınca sonuç zaten normalize olur; `.upperLeft`
                // kökeni y=0'ı ekranın ÜSTÜ yapar, böylece "üstteki büyük satır başlıktır"
                // heuristiği doğrudan çalışır.
                let box = observation.boundingBox.toImageCoordinates(
                    CGSize(width: 1, height: 1),
                    origin: .upperLeft
                )
                return RecognizedDocument.TextBlock(
                    text: text,
                    verticalPosition: Double(box.midY),
                    relativeHeight: Double(box.height),
                    confidence: confidence
                )
            }
            .sorted { lhs, rhs in
                lhs.verticalPosition < rhs.verticalPosition
            }
        } catch {
            Log.error(.ocr, "Metin tanıma başarısız", error: error)
            return []
        }
    }

    // MARK: - Barkod

    private func recognizeBarcodes(in imageData: Data) async -> [RecognizedDocument.Barcode] {
        guard configuration.detectsBarcodes else { return [] }

        let request = DetectBarcodesRequest()
        do {
            let observations = try await request.perform(on: imageData)
            return observations.compactMap { observation in
                guard let payload = observation.payloadString, !payload.isEmpty else { return nil }
                return RecognizedDocument.Barcode(
                    payload: payload,
                    symbology: String(describing: observation.symbology)
                )
            }
        } catch {
            Log.warning(.ocr, "Barkod taraması başarısız")
            return []
        }
    }

    // MARK: - Yapı

    private func recognizeStructure(
        in imageData: Data,
        languages: [String]
    ) async -> DocumentStructure {
        guard configuration.usesDocumentStructure else { return .empty }
        return await VisionDocumentMapper.structure(in: imageData, languages: languages)
    }
}

/// Yapısal tanımanın çıktısı.
public struct DocumentStructure: Sendable {
    public let tables: [RecognizedDocument.Table]
    public let lists: [[String]]

    public static let empty = DocumentStructure(tables: [], lists: [])

    public init(tables: [RecognizedDocument.Table], lists: [[String]]) {
        self.tables = tables
        self.lists = lists
    }
}
