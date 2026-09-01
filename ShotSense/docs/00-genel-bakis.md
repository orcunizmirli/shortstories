# 00 — Genel Bakış

## 1. Problem

Ortalama bir iPhone kullanıcısının fotoğraf kitaplığında **binlerce ekran görüntüsü** birikir
(tipik aralık 1.500–10.000). Bu yığın pratikte *yazılabilir ama okunamaz* bir bellektir:

| Kullanıcı ihtiyacı | Bugünkü durum |
|---|---|
| "Geçen ay aldığım kablosuz kulaklığın fişi nerede?" | Photos aramasında marka adı hatırlanmadan bulunamaz |
| "Otelin wifi şifresini almıştım" | Elle scroll, ~40 sn |
| "Bu biletin tarihi ne zamandı?" | Screenshot açılır, gözle okunur, takvime elle girilir |
| "Bu 4.000 screenshot'ın hangisi çöp?" | Hiçbir sinyal yok; kimse temizlemez |

Apple'ın Live Text / Visual Look Up araması **kelime eşleşmesine** dayanır: içeriği
*sınıflandırmaz*, *özetlemez*, *varlık çıkarmaz*, *aksiyona çevirmez*.

## 2. Çözüm

Ekran görüntüsü yığınını **tamamen cihaz üstünde** işleyen bir zekâ katmanı:

1. **Anla** — Vision `RecognizeDocumentsRequest` ile yapısal OCR (paragraf, tablo, liste, barkod).
2. **Sınıflandır** — Foundation Models ile 14 kategori (fiş, bilet, wifi, sohbet, tarif, makale,
   kod, ürün, adres, etkinlik, banka/IBAN, kargo, kimlik, diğer).
3. **Çıkar** — tarih, tutar+para birimi, satıcı, URL, telefon, e-posta, IBAN, kargo no, uçuş no,
   adres, wifi SSID/şifre → yapılandırılmış `@Generable` çıktı.
4. **Ara** — doğal dil sorgusu ("geçen ay kulaklık fişi") → hibrit arama (BM25 + cümle embedding).
5. **Aksiyona çevir** — tek dokunuşla Hatırlatıcı, Takvim etkinliği, Kişi, panoya kopyala.
6. **Temizle** — süresi geçmiş / yinelenen / düşük değerli screenshot'lar için silme önerisi.

## 3. Neden şimdi (timing)

- **iOS 26 Foundation Models framework**: ~3B parametreli on-device LLM, guided generation
  (`@Generable`) ile şemalı çıktı, **ücretsiz ve kotasız**. Sunucu maliyeti = 0.
- **iOS 26 Vision `RecognizeDocumentsRequest`**: düz metin değil *yapı* döndürür (tablo hücreleri,
  liste öğeleri, algılanmış veri tipleri) — LLM'e verilen prompt kalitesini sıçratır.
- Bu ikisi olmadan aynı ürün, screenshot başına bir sunucu VLM çağrısı demekti
  (~$0.002–0.01/görsel × 5.000 görsel = kullanıcı başına $10–50 **negatif** birim ekonomi).

## 4. İş modeli

**Freemium + yıllık abonelik.** Sunucu yok → değişken maliyet ≈ 0 → abonelik geliri App Store
komisyonu (%15 small-business / %30) dışında **saf marj**.

| | Free | Pro |
|---|---|---|
| İndekslenen screenshot | Son 200 | Sınırsız |
| Doğal dil arama | Ayda 10 sorgu | Sınırsız |
| Aksiyonlar (hatırlatıcı/takvim) | 3/ay | Sınırsız |
| Otomatik koleksiyonlar, temizlik asistanı, dışa aktarma, widget | — | ✓ |

Hedef fiyat: **₺**/yerel eşdeğer ~ $19.99/yıl, $3.99/ay, 7 gün deneme. Detay: `06-monetizasyon.md`.

## 5. Hedef kullanıcı

1. **Bilgi işçisi** — makale/kod/toplantı notu screenshot'ları (birincil).
2. **Seyahat eden** — bilet, rezervasyon, wifi, adres.
3. **Alışverişçi** — fiş, ürün, kampanya kodu, kargo takip.
4. **Öğrenci** — ders slaytı, tarif, ödev.

## 6. Farklılaşma

| Rakip | Zayıf noktası |
|---|---|
| Apple Photos (yerleşik) | Sınıflandırma/özet/aksiyon yok; sadece kelime araması |
| Bulut tabanlı screenshot uygulamaları | Görselleri sunucuya yükler → gizlilik + maliyet |
| Genel not uygulamaları (Notion/Bear) | Manuel giriş gerektirir; otomatik değil |

**Bizim iddiamız:** *"Hiçbir görselin telefonundan çıkmaz"* — teknik olarak doğrulanabilir
(uygulama ağ izni istemez; bkz. `07-gizlilik.md` §3 "sıfır-ağ taahhüdü").

## 7. Riskler ve karşılıkları

| Risk | Etki | Karşılık |
|---|---|---|
| **Apple Intelligence cihaz kısıtı** (iPhone 15 Pro+ / 16+) | Kurulabilir tabanın ~%40'ı LLM'siz | `HeuristicAnalyzer` fallback: regex + `NLTagger` NER ile kategori+varlık. Ürün LLM'siz de çalışır, "Akıllı özet" kapalı olur |
| İlk indeksleme süresi/pil | 5.000 görsel × ~1.2 sn = ~100 dk | Artımlı + `BGProcessingTask` + yalnızca şarjda/boştayken; kullanıcıya ilerleme; en yeni 200 önce |
| Model kalitesi (3B) | Yanlış kategori/varlık | Şemalı çıktı + doğrulama katmanı (`ExtractionValidator`) + düşük güvende "belirsiz"e düşme + kullanıcı düzeltmesi |
| Photos izin sürtünmesi | Onboarding drop | Önce sınırlı seçim (`PHPickerViewController`) ile değer göster, sonra tam izin iste |
| App Review (Photos tam erişim gerekçesi) | Ret | `NSPhotoLibraryUsageDescription` net; ekran kaydı ile "veri cihazdan çıkmıyor" kanıtı |
| Foundation Models rate/guardrail reddi | Analiz boş döner | `LanguageModelSession` hata sınıflandırması + yeniden deneme + fallback zinciri |

## 8. Başarı metrikleri (cihaz-içi, anonim)

- **North star:** haftalık *başarılı geri getirme* (arama → detay açma) / aktif kullanıcı.
- Aktivasyon: onboarding sonrası ilk 24 saatte ≥1 arama yapan kullanıcı oranı (hedef %45).
- İndeksleme sağlığı: analiz başarı oranı (hedef ≥%95), medyan görsel/sn.
- Dönüşüm: paywall görüntüleme → deneme (hedef %8), deneme → ödeme (hedef %35).
