# ShortSeries iOS — Dokümantasyon Dizini

**Amaç:** Bu doküman, ShortSeries iOS projesinin `docs/` altındaki tüm teknik ve ürün dokümantasyonunun giriş noktasıdır. Hangi dokümanın neyi kapsadığını, hangi rolün hangi sırayla okuması gerektiğini, projenin kanonik teknik kararlarının özetini ve dokümantasyonun nasıl güncel tutulacağını tanımlar. Ekibe yeni katılan herkes önce bu dosyayı okur; herhangi bir dokümanla çelişki durumunda terminoloji ve sayısal hedefler için tek doğruluk kaynağı proje kanonudur ve bu dizindeki tüm dokümanlar ona %100 uyar.

**İlgili dokümanlar:** 00-genel-bakis.md, 01-ozellik-envanteri.md, 02-ekran-haritasi-navigasyon.md, 03-mimari.md, 04-player-engine.md, 05-veri-modeli-api.md, 06-monetizasyon.md, 07-retention-gamification.md, 08-analitik-deney.md, 09-yol-haritasi-tasklar.md, 10-arastirma-raporu.md

---

## 1. Proje tanıtımı

ShortSeries, AI-generated dikey mikro-dizi (short drama) platformunun **iOS (Swift) istemcisidir**. Kullanıcı uygulamayı açtığı anda doğrudan tam ekran dikey video ile karşılaşır (Ana Sayfa = For You player feed'i); bölümler 1–3 dakikalık cliffhanger odaklı parçalar halinde akar, dizi başına ilk 5–10 bölüm ücretsizdir ve sonrası coin / rewarded ad / VIP abonelik ile açılır. İçerikler ayrı bir AI üretim hattında üretilir ve backend + CDN üzerinden servis edilir — **iOS istemcisi içerik üretmez, tüketir.** Benchmark uygulamalar ReelShort, DramaBox, NetShort ve DramaWave'dir; hedef bu uygulamalarla neredeyse %100 özellik paritesidir. Hedef pazar ABD önceliklidir (kategori gelirinin ~%49-60'ı ABD — Sensor Tower); altyapı çok dillidir (EN başta, TR/ES/PT ikinci dalga).

Neden bu proje: short-drama kategorisi Q1 2025'te ~$700M IAP geliri (YoY ~4x) ve >370M indirme üretti; 2024 başından kümülatif gelir ~$2.3B'dir ve pazarın ~%70'i iki uygulamada (ReelShort ~$490M, DramaBox ~$450M kümülatif) toplanmıştır — kategori kanıtlanmış, model kopyalanabilir, fark yaratma alanı yürütme kalitesindedir. **Kuzey yıldızımız, öncelik sırasıyla:** (1) akıcı, kesintisiz izleme deneyimi; (2) kullanıcının platformdan çıkmak istememesi (retention); (3) aradığı her şeyi kolayca bulabilmesi (discovery). Her ürün ve mühendislik kararı bu üç önceliğe göre tartılır: bir özellik izleme akıcılığını bozuyorsa (ör. time-to-first-frame < 500 ms veya swipe-to-next < 100 ms bütçesini aşıyorsa) retention getirisi ne olursa olsun geri gönderilir. Sayısal hedefler: D1 ≥ %30, D7 ≥ %10, D30 ≥ %5, ödeme dönüşümü ≥ %3, crash-free ≥ %99.8.

## 2. Doküman haritası

| Dosya | İçerik özeti | Hedef okuyucu |
|---|---|---|
| `README.md` (bu dosya) | Dokümantasyon dizini: harita, rol bazlı okuma sırası, kanonik kararların özeti, güncelleme kuralları. | Herkes (ilk durak) |
| `KANON.md` | Proje kanonu — terminoloji, ekran/modül adları, teknik kararlar ve sayısal hedeflerin TEK doğruluk kaynağı. Tüm dokümanlar buna %100 uyar; çelişkide kanon kazanır. | Herkes (referans) |
| `00-genel-bakis.md` | Ürün vizyonu, kuzey yıldızı, hedef pazar ve rakip konumlandırma (ReelShort / DramaBox / NetShort / DramaWave benchmark'ı), faz planının üst düzey özeti, başarı metrikleri. | PM, yeni ekip üyeleri, yönetim |
| `01-ozellik-envanteri.md` | Rakip paritesine göre tam özellik listesi: her özelliğin davranış tanımı, faz ataması (Faz 1/2/3), kabul kriterleri ve edge case'ler. Parite matrisi buradadır. | PM, iOS geliştirici, QA |
| `02-ekran-haritasi-navigasyon.md` | 5 sekmeli tab bar (Ana Sayfa, Keşfet, Ödüller, Listem, Profil) ve tüm ekranlar: Splash, Onboarding, PlayerFeed, DiziDetay, BolumListesi, UnlockSheet, CoinMagazasi, VIPAbonelik, OdulMerkezi, Kesfet, Arama, Listem, Profil, Ayarlar, BildirimMerkezi. Ekran geçişleri, deep link'ler, Coordinator (Router) akışları. | iOS geliştirici, tasarımcı, PM |
| `03-mimari.md` | MVVM + Coordinator, modüler SPM paketleri (AppFoundation, DesignSystem, PlayerKit, ContentKit, DiscoverKit, LibraryKit, WalletKit, RewardsKit, ProfileKit, AnalyticsKit, ShortSeriesApp), `@Observable` state, DI (init-injection + `Dependencies` konteyneri), Swift structured concurrency kuralları (actor'ler, Combine yasağı), katman sınırları. | iOS geliştirici, teknik lider |
| `04-player-engine.md` | Player feed'in UIKit çekirdeği: `UICollectionView` dikey paging + AVPlayer havuzu (`PlayerPool` actor, 3–5 instance), PrefetchController (~500 KB / ilk 2 sn), `preferredForwardBufferDuration` politikası (aktif = 0, idle = 1 sn), HLS yapılandırması (2–6 sn segment, 240p→1080p merdiveni), performans bütçeleri, disk cache (~200 MB LRU), `AVAssetDownloadTask` ile offline/ön-indirme, veri tasarrufu modu. | iOS geliştirici (player), teknik lider |
| `05-veri-modeli-api.md` | Series/Episode modelleri, katalog & feed API sözleşmeleri (REST + JSON, Codable), `unlockPrice` ve release schedule alanları, kimlik akışı (anonim misafir → Apple/Google/e-posta bağlama), imzalı URL'ler, SwiftData persistence şeması, cüzdan backend beklentileri (idempotency, double-entry, audit trail, fraud kontrolleri). | Backend geliştirici, iOS geliştirici |
| `06-monetizasyon.md` | Coin ekonomisi (bölüm kilidi 50–100 coin, API'den dinamik), coin paketleri ($0.99–$99.99, artan bonus kademeleri %0→%100, ilk yükleme 2x), VIP abonelik (haftalık $5.99 / intro $3.99 / aylık $14.99 / yıllık $49.99), UnlockSheet paywall akışı, StoreKit 2 entegrasyonu, server-side receipt doğrulama, purchased vs earned coin ayrımı ve harcama önceliği, rakip fiyat benchmark'ları. | PM, iOS geliştirici (WalletKit), backend |
| `07-retention-gamification.md` | Günlük check-in (7 günlük artan döngü, 10–50 coin), streak bonusu, görev merkezi, rewarded ads (günde 5–10 cap, remote config, 30 sn tamamlama), push stratejisi (yeni bölüm, kaldığın yerden devam, coin hatırlatması; sessiz saat + frekans limiti), cliffhanger + otomatik sonraki bölüm binge döngüsü, "devam et" yüzeyleri. | PM, iOS geliştirici (RewardsKit), CRM |
| `08-analitik-deney.md` | Event şeması (kendi şemamız + Firebase Analytics + Crashlytics), funnel tanımları, A/B deney altyapısı (feature-flag/remote-config), metrik sözlüğü (D1/D7/D30, ödeme dönüşümü, crash-free), deney süreci ve karar kuralları. | PM, veri analisti, iOS geliştirici |
| `09-yol-haritasi-tasklar.md` | Faz 1/2/3 kapsamı (Faz 1: iPhone-only portrait çekirdek; Faz 2: rewarded ads, FairPlay DRM, BildirimMerkezi; Faz 3: İndirilenler, Live Activities), epic/task kırılımı, bağımlılıklar, tahminler, kabul kriterleri. | PM, teknik lider, tüm geliştiriciler |
| `10-arastirma-raporu.md` | Pazar araştırması ham raporu: Sensor Tower/InvestGame verileri, rakip fiyat ve retention benchmark'ları, kaynak URL'leri, doğrulanmış/tutarsız iddia ayrımı. Diğer dokümanlardaki pazar rakamlarının kaynağıdır. | PM, yönetim, monetizasyon sahibi |

## 3. Önerilen okuma sırası (rol bazlı)

Her rol için sıra "bağlam → kendi alanı → komşu alanlar" mantığıyla kurulmuştur. İlk gün için asgari set kalın işaretlidir.

### PM / ürün
1. **`README.md`** → **`00-genel-bakis.md`** — vizyon, pazar, hedef metrikler.
2. **`01-ozellik-envanteri.md`** — kapsamın tamamı ve faz atamaları; parite matrisi.
3. **`02-ekran-haritasi-navigasyon.md`** — kullanıcı yüzeyleri ve akışlar.
4. `06-monetizasyon.md` + `07-retention-gamification.md` — gelir ve retention mekaniği (birlikte okunmalı; UnlockSheet ve OdulMerkezi iki dokümanın kesişimindedir).
5. `08-analitik-deney.md` — başarıyı nasıl ölçeceğiz.
6. `09-yol-haritasi-tasklar.md` — ne, ne zaman.
7. `10-arastirma-raporu.md` — rakam kaynakları; pazarlık/sunum hazırlarken referans.
8. `03-mimari.md` ve `04-player-engine.md` — yalnızca "neden bu teknik kısıt var" sorusuna cevap ararken.

### iOS geliştirici
1. **`README.md`** → **`00-genel-bakis.md`** (hızlı) — bağlam.
2. **`03-mimari.md`** — SPM modül sınırları, MVVM + Coordinator, `@Observable`, DI, concurrency kuralları. Kod yazmadan önce zorunlu.
3. **`02-ekran-haritasi-navigasyon.md`** — ekran adları ve navigasyon sözleşmeleri; Coordinator akışları buradaki adlarla kodlanır.
4. **`04-player-engine.md`** — PlayerKit üzerinde çalışan herkes için zorunlu; diğerleri için performans bütçelerini bilmek yeterli.
5. `05-veri-modeli-api.md` — modeller, API sözleşmeleri, SwiftData şeması.
6. Alan bazlı: WalletKit → `06-monetizasyon.md`; RewardsKit → `07-retention-gamification.md`; AnalyticsKit → `08-analitik-deney.md`.
7. `09-yol-haritasi-tasklar.md` — üzerinde çalıştığın epic'in kabul kriterleri.
8. `01-ozellik-envanteri.md` — geliştirdiğin özelliğin davranış tanımı ve edge case'leri (task'a başlamadan ilgili satırı mutlaka oku).

### Backend geliştirici
1. **`README.md`** → **`00-genel-bakis.md`** (hızlı) — bağlam ve "istemci tüketir, üretmez" sınırı.
2. **`05-veri-modeli-api.md`** — ana çalışma dokümanın: API sözleşmeleri, `unlockPrice`, release schedule, imzalı URL, kimlik akışı, cüzdan backend beklentileri (idempotent işlemler, double-entry kayıt, audit trail, fraud kontrolleri: receipt replay, jailbreak, anormal kazanç hızı).
3. **`06-monetizasyon.md`** — coin ekonomisi kuralları, purchased vs earned ayrımı ve harcama önceliği (earned önce), App Store Server API + Server Notifications V2 ile receipt doğrulama.
4. `04-player-engine.md` — HLS/CDN gereksinimleri (segment süresi, bitrate merdiveni, H.264 + HEVC varyantları); CDN tarafını besler.
5. `07-retention-gamification.md` — check-in/görev/streak sunucu mantığı ve push tetikleyicileri.
6. `08-analitik-deney.md` — event şeması ve remote-config sözleşmesi.
7. `02-ekran-haritasi-navigasyon.md` — hangi ekranın hangi endpoint'i çağırdığını görmek için referans.

## 4. Kanonik teknik kararların özeti

ShortSeries iOS 17.0+, iPhone-only (faz 1), portrait-locked bir uygulamadır; Swift 5.10+ ve Xcode 16+ ile geliştirilir. UI katmanı SwiftUI app shell + tab bar'dır ancak **player feed UIKit'tir**: `UICollectionView` (dikey paging) + AVPlayer havuzu, SwiftUI'ye `UIViewControllerRepresentable` köprüsüyle bağlanır (60fps kaydırma + player pooling için savaşta test edilmiş Mux/TikTok kalıbı). Mimari MVVM + Coordinator (Router) ve modüler SPM paketleridir; state `@Observable` (Observation framework), DI init-injection + hafif `Dependencies` konteyneridir; concurrency Swift structured concurrency'dir (async/await, actors — `PlayerPool` ve `WalletStore` actor'dür) ve yeni kodda Combine yoktur. Video HLS ile CDN'den gelir (2–6 sn segment, 240p→1080p portrait merdiveni, H.264 + HEVC); zorunlu performans bütçeleri time-to-first-frame < 500 ms, swipe-to-next < 100 ms, 60 fps kaydırma, 3–5 player'lık havuz, ~500 KB / ilk 2 sn prefetch, disk cache ~200 MB LRU'dur; HLS segmentleri URL interception ile cache'lenemediğinden offline/ön-indirme `AVAssetDownloadTask` iledir. Persistence SwiftData + Keychain + UserDefaults; networking REST + JSON (URLSession async/await, Codable); kimlik ilk açılışta otomatik anonim misafir hesabı, sonradan Apple/Google/e-posta bağlama; içerik erişimi imzalı URL, FairPlay DRM Faz 2'dir. IAP StoreKit 2 (coin = consumable, VIP = auto-renewable) ve server-side receipt doğrulamadır; rewarded ads (AdMob birincil aday) Faz 2, Live Activities Faz 3'tür; analitik kendi event şeması + Firebase Analytics + Crashlytics'tir; tasarım dark theme first (OLED siyahı) ve tek DesignSystem paketidir. Ayrıntı ve gerekçeler: `03-mimari.md`, `04-player-engine.md`, `06-monetizasyon.md`.

> **Fiyat notu:** Dokümanlardaki rakip fiyatları (özellikle ReelShort haftalık VIP'i — kaynaklarda $5.99–$20 arası çelişkili raporlanıyor) aralık olarak verilir, kesin rakam değildir; **lansman öncesi güncel App Store fiyatları doğrulanmalıdır.** ShortSeries'in kendi fiyat kademeleri ($0.99–$99.99 coin paketleri; VIP haftalık $5.99 / intro $3.99 ilk hafta / aylık $14.99 / yıllık $49.99) bizim tasarımımızdır ve `06-monetizasyon.md`'de tanımlıdır.

## 5. Kanonik terminoloji — hızlı referans

Tüm dokümanlar ve kod, ekran/sekme/modül adlarını aşağıdaki yazımla **birebir** kullanır. Yeni ad üretilmez; eş anlamlı kullanılmaz (ör. "Home feed" değil `PlayerFeed`, "cüzdan ekranı" değil `CoinMagazasi`).

- **Tab bar (5 sekme):** Ana Sayfa, Keşfet, Ödüller, Listem, Profil. Uygulama DOĞRUDAN video ile açılır (Ana Sayfa = `PlayerFeed`).
- **Ekranlar:** `Splash`, `Onboarding`, `PlayerFeed`, `DiziDetay`, `BolumListesi`, `UnlockSheet`, `CoinMagazasi`, `VIPAbonelik`, `OdulMerkezi`, `Kesfet`, `Arama`, `Listem`, `Profil`, `Ayarlar`, `BildirimMerkezi` (Faz 2). Davranış tanımları: `02-ekran-haritasi-navigasyon.md`.
- **SPM modülleri:** `AppFoundation`, `DesignSystem`, `PlayerKit`, `ContentKit`, `DiscoverKit`, `LibraryKit`, `WalletKit`, `RewardsKit`, `ProfileKit`, `AnalyticsKit`, `ShortSeriesApp`. Sahiplik ve sınırlar: `03-mimari.md`.

## 6. Doküman güncelleme kuralları

Dokümantasyonun değeri tutarlılığındadır. Kurallar:

1. **Kanon önce değişir.** Terminoloji, ekran/modül adı, teknik karar veya sayısal hedef değişecekse önce proje kanonu güncellenir; dokümanlar kanonu takip eder, tersi olmaz. Kanonla çelişen bir doküman bulan kişi dokümanı düzeltir (kanonu değil).
2. **Kanon değişikliğinde etki taraması zorunludur.** Değişikliği yapan kişi, yukarıdaki doküman haritasını kullanarak etkilenen tüm dokümanları aynı değişiklik içinde günceller. Tipik etki zincirleri: ekran adı/akış değişikliği → `02-ekran-haritasi-navigasyon.md` + `01-ozellik-envanteri.md` + ilgili alan dokümanı; fiyat/coin kuralı → `06-monetizasyon.md` + `05-veri-modeli-api.md` (unlockPrice/cüzdan) + `07-retention-gamification.md` (earned coin); performans bütçesi → `04-player-engine.md` + `08-analitik-deney.md` (metrik tanımı) + `09-yol-haritasi-tasklar.md` (kabul kriterleri); yeni modül → `03-mimari.md` + `README.md` (bu dosyanın 5. bölümü).
3. **Yarım güncelleme yasak.** Bir dokümanı güncelleyip çapraz referans verdiği dokümanları eski bırakmak, hiç güncellememekten kötüdür. Zaman yoksa etkilenen dokümanların başına tek satır uyarı eklenir: `> GÜNCELLEME BEKLİYOR: <tarih> — <değişen karar>` — ve `09-yol-haritasi-tasklar.md`'ye takip task'ı açılır.
4. **Stil şablonu korunur.** Her doküman şu yapıyla başlar: H1 başlık → "**Amaç:** ..." tek paragraf → "**İlgili dokümanlar:** ..." (göreli dosya adlarıyla, ör. `04-player-engine.md`) → içerik. Dil Türkçe, teknik terimler İngilizce kalabilir (prefetch, paywall, entitlement...). Kod örnekleri Swift.
5. **Pazar rakamı disiplini.** Sayısal pazar/fiyat iddiaları yalnız kanondaki doğrulanmış verilerden ve `10-arastirma-raporu.md`'nin doğrulanmış bölümünden alınır; kaynak düz URL ile gösterilir. Tutarsız raporlanan rakamlar (ör. ReelShort haftalık VIP) yalnızca aralık olarak yazılır ve "lansman öncesi App Store'dan doğrulanmalı" notu düşülür. Araştırma raporunda "çürütülmüş/tutarsız" işaretli rakamlar hiçbir dokümanda kesin veri olarak kullanılamaz.
6. **Yeni doküman eklerken:** numaralandırma şemasına uyulur (`NN-konu-adi.md`), bu README'deki doküman haritası tablosuna satır eklenir ve ilgili rol okuma sıralarına yerleştirilir. Bu adımlar yapılmadan yeni doküman "var" sayılmaz.
