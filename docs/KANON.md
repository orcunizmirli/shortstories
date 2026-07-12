# ShortSeries — Proje Kanonu (tüm dokümanlar buna %100 uyar)

Bu dosya dokümantasyon yazarları için TEK doğruluk kaynağıdır. Terminoloji, mimari kararlar, ekran/modül adları ve sayısal hedefler burada tanımlandığı gibi kullanılır. Sapma yok.

## 1. Proje kimliği
- **Kod adı:** ShortSeries
- **Ne:** AI-generated dikey mikro-dizi (short drama) platformunun iOS (Swift) istemcisi.
- **Benchmark uygulamalar:** ReelShort, DramaBox, NetShort, DramaWave. Hedef: bu uygulamalarla neredeyse %100 özellik paritesi.
- **Kuzey yıldızı (öncelik sırasıyla):** (1) akıcı, kesintisiz izleme deneyimi; (2) kullanıcının platformdan çıkmak istememesi (retention); (3) aradığı her şeyi kolayca bulabilmesi (discovery).
- **İçerik kaynağı:** İçerikler AI üretim hattında üretilir (ayrı proje), backend + CDN üzerinden uygulamaya servis edilir. iOS istemcisi içerik ÜRETMEZ, TÜKETİR.
- **Hedef pazar:** ABD öncelikli (kategori gelirinin ~%49-60'ı ABD — Sensor Tower), çok dilli altyapı (EN başta, TR/ES/PT ikinci dalga).

## 2. Teknik kararlar (kesin)
- **Platform:** iOS 17.0+, iPhone-only, portrait-locked. Swift 5.10+, Xcode 16+. Android/iPad/landscape bilinçli kapsam dışıdır — "Won't (bu proje kapsamı)", faz iması yoktur (bkz. `01-ozellik-envanteri.md` §4).
- **UI:** SwiftUI app shell + tab bar. **Player feed UIKit'tir:** `UICollectionView` (dikey paging) + AVPlayer havuzu, SwiftUI'ye `UIViewControllerRepresentable` köprüsü. Gerekçe: 60fps kaydırma + player pooling için savaşta test edilmiş kalıp (Mux/TikTok kalıbı).
- **Mimari:** MVVM + Coordinator (Router). Modüler SPM paketleri. State: `@Observable` (Observation framework). DI: init-injection + hafif `Dependencies` konteyneri (protokol tabanlı, EnvironmentKey ile SwiftUI'ye).
- **Concurrency:** Swift structured concurrency (async/await, actors). `PlayerPool` ve `WalletStore` actor'dür. Combine YOK (yeni kodda).
- **Video:** HLS (CDN üzerinden), 2–6 sn segment, portrait bitrate merdiveni 240p→1080p (~300 kbps → 2.5 Mbps), H.264 + HEVC varyantları.
- **Performans bütçeleri (zorunlu):** time-to-first-frame < 500 ms; swipe-to-next oynatma < 100 ms; 60 fps kaydırma; player havuzu 3–5 instance; sonraki bölüm prefetch ~500 KB veya ilk 2 sn; `preferredForwardBufferDuration`: aktif player = 0 (otomatik), havuzdaki idle player = 1 sn; disk video cache ~200 MB LRU; hücresel veri tasarrufu modunda 480p + prefetch durdur.
- **HLS cache notu:** HLS segmentleri basit URL interception ile cache'lenemez; `AVAssetDownloadTask` (offline/ön-indirme) kullanılır. (Alternatif yol — progressive MP4 fast-start + `AVAssetResourceLoaderDelegate` — yalnızca "değerlendirilen alternatif" olarak anılır, seçilen yol HLS'dir.)
- **Player teknolojisi sınırı:** AVPlayer/AVFoundation seçimi PlayerKit-internal implementasyon kararıdır; PlayerKit'in public API'sında AVFoundation tipi (AVPlayer/AVPlayerItem/AVPlayerLayer) bulunamaz. Player teknolojisi değişikliğinin etki alanı `PlayerKit` + `ShortSeriesApp` (+ `LibraryKit` indirme) olarak tanımlıdır (bkz. `04-player-engine.md`).
- **Persistence:** SwiftData (izleme geçmişi, liste, cache metadata), Keychain (token), UserDefaults (flag/ayarlar).
- **Networking:** REST + JSON, URLSession async/await, Codable. Kimlik: anonim misafir hesabı ilk açılışta otomatik → sonradan Apple/Google/e-posta bağlama. İçerik erişimi imzalı URL; FairPlay DRM Faz 2.
- **IAP:** StoreKit 2. Coin = consumable, VIP = auto-renewable subscription. Server-side receipt doğrulama (App Store Server API + Server Notifications V2).
- **Reklam:** Rewarded ads (AdMob birincil aday) — Faz 2. Sağlayıcı değiştirilebilir detaydır; entegrasyon `RewardsKit`/AdBridge'e hapsolur (bkz. `06-monetizasyon.md`).
- **Push:** APNs + rich push (görselli). Live Activities Faz 3.
- **Analitik:** kendi event şeması + üçüncü parti (Firebase Analytics + Crashlytics); A/B için feature-flag/remote-config altyapısı.
- **Tasarım:** dark-locked (OLED siyahı) — uygulama sistem temasını TAKİP ETMEZ, tek temayla çalışır; light theme eklenmesi kanon değişikliğidir. Player overlay token'ları theme-invariant sınıftır (tema ekseni eklense bile her temada koyu kalır). Tek DesignSystem paketi.

## 3. Kanonik ekran ve sekme adları
Tab bar (5 sekme): **Ana Sayfa** (For You player feed'i — uygulama DOĞRUDAN video ile açılır), **Keşfet**, **Ödüller**, **Listem**, **Profil**.

Ekranlar (bu adlarla anılır):
- `Splash` — logo + ön-yükleme (ilk feed'i arka planda hazırlar)
- `Onboarding` — 2-3 adım: dil seçimi, tür tercihi (isteğe bağlı, atlanabilir), bildirim izni + ATT istemi (değer önerisinden SONRA sorulur)
- `PlayerFeed` (Ana Sayfa) — dikey tam ekran For You akışı; bölüm ilerledikçe aynı dizinin sonraki bölümü, dizi bitince/atlanınca yeni dizi önerisi
- `DiziDetay` — kapak, özet, etiketler, bölüm ızgarası, "İzlemeye Başla / Devam Et" CTA, listeye ekle, paylaş
- `BolumListesi` — player içinden açılan sheet; kilitli bölümler kilit ikonu + coin fiyatıyla
- `UnlockSheet` (paywall) — kilitli bölüme gelindiğinde: coin ile aç / reklam izle / VIP ol seçenekleri; coin yetersizse CoinMagazasi'na akar
- `CoinMagazasi` — coin paketleri + bonus kademeleri + ilk yükleme teklifi
- `VIPAbonelik` — abonelik planları ve ayrıcalıklar
- `OdulMerkezi` (Ödüller sekmesi) — günlük check-in takvimi, görev listesi, rewarded ad kartı, coin bakiyesi
- `Kesfet` — kategori rafları (banner + koleksiyonlar + sıralamalar: Trend, Yeni, Top 10), tür filtreleri
- `Arama` — arama çubuğu, otomatik tamamlama, popüler aramalar, sonuç ızgarası
- `Listem` — üç segment: Favoriler, Devam Et (izleme geçmişi + kaldığı yer), İndirilenler (Faz 3)
- `Profil` — hesap, coin/VIP durumu, izleme geçmişi, ayarlar girişi
- `Ayarlar` — dil (uygulama + altyazı), bildirim tercihleri, oynatma tercihleri (otomatik oynatma, veri tasarrufu), hesap yönetimi, yasal
- `BildirimMerkezi` — uygulama içi bildirim listesi (Faz 2)

## 4. Kanonik SPM modülleri
- `AppFoundation` — networking, auth/session, storage, config, feature flags, logging
- `DesignSystem` — renk/tipografi/bileşenler
- `PlayerKit` — PlayerPool (actor), PrefetchController, PlayerFeedViewController, oynatma UI'ı
- `ContentKit` — Series/Episode modelleri, katalog & feed API istemcileri
- `DiscoverKit` — Keşfet + Arama
- `LibraryKit` — Listem, izleme geçmişi, devam et, (Faz 3 indirmeler)
- `WalletKit` — coin cüzdanı, StoreKit 2, entitlement, UnlockSheet/CoinMagazasi/VIPAbonelik
- `RewardsKit` — check-in, görevler, rewarded ads köprüsü
- `ProfileKit` — profil, ayarlar, auth UI
- `AnalyticsKit` — event şeması, A/B deney istemcisi
- `ShortSeriesApp` — app target: koordinatörler, tab bar, DI kompozisyonu

## 5. İş modeli kanonu (ShortSeries tasarımı + rakip benchmark)
**Erişim modeli:** Dizi başına ilk 5–10 bölüm ücretsiz (~ilk 10 dakika), sonrası bölüm başına kilitli. Kilit cliffhanger noktasına denk gelir (içerik ekibi belirler, istemci `unlockPrice`yi API'den okur).

**ShortSeries coin ekonomisi (bizim tasarım):**
- Bölüm kilidi: 50–100 coin (API'den dinamik, `unlockPrice`)
- Coin paketleri (USD, App Store): $0.99 / $4.99 / $9.99 / $19.99 / $49.99 / $99.99 — artan bonus coin kademeleri (%0→%100), ilk yüklemeye özel 2x bonus teklifi
- VIP abonelik: haftalık $5.99 (intro teklif $3.99/ilk hafta), aylık $14.99, yıllık $49.99 — tüm bölümler açık + günlük bonus coin + reklamsız
- Rewarded ad ile kilit açma: günde 5–10 cap (remote config), 30 sn tamamlama şartı
- Günlük check-in: 7 günlük artan döngü, 10–50 coin; streak bonusu
- Görevler: izleme süresi, favorileme, paylaşma, bildirim izni → coin ödülü; earned coin'ler son kullanma tarihli olabilir
- **Purchased vs earned coin ayrımı zorunlu** (muhasebe + App Store komisyonu farkı); harcama önceliği: earned önce
- Cüzdan backend beklentisi: idempotent işlemler, double-entry kayıt, audit trail, fraud kontrolleri (receipt replay, jailbreak, anormal kazanç hızı)

**Rakip benchmark (dokümanlarda kaynaklı kullanılabilir):**
- ReelShort: coin ağırlıklı model; haftalık VIP fiyatı kaynaklarda $5.99–$20 arası ÇELİŞKİLİ raporlanıyor → "aralık" olarak belgele, kesin rakam verme; bölüm ~18–100 coin; seri tamamlama ~$10–50
- DramaBox: abonelik ağırlıklı; $3.99 intro / $5.99 haftalık / $49.99 yıllık (doğrulanmış); daha fazla ücretsiz bölüm
- DramaWave: haftalık/aylık VIP ~$19.90 + $9.99 tek seferlik teklif (tek kaynak, temkinli kullan)
- UYARI: Fiyat ayrıntıları kaynaklar arasında tutarsız; dokümanlarda "lansman öncesi güncel App Store fiyatları doğrulanmalı" notu düş.

**Pazar verisi (doğrulanmış, Sensor Tower/InvestGame kaynaklı):**
- Kategori Q1 2025: ~$700M IAP geliri (YoY ~4x), >370M indirme; 2024 başından kümülatif ~$2.3B
- ReelShort: $130M Q1 2025, ~$490M kümülatif; DramaBox: $120M, ~$450M; birlikte küresel short-drama IAP'ının ~%70'i
- DramaWave: Q1 2025'te indirmede 10x büyüme, 53M kümülatif indirme, ~$47M gelir; NetShort: %171 çeyreklik gelir büyümesi, ~$57M kümülatif
- ABD: kategori gelirinin ~%49'u (Q1 2025); hedef demografi ağırlıkla 25–45 kadın
- Retention benchmark: kategori ortalaması D1 ~%27, D7 ~%8.6, D14 ~%5.6; DramaBox 6. ay %17 / 12. ay %15; rewarded engagement kullanıcıları ~3x daha sık geri dönüyor (adjoe)
- ShortSeries hedefleri: D1 ≥ %30, D7 ≥ %10, D30 ≥ %5; ödeme dönüşümü ≥ %3; crash-free ≥ %99.8

## 6. Retention kanonu
- Günlük check-in (7 gün döngü, artan ödül), görev merkezi, streak
- Push stratejisi: yeni bölüm, kaldığın yerden devam, coin/ödül hatırlatması, kişiselleştirilmiş öneri; sessiz saat + frekans limiti
- Cliffhanger + otomatik sonraki bölüm = binge döngüsü; "devam et" her yüzeyde (Ana Sayfa rafı, Listem, push, DiziDetay)
- Yeni bölüm takvimi: diziler bölüm bölüm yayınlanabilir (release schedule API'den)

## 7. Doküman stili
- Dil: **Türkçe**; teknik terimler İngilizce kalabilir (prefetch, paywall, entitlement...)
- Markdown; tablo serbest; kod örnekleri Swift.
- Her doküman şu şablonla başlar: H1 başlık → "**Amaç:** ..." tek paragraf → "**İlgili dokümanlar:** ..." (dosya adlarıyla çapraz referans) → içerik.
- Ekran/modül adları bu kanondaki yazımla birebir kullanılır.
- Kaynak gösterirken düz URL; sayısal pazar iddiaları yalnız Bölüm 5'teki doğrulanmış verilerden.
- Dosyalar `docs/` altındadır; çapraz referanslar göreli dosya adıyla verilir (ör. `04-player-engine.md`).
