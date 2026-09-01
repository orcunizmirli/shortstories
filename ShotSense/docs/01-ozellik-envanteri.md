# 01 — Özellik Envanteri

Öncelik: **P0** = v1.0 kapsamı (yayınlanamaz olmadan), **P1** = v1.1–1.2, **P2** = sonrası.

## A. Alım (Ingest)

| # | Özellik | Öncelik | Not |
|---|---|---|---|
| A1 | Photos "Ekran Görüntüleri" akıllı albümünü okuma | P0 | `PHAssetCollection.smartAlbumScreenshots` |
| A2 | Artımlı senkronizasyon (`PHPhotoLibraryChangeObserver`) | P0 | Yeni screenshot otomatik kuyruğa |
| A3 | Sınırlı erişim modu (`PHPicker` ile elle ekleme) | P0 | İzin vermeyen kullanıcı için değer kanıtı |
| A4 | Arka plan indeksleme (`BGProcessingTask`, şarj+boşta) | P0 | Pil politikası `03-mimari.md` §7 |
| A5 | Share Extension ile başka uygulamadan görsel alma | P1 | |
| A6 | Screenshot dışı fotoğraflar (fatura fotoğrafı vb.) | P1 | Kullanıcı opt-in, ayrı albüm |
| A7 | PDF / belge alma | P2 | |

## B. Anlama (OCR + Zekâ)

| # | Özellik | Öncelik | Not |
|---|---|---|---|
| B1 | Yapısal OCR (`RecognizeDocumentsRequest`) | P0 | Paragraf/tablo/liste |
| B2 | Barkod + QR okuma (`DetectBarcodesRequest`) | P0 | Bilet/ödeme QR'ları |
| B3 | Kategori sınıflandırma (14 sınıf) | P0 | Foundation Models `@Generable` enum |
| B4 | Başlık + 1 cümlelik özet üretimi | P0 | |
| B5 | Varlık çıkarımı (tarih, tutar, satıcı, URL, tel, e-posta, IBAN, kargo, uçuş, adres, wifi) | P0 | Şemalı çıktı + doğrulama |
| B6 | Etiket (tag) önerisi, maks. 5 | P0 | |
| B7 | Kaynak uygulama tahmini (WhatsApp, Safari, Instagram…) | P1 | Statü çubuğu/renk imzası + LLM ipucu |
| B8 | LLM'siz cihazlar için heuristik analiz | P0 | `NLTagger` + regex; ürün çalışmaya devam eder |
| B9 | Kullanıcı düzeltmesi (kategori/başlık değiştir) | P1 | Düzeltmeler yeniden analizde ipucu olur |
| B10 | Çok dilli OCR (TR/EN öncelikli) | P0 | `recognitionLanguages` |

## C. Geri getirme (Arama)

| # | Özellik | Öncelik | Not |
|---|---|---|---|
| C1 | Anahtar kelime araması (OCR metni üzerinde, BM25) | P0 | |
| C2 | Anlamsal arama (`NLEmbedding` cümle vektörü, kosinüs) | P0 | Hibrit skor `04-zeka-pipeline.md` §6 |
| C3 | Doğal dil sorgu ayrıştırma ("geçen ay 500 TL üstü fişler") | P0 | LLM → `SearchFilter` `@Generable` |
| C4 | Kategori / tarih / tutar filtreleri | P0 | |
| C5 | Spotlight indeksleme (`CoreSpotlight`) | P1 | Sistem aramasından erişim |
| C6 | Kaydedilmiş aramalar → akıllı koleksiyon | P1 | |
| C7 | Görsel benzerlik araması | P2 | |

## D. Aksiyon

| # | Özellik | Öncelik | Not |
|---|---|---|---|
| D1 | Hatırlatıcı oluştur (EventKit) | P0 | Çıkarılan tarih ön-doldurulur |
| D2 | Takvim etkinliği oluştur | P0 | |
| D3 | Metni / tek alanı panoya kopyala (IBAN, kod, şifre) | P0 | |
| D4 | Kişi olarak kaydet (Contacts) | P1 | |
| D5 | URL'yi aç / Safari okuma listesine ekle | P1 | |
| D6 | App Intents + Shortcuts + Siri | P1 | "ShotSense'te wifi şifresi ara" |
| D7 | Widget: "Yaklaşan" (tarihi gelen screenshot'lar) | P1 | |

## E. Organizasyon ve bakım

| # | Özellik | Öncelik | Not |
|---|---|---|---|
| E1 | Kategoriye göre otomatik koleksiyonlar | P0 | |
| E2 | Manuel koleksiyon / favori | P1 | |
| E3 | Yinelenen tespiti (perceptual hash) | P1 | |
| E4 | Temizlik asistanı: süresi geçmiş + yinelenen + düşük değerli | P1 | Silme **her zaman** onaylı |
| E5 | Dışa aktarma (JSON / CSV / Markdown) | P1 | |
| E6 | Arşivleme (indeksten çıkarmadan gizle) | P2 | |

## F. Platform / altyapı

| # | Özellik | Öncelik | Not |
|---|---|---|---|
| F1 | Onboarding (izin, ilk indeksleme, değer gösterimi) | P0 | |
| F2 | Paywall + StoreKit 2 abonelik | P0 | |
| F3 | Ayarlar (dil, indeksleme politikası, veri sıfırlama) | P0 | |
| F4 | Karanlık mod, Dynamic Type, VoiceOver | P0 | Erişilebilirlik kanon kuralı |
| F5 | Cihaz-içi analitik (ağ yok, halka tampon) | P0 | |
| F6 | iPad / Mac (Catalyst değil, native) | P2 | |

## G. Kapsam DIŞI (v1)

- Bulut senkronizasyonu, hesap sistemi, sunucu (mimari taahhüt — bkz. `07-gizlilik.md`).
- Paylaşımlı koleksiyonlar / işbirliği.
- Android.
- Video / ekran kaydı analizi.
