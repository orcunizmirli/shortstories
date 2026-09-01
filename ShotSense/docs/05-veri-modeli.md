# 05 — Veri Modeli ve Kalıcılık

## 1. Depolama seçimi

**SwiftData** (iOS 26). Gerekçe: `@Model` + `@Query` ile SwiftUI entegrasyonu, `ModelActor` ile
Swift 6 uyumlu izolasyon, migration desteği. Tam metin araması SwiftData'da yok → BM25 indeksi
**ayrı, kendi yazdığımız yapı** olarak tutulur (`IndexKit`), diskte tek bir binary snapshot
(`index.bin`) + bellekte posting list.

Görseller **kopyalanmaz** — yalnızca `PHAsset.localIdentifier` referansı ve 320px thumbnail
saklanır. Kullanıcı Photos'tan silerse kayıt "yetim" işaretlenir ve temizlenir.

## 2. Modeller

```swift
@Model final class ShotRecord {
    #Unique<ShotRecord>([\.assetIdentifier])
    var assetIdentifier: String        // PHAsset.localIdentifier
    var createdAt: Date                // asset'in çekilme tarihi
    var indexedAt: Date?
    var status: AnalysisStatus         // pending | analyzing | analyzed | failed | orphaned
    var schemaVersion: Int             // AnalysisSchemaVersion — yeniden analiz tetikler
    var pixelWidth: Int
    var pixelHeight: Int

    // OCR
    var recognizedText: String
    var ocrLanguages: [String]
    var barcodePayloads: [String]

    // Analiz
    var category: ShotCategory
    var categoryConfidence: Double
    var title: String
    var summary: String
    var tags: [String]
    var analyzerKind: AnalyzerKind     // foundationModel | heuristic
    var userCorrected: Bool

    // Türev
    var embedding: [Float]?            // 512-boyut, nil = model yok
    var thumbnailData: Data?           // 320px JPEG
    var perceptualHash: UInt64         // yinelenen tespiti (P1)

    @Relationship(deleteRule: .cascade) var entities: [ExtractedEntity]
    @Relationship(inverse: \Collection.shots) var collections: [Collection]
}

@Model final class ExtractedEntity {
    var kind: EntityKind               // date | amount | merchant | url | phone | email |
                                       // iban | trackingNumber | flightNumber | address |
                                       // wifiSSID | wifiPassword | code | person
    var rawValue: String               // metinde geçtiği hali
    var normalizedValue: String        // ISO tarih, ondalık tutar, E.164 telefon…
    var currencyCode: String?
    var confidence: Double
    var isGrounded: Bool               // OCR metninde doğrulandı mı (04 §5)
    var sourceRange: Range<Int>?       // recognizedText içindeki konum → vurgulama
}

@Model final class Collection {
    var name: String
    var symbolName: String             // SF Symbol
    var isSmart: Bool
    var savedQueryData: Data?          // akıllı koleksiyon için kodlanmış SearchQuery
    var shots: [ShotRecord]
}

@Model final class AnalysisJob {           // dayanıklı kuyruk (uygulama kapansa da sürsün)
    var assetIdentifier: String
    var attempts: Int
    var lastError: String?
    var nextAttemptAt: Date
    var priority: Int                       // 0 = kullanıcı tetikledi, 1 = yeni, 2 = geriye dönük
}
```

## 3. Domain ↔ kalıcılık ayrımı

`ShotRecord` bir **kalıcılık detayıdır** ve `IndexKit` içinde yaşar. `ShotCore` saf `struct Shot`
kullanır. Dönüşüm `ShotMapper` ile tek yönde yapılır. Bunun sebebi R1 kuralı: domain SwiftData
bilmez, dolayısıyla birim testleri simülatörsüz koşar.

## 4. İndeks dosyası

```
index.bin
├── header  { version, docCount, avgDocLength, vocabularySize }
├── vocabulary   [term → termID]  (sıralı, delta kodlu)
├── postings     [termID → (docID, tf)*]  (varint)
└── docMeta      [docID → (assetID hash, length, createdAt, category)]
```

Embedding'ler ayrı `vectors.bin` içinde ham `Float32` blob (docCount × 512). Kosinüs için
normalize edilmiş saklanır → arama sırasında yalnız nokta çarpımı.

5.000 belge için: postings ~4 MB, vektörler 5.000×512×4 B ≈ 10 MB. Bellekte tutulabilir.

## 5. Migration politikası

- **SwiftData şeması**: `VersionedSchema` + `SchemaMigrationPlan`, hafif migration tercih edilir.
- **Analiz şeması** (`AnalysisSchemaVersion`): artınca kayıtlar silinmez; `status` değişmez ama
  `schemaVersion < current` olanlar düşük öncelikli yeniden analiz kuyruğuna alınır.
- **İndeks formatı**: header'daki `version` uyuşmazsa indeks **sıfırdan** yeniden kurulur
  (kaynak veri SwiftData'da durduğu için kayıpsız, ~30 sn).

## 6. Silme semantiği

| Eylem | Sonuç |
|---|---|
| Uygulamadan "kaldır" | `ShotRecord` silinir, **Photos'taki görsel durur** |
| Temizlik asistanından "sil" | `PHPhotoLibrary` üzerinden silme istenir → sistem onay diyaloğu → çöp kutusuna gider |
| "İndeksi sıfırla" | Tüm `ShotRecord` + index.bin silinir, görsellere dokunulmaz |
| Photos'tan silinmiş asset | Senkronizasyonda `.orphaned` → sessizce temizlenir |
