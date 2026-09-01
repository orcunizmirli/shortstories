# 03 — Mimari

## 1. İlkeler

1. **Ports & Adapters.** Domain (`ShotCore`) hiçbir Apple çerçevesine bağlı değildir —
   `Vision`, `FoundationModels`, `Photos`, `EventKit`, `StoreKit` yalnızca *adaptör*
   paketlerinde import edilir. Domain saf Swift'tir → test edilebilir, simülatörsüz koşar.
2. **Kompozisyon kökü tektir.** Adaptörleri portlara App target bağlar. Hiçbir paket
   başka bir "özellik" paketini import etmez.
3. **Swift 6 strict concurrency.** Tüm paketler `swiftLanguageModes: [.v6]`.
4. **Asset yok.** Tüm ikonografi SF Symbols, tüm renkler `DesignSystem` token'ları.
5. **Ağ yok.** Hiçbir pakette `URLSession` / socket kullanımı yoktur; CI bunu denetler.

## 2. Paket grafiği

```
                         ┌──────────────┐
                         │ AppFoundation│  log, hata, saat, feature flag, ring-buffer analytics
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │   ShotCore   │  domain modelleri + PORT protokolleri
                         └──────┬───────┘
        ┌───────────┬───────────┼───────────┬────────────┬───────────┐
        │           │           │           │            │           │
   ┌────▼───┐  ┌────▼─────┐ ┌───▼────┐ ┌────▼─────┐ ┌────▼────┐ ┌────▼─────┐
   │ OCRKit │  │Intelligen│ │IngestKit│ │ IndexKit │ │ActionKit│ │PaywallKit│   ADAPTÖRLER
   │(Vision)│  │ceKit(FM) │ │(Photos)│ │(NL/FTS)  │ │(EventKit│ │(StoreKit)│
   └────────┘  └──────────┘ └────────┘ └──────────┘ └─────────┘ └──────────┘
        ┌──────────────┐        ┌──────────────┐
        │ DesignSystem │◀───────│  LibraryKit  │  (UI: kitaplık, arama, detay, ayarlar)
        └──────────────┘        └──────┬───────┘
                                       │ yalnız ShotCore + DesignSystem + AppFoundation
                                ┌──────▼───────┐
                                │  ShotSenseApp│  KOMPOZİSYON KÖKÜ (tüm adaptörleri bağlar)
                                └──────────────┘
```

## 3. Paket sorumlulukları

| Paket | Sorumluluk | İzinli import |
|---|---|---|
| `AppFoundation` | Log, `AppError`, `Clock`, feature flag, cihaz-içi analitik | Foundation, os |
| `ShotCore` | `Shot`, `ShotCategory`, `ExtractedEntity`, `SearchQuery` + **portlar** (`TextRecognizing`, `ShotAnalyzing`, `ShotSourcing`, `ShotIndexing`, `ActionPerforming`, `EntitlementProviding`) | Foundation, AppFoundation |
| `OCRKit` | `VisionTextRecognizer: TextRecognizing` | Vision, CoreImage |
| `IntelligenceKit` | `FoundationModelAnalyzer: ShotAnalyzing`, `HeuristicAnalyzer: ShotAnalyzing`, `AnalyzerFactory` | FoundationModels, NaturalLanguage |
| `IngestKit` | `PhotosShotSource: ShotSourcing`, değişiklik gözlemcisi, thumbnail | Photos, PhotosUI |
| `IndexKit` | `HybridIndex: ShotIndexing` (BM25 + embedding), kalıcılık (SwiftData) | SwiftData, NaturalLanguage |
| `ActionKit` | `EventKitActionPerformer: ActionPerforming` | EventKit, Contacts |
| `PaywallKit` | `StoreKitEntitlementProvider: EntitlementProviding`, ürün katalogu | StoreKit |
| `DesignSystem` | Token'lar (renk/tipografi/aralık), `ShotCard`, `CategoryBadge`, `EmptyStateView` | SwiftUI |
| `LibraryKit` | Tüm ekranlar + view model'ler | SwiftUI, ShotCore, DesignSystem |

## 4. Bağımlılık kuralları (CI'da `Scripts/dependency-lint.swift` denetler)

