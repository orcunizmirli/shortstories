# 08 — Yol Haritası ve Task Listesi

Tahminler tek geliştirici / gün cinsindendir. Task ID'leri commit mesajlarında kullanılır
(`feat(SS-012): …`).

## M0 — İskelet (2 gün) ✅

| ID | Task | Tahmin |
|---|---|---|
| SS-001 | Repo iskeleti, `.gitignore`, SwiftLint/SwiftFormat, XcodeGen `project.yml` | 0.5 |
| SS-002 | `AppFoundation` paketi (Log+redaction, `AppError`, `Clock`, feature flag) | 0.5 |
| SS-003 | `ShotCore`: domain modelleri + tüm port protokolleri | 1 |
| SS-004 | `Scripts/dependency-lint.swift` (R1–R7) + CI workflow | 0.5 |

## M1 — Anlama zinciri (4 gün) ✅

| ID | Task | Tahmin |
|---|---|---|
| SS-010 | `OCRKit`: `VisionTextRecognizer` (`RecognizeDocumentsRequest` + fallback) | 1 |
| SS-011 | `OCRKit`: barkod okuma, tablo→metin düzleştirme | 0.5 |
| SS-012 | `IntelligenceKit`: `@Generable` şemaları + `FoundationModelAnalyzer` | 1 |
| SS-013 | `IntelligenceKit`: `HeuristicAnalyzer` (regex+`NLTagger`+`NSDataDetector`) | 1 |
| SS-014 | `ExtractionValidator` (grounding, IBAN mod-97, ISO-4217) | 0.5 |
| SS-015 | Altın küme + doğruluk testi, CI eşiği %70 (şu an 18 örnek; 60 hedef) | 0.5 |

## M2 — Alım ve kalıcılık (4 gün)

| ID | Task | Tahmin |
|---|---|---|
| SS-020 | `IngestKit`: izinler, screenshot albümü, `PHAsset` listeleme, thumbnail | 1 |
| SS-021 | `IngestKit`: `PHPhotoLibraryChangeObserver` artımlı senkron | 0.5 |
| SS-022 | `IndexKit`: SwiftData şeması + `ShotStore` `@ModelActor` | 1 |
| SS-023 | `AnalysisPipeline` actor: kuyruk, öncelik, iptal, geri çekilme | 1 |
| SS-024 | `BGProcessingTask` kaydı + termal/pil politikası | 0.5 |

## M3 — Arama (3 gün)

| ID | Task | Tahmin |
|---|---|---|
| SS-030 | BM25 indeksi (tokenizer, posting list, binary serileştirme) | 1.5 |
| SS-031 | `NLEmbedding` vektörleri + kosinüs + hibrit skor | 0.5 |
| SS-032 | `SearchIntent` LLM ayrıştırma + filtre çipleri | 0.5 |
| SS-033 | Sıralama regresyon testleri (altın sorgular) | 0.5 |

## M4 — Arayüz (5 gün)

| ID | Task | Tahmin |
|---|---|---|
| SS-040 | `DesignSystem`: token'lar, `CategoryBadge`, `ShotCard`, `EmptyStateView` | 1 |
| SS-041 | `LibraryView` (grid, çipler, ilerleme bandı, durum matrisi) | 1 |
| SS-042 | `SearchView` (anlık + LLM, çipler, öneriler) | 1 |
| SS-043 | `ShotDetailView` (özet, varlık satırları, maskeleme, metin) | 1 |
| SS-044 | `SettingsView` + zekâ durumu + indeksi sıfırla | 0.5 |
| SS-045 | Erişilebilirlik geçişi (VoiceOver, Dynamic Type, 44pt) | 0.5 |

## M5 — Aksiyon + para (3 gün)

| ID | Task | Tahmin |
|---|---|---|
| SS-050 | `ActionKit`: EventKit hatırlatıcı + takvim, izin akışı | 1 |
| SS-051 | `PaywallKit`: StoreKit 2, `Transaction.updates`, entitlement | 1 |
| SS-052 | `QuotaLedger` + paywall tetikleyicileri + frekans kapağı | 0.5 |
| SS-053 | `PaywallView` (fiyat, deneme, restore, linkler) | 0.5 |

## M6 — Onboarding + cila (3 gün)

| ID | Task | Tahmin |
|---|---|---|
| SS-060 | `OnboardingFlow` 4 adım (değer → örnek → izin → indeksleme) | 1.5 |
| SS-061 | Boş/hata durumları, ilk çalıştırma performansı | 0.5 |
| SS-062 | App Store materyali (ekran görüntüleri, metin, gizlilik beyanı) | 1 |

**v1.0 toplam ≈ 24 gün.**

## v1.1 (sonraki)
Share Extension · App Intents/Shortcuts/Siri · Widget · Spotlight · yinelenen tespiti +
temizlik asistanı · manuel koleksiyon · dışa aktarma · lifetime ürünü.

## v1.2+
iPad/Mac native · görsel benzerlik · PDF alma · kullanıcı düzeltmelerinden öğrenen sıralama.

## Çıkış kriterleri (v1.0 yayınlanabilir sayılır)

1. 5.000 screenshot'lık kitaplık ilk indekslemeyi ≤ 90 dk'da, çökmeden bitirir.
2. Altın kümede kategori doğruluğu ≥ %70 (heuristik), ≥ %85 (LLM).
3. Apple Intelligence'sız cihazda tüm P0 akışları çalışır.
4. VoiceOver ile kitaplık→arama→detay→hatırlatıcı akışı tamamlanabilir.
5. Sızıntı yok: 30 dk kullanımda `URLSession` çağrısı 0 (Instruments Network ile doğrulanır).
6. Satın alma, iptal, geri yükleme, grace period sandbox'ta doğrulanmıştır.