- **R1** `ShotCore` yalnız `AppFoundation`'a bağımlıdır. Apple UI/servis çerçevesi import edemez.
- **R2** Adaptör paketleri birbirini import edemez (`OCRKit` ↔ `IntelligenceKit` yasak).
- **R3** `LibraryKit` hiçbir adaptörü import edemez — yalnız `ShotCore` portlarını kullanır.
- **R4** Yalnız App target adaptör + UI'yi birlikte import edebilir.
- **R5** `DesignSystem` `ShotCore` dışında domain bilmez; iş kuralı içermez.
- **R6** Hiçbir pakette `import UIKit` yoktur (SwiftUI + gerekli yerde `UIImage` köprüsü hariç, `DesignSystem` ve `IngestKit`).
- **R7** Hiçbir pakette `URLSession`, `Network`, `CFSocket` geçmez. **İhlali build'i kırar.**

## 5. Eşzamanlılık modeli

- **`AnalysisPipeline`** bir `actor`'dır: kuyruk, eşzamanlılık limiti (varsayılan 2), iptal.
- OCR ve LLM çağrıları `nonisolated` async fonksiyonlardır; pipeline `TaskGroup` ile sürer.
- SwiftData yazmaları tek bir `@ModelActor` (`ShotStore`) üzerinden — çoklu context yok.
- UI katmanı `@MainActor @Observable` view model'ler; domain tipleri `Sendable`.
- Foundation Models `LanguageModelSession` **thread-safe değildir** → her analiz görevi kendi
  oturumunu alır; oturum havuzu `SessionPool` actor'ında tutulur (soğuk başlangıç maliyeti için).

## 6. Veri akışı (bir screenshot'ın yaşam döngüsü)

```
PHAsset keşfi ──▶ ShotRecord(status:.pending) yazılır ──▶ AnalysisPipeline kuyruğu
   │
   ├─ 1. Görsel yükle (PHImageManager, maks 2048px kenar)
   ├─ 2. OCR  → RecognizedDocument{paragraflar, tablolar, barkodlar, diller}
   ├─ 3. Ön-filtre: metin < 8 karakter → kategori .other, LLM ÇAĞRILMAZ (maliyet/pil)
   ├─ 4. Analiz → ShotAnalysis{kategori, başlık, özet, etiketler, varlıklar, güven}
   ├─ 5. Doğrula (ExtractionValidator): tarihler geçerli mi, IBAN checksum, tutar formatı
   ├─ 6. Embedding üret (NLEmbedding, 512-boyut) + BM25 posting listesi güncelle
   └─ 7. ShotRecord(status:.analyzed) + indeks commit
                                   │
                                   └──▶ UI (Observable) yenilenir
```

Hata durumunda: `status = .failed(reason)`, 3 denemeye kadar üstel geri çekilme, sonra
`.other` kategorisiyle metin-yalnız indekslenir (arama yine çalışır).

## 7. Pil ve performans bütçesi

| Kural | Değer |
|---|---|
| Ön planda eşzamanlı analiz | 2 görev |
| Arka planda (`BGProcessingTask`) | 4 görev, yalnız şarjda + ağ gereksiz |
| Termal durum `.serious`+ | Pipeline duraklar |
| Düşük Güç Modu | Yalnız kullanıcı tetiklerse çalışır |
| Görsel başına hedef | ≤ 1.5 sn (OCR ~250 ms + LLM ~900 ms) |
| Depolama | Thumbnail 320px JPEG ~25 KB + metin ~2 KB → 5.000 görsel ≈ 135 MB |

## 8. Test stratejisi

- `ShotCore`: saf birim testleri (skorlama, doğrulama, sorgu ayrıştırma sonrası filtre uygulaması).
- `IntelligenceKit`: `HeuristicAnalyzer` tam test edilir; `FoundationModelAnalyzer` için
  **şema sözleşme testi** (prompt + `@Generable` tipinin alan adları) + sahte oturum.
- `IndexKit`: sabit korpus üzerinde sıralama regresyon testleri (altın küme).
- `LibraryKit`: view model testleri sahte portlarla; snapshot testi yok (kırılgan).
- CI matrisi paket başına `xcodebuild test` (bkz. `.github/workflows/pr.yml`).
