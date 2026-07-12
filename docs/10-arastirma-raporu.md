# Araştırma Raporu — Kaynaklar ve Doğrulanmış Bulgular

**Amaç:** Bu doküman, ShortSeries dokümantasyon setindeki tüm pazar, fiyatlandırma, retention ve player-mühendisliği iddialarının kanıt tabanını tek yerde toplar: hangi iddia hangi kaynaktan geldi, çapraz doğrulamadan geçti mi, geçemediyse dokümanlarda nasıl (ör. aralık + doğrulama notu olarak) kullanıldı. Diğer dokümanlarda geçen her sayısal pazar/fiyat iddiasının izlenebilirlik (traceability) referansıdır; bir rakam buradaki "Doğrulanmış" veya "Yüksek güvenli" tablolarda yoksa, dokümanlarda kesin veri olarak kullanılamaz. Rapor ayrıca araştırma boşluklarını ve lansman öncesi kapatılması zorunlu doğrulama görevlerini (bkz. 09-yol-haritasi-tasklar.md, E16) tanımlar.

**İlgili dokümanlar:** README.md (doküman seti haritası), 00-genel-bakis.md (pazar analizi — bu rapordaki doğrulanmış rakamları kullanır), 01-ozellik-envanteri.md (rakip parite matrisi), 02-ekran-haritasi-navigasyon.md (UnlockSheet/paywall akışının teardown dayanağı), 03-mimari.md (SwiftUI + UIKit köprü kararı), 04-player-engine.md (performans bütçelerinin kaynağı), 05-veri-modeli-api.md (unlockPrice ve cüzdan sözleşmeleri), 06-monetizasyon.md (coin/VIP ekonomisi — fiyat aralıkları buradan türetildi), 07-retention-gamification.md (retention benchmarkları), 08-analitik-deney.md (KPI hedeflerinin benchmark dayanağı), 09-yol-haritasi-tasklar.md (E16 doğrulama görevi).

---

## 1. Metodoloji

### 1.1 Araştırma hattı (pipeline)

Araştırma, benchmark uygulamalar (ReelShort, DramaBox, NetShort, DramaWave) ve dikey video player mühendisliği üzerine **5 paralel arama kolunda** yürütüldü:

| Kol | Konu | Beslediği dokümanlar |
|---|---|---|
| K1 | Pazar büyüklüğü, rakip gelir/indirme verileri, App Store konumlanması | 00-genel-bakis.md |
| K2 | Monetizasyon: coin ekonomisi, VIP abonelik, paywall/unlock akışları, fiyat kademeleri | 06-monetizasyon.md, 05-veri-modeli-api.md |
| K3 | Retention ve gamification: check-in, görevler, rewarded ads, push, benchmark oranları | 07-retention-gamification.md, 08-analitik-deney.md |
| K4 | Özellik envanteri ve ekran akışları (klon-rehberi kaynakları, ürün teardown'ları) | 01-ozellik-envanteri.md, 02-ekran-haritasi-navigasyon.md |
| K5 | iOS player mühendisliği: AVPlayer pooling, prefetch, HLS, buffer tuning | 04-player-engine.md, 03-mimari.md |

Hattın akışı:

1. **Toplama:** 5 kol toplam 30 ham arama sonucu döndürdü; tekilleştirme ve kalite filtresinden sonra **18 kaynak** ana kanıt tabanını oluşturdu (6 ek kaynak yalnızca teknik referans / çapraz kontrol amacıyla tutuldu — bkz. §6.2).
2. **İddia çıkarımı:** Kaynaklardan, doğrudan alıntıyla desteklenen **85 iddia** çıkarıldı. Her iddia iki eksende etiketlendi: önem (`central` / `supporting` / `tangential`) ve kaynak kalitesi (`primary` / `secondary` / `blog`).
3. **Çapraz doğrulama:** Dokümanlara **kesin rakam** olarak girecek iddialar önceliklendirilerek oylamaya alındı. Her iddia için **3 bağımsız hakem** oylaması yapıldı; hakemler iddiayı diğer kaynaklara ve birincil verilere karşı sınadı. Kural: **3 hakemden 2'si çürütürse iddia elenir** (dokümanlarda kesin veri olarak kullanılamaz).
4. **Sentez:** Doğrulanan iddialar kanon dokümanına (proje geneli doğruluk kaynağı) ve ilgili dokümanlara işlendi.

> **Süreç notu (şeffaflık):** Oturum limiti nedeniyle otomatik hattın **sentez adımı manuel tamamlandı** ve 3 iddianın oylaması yarım kaldı (bkz. §5). Oylamaya girmeyen `central`/`primary` etiketli iddialar §3'te **"tek kaynak, oylanmadı"** etiketiyle listelenir; bunlar yön göstermek için kullanılabilir ama tek başına kesin veri sayılmaz.

### 1.2 Oylama sonuç dağılımı

| Sonuç | Adet | Dokümanlardaki statüsü |
|---|---|---|
| Doğrulanmış (2-0'dan iyi; çoğu 3-0) | 9 | Kesin veri olarak kullanılabilir (§2) |
| Çürütülmüş / tutarsız (2/3 veya 3/3 çürütme) | 13 | Kesin rakam olarak **kullanılamaz**; yalnız "kaynaklar arasında tutarsız, aralık" notuyla anılabilir (§4) |
| Doğrulanamayan (oylama tamamlanamadı) | 3 | Temkinli; yalnız nitel yön olarak (§5) |
| Oylamaya girmeyen | 60 | Seçilmiş olanlar §3'te "tek kaynak, oylanmadı" etiketiyle; kalanı yalnız bağlam |

### 1.3 Kullanım kuralları (diğer doküman yazarları için kabul kriterleri)

- **AC-R1:** Herhangi bir dokümanda geçen pazar/gelir/indirme/retention rakamı, bu raporun §2 (Doğrulanmış) veya §3 (Yüksek güvenli) tablolarından birine dayanmak zorundadır. Dayanmıyorsa rakam silinir veya "doğrulanmamış" ibaresiyle işaretlenir.
- **AC-R2:** §4'teki çürütülmüş fiyat ayrıntıları (coin paket fiyatları, haftalık VIP, bölüm başı maliyet) hiçbir dokümanda kesin rakam olarak yer alamaz; yalnız **aralık** olarak ve "lansman öncesi App Store'dan doğrulanmalı" notuyla kullanılabilir.
- **AC-R3:** ShortSeries'in **kendi** fiyat tasarımı (coin paketleri, VIP planları, rewarded cap) rakip fiyatlarından bağımsız bir üründür ve kesin rakamla yazılabilir; ancak rakip karşılaştırma tablolarında AC-R2 geçerlidir.
- **AC-R4:** Lansman go/no-go kapısından önce 09-yol-haritasi-tasklar.md içindeki **E16** görevi (rakip fiyatlarının App Store'dan birebir doğrulanması) tamamlanmış olmalıdır (§4.3).
- **AC-R5:** Bu rapor çeyrekte bir güncellenir; Sensor Tower yeni dönem raporu yayımlandığında §2.1 ve §3 rakamları yeniden doğrulanır. Pazar rakamları hızla eskir (kategori bir yılda ~4x büyüdü) — 6 aydan eski rakam "tarihli veri" olarak işaretlenmelidir.

---

## 2. Doğrulanmış bulgular (9 iddia — dokümanlarda güvenle kullanılabilir)

Aşağıdaki 9 iddia 3 bağımsız hakem oylamasından geçti. Her bulgu için oylama sonucu, kaynak URL'si ve ShortSeries dokümanlarındaki karşılığı verilir.

### 2.1 Pazar büyüklüğü ve rekabet

**D1 — Pazar liderleri ve gelirleri** `[3-0]`
ReelShort ve DramaBox gelirde açık ara pazar lideridir: ReelShort Q1 2025'te $130M ($490M kümülatif), DramaBox $120M ($450M kümülatif) IAP geliri elde etti; ikisi birlikte küresel short-drama IAP'ının ~%70'ini oluşturur.
Kaynak: https://sensortower.com/blog/state-of-short-drama-apps-2025
*Dokümanlardaki karşılık:* 00-genel-bakis.md rakip analizi ve pazar boyutlandırması; 01-ozellik-envanteri.md'nin parite hedefinin ("bu iki uygulamayla neredeyse %100 parite") gerekçesi.

**D2 — İkinci dalga: DramaWave ve NetShort** `[3-0]`
DramaWave Q1 2025'te indirmede çeyreklik 10x'in üzerinde büyümeyle kategorinin en hızlı büyüyen uygulaması oldu (Nisan 2025 itibarıyla 53M kümülatif indirme, ~$47M gelir); NetShort %171 çeyreklik gelir büyümesiyle ~$57M kümülatif gelire ulaştı.
Kaynak: https://sensortower.com/blog/state-of-short-drama-apps-2025
*Dokümanlardaki karşılık:* 00-genel-bakis.md — pazarın yeni girişlere hâlâ açık olduğunun (H2 2024'te çıkan uygulamaların aylar içinde ölçeklendiğinin) birincil kanıtı. ShortSeries'in "geç giriş" riskini dengeleyen ana veri noktası.

**D3 — Birincil rapor teyidi (InvestGame/Sensor Tower PDF)** `[3-0]`
Sensor Tower'ın tam rapor PDF'i aynı liderlik sıralamasını teyit eder: Q1 2025'te ReelShort ~$130M, DramaBox ~$120M çeyreklik IAP geliri (çeyreklik büyüme sırasıyla %31 ve %29).
Kaynak: https://investgame.net/wp-content/uploads/2025/11/State-of-Short-Drama-Apps-Overseas-2025-Report.pdf
*Çelişki notu:* PDF'in "takeaways" kesiti kümülatif gelirleri $521M / $470M olarak verir; D1'deki blog kesiti $490M / $450M der. Fark, iki yayının farklı tarih kesitlerinden kaynaklanır (blog Q1 sonu, PDF daha geç bir kesit). Dokümanlarda kanonik değer olarak **~$490M / ~$450M** kullanılır; kümülatif rakamların "yaklaşık" (~) işaretiyle yazılması zorunludur.
*Dokümanlardaki karşılık:* 00-genel-bakis.md; bu rapor §3 (aynı PDF'ten gelen retention ve ABD payı verileri).

### 2.2 Monetizasyon kalıpları

**D4 — Coin-ile-kilit-açma modeli kategorinin standardıdır** `[3-0]`
ReelShort kilitli bölümleri sanal coin para birimiyle açtırır: kullanıcı coin satın alır ve dizinin sonraki bölümlerini bu coin'lerle açar.
Kaynak: https://en.wikipedia.org/wiki/ReelShort
*Dokümanlardaki karşılık:* 06-monetizasyon.md'nin temel modeli (coin = consumable IAP, bölüm başına `unlockPrice`); WalletKit modül tasarımı; UnlockSheet ve CoinMagazasi ekranlarının varlık gerekçesi.

**D5 — Paywall ilk ~10 dakikadan sonra, cliffhanger noktasında** `[3-0]`
ReelShort paywall'u ilk hikâyenin yaklaşık 10. dakikasına kadar geciktirir; ücretsiz bölümler bittiğinde kilit tam bir cliffhanger anına denk düşer. Bu, kategorinin doğrulanmış "önce bağımlılık, sonra ödeme" akışıdır.
Kaynak: https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop
*Dokümanlardaki karşılık:* Kanonik erişim modeli — "dizi başına ilk 5–10 bölüm ücretsiz (~ilk 10 dakika), sonrası kilitli; kilit cliffhanger noktasına denk gelir" (00-genel-bakis.md, 06-monetizasyon.md). PlayerFeed → UnlockSheet geçiş akışının (02-ekran-haritasi-navigasyon.md) davranış tanımı bu teardown'a dayanır. `unlockPrice` ve kilit noktası istemciye API'den gelir (05-veri-modeli-api.md) — içerik ekibi cliffhanger'ı belirler, istemci hardcode etmez.

**D6 — ReelShort'un agresif abonelik fiyatı ve coin kazanım görevleri** `[3-0]`
Teardown'a göre ReelShort'un abonelik teklifi haftalık $20+ seviyesindedir (yıllıklandırıldığında ~$1.000); coin ise bildirim izni verme, e-posta paylaşma, reklam izleme ve günlük streak sürdürme yollarıyla kazanılabilir.
Kaynak: https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop
*Çelişki notu:* Bu iddia kendi kaynağı içinde tutarlı bulunup 3-0 geçti; ancak başka kaynaklar ReelShort haftalık VIP'ini $5.99'a kadar düşük raporlar (§4). Kanonik kullanım: **ReelShort haftalık VIP $5.99–$20 aralığında çelişkili raporlanıyor** — dokümanlarda aralık olarak yazılır, kesin rakam verilmez, lansman öncesi App Store'dan doğrulanır (E16).
*Dokümanlardaki karşılık:* 07-retention-gamification.md görev listesi tasarımı (OdulMerkezi'ndeki "bildirim iznine coin ödülü" görevi doğrudan bu bulgudan); 06-monetizasyon.md rakip karşılaştırması (aralıkla).

**D7 — DramaBox abonelik merdiveni (kategorinin en net doğrulanmış fiyat seti)** `[3-0]`
DramaBox kademeli abonelik sunar: $3.99 haftalık tanıtım (intro) fiyatı, $5.99 standart haftalık, $13–19 premium içerik kademesi ve $49.99 yıllık plan; ReelShort'un haftalık abonelikleri ise ~$20'den başlar.
Kaynak: https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack
*Dokümanlardaki karşılık:* VIPAbonelik plan kurgusunun benchmark'ı. ShortSeries'in kendi planları (haftalık $5.99 + intro $3.99/ilk hafta, aylık $14.99, yıllık $49.99 — 06-monetizasyon.md) DramaBox kalıbını temel alır; bu, kategoride kesin fiyatı doğrulanabilmiş tek abonelik merdiveni olduğu için bilinçli bir tercihtir.

**D8 — Cüzdan backend'inin zorunlu nitelikleri** `[2-1]`
Üretim kalitesinde bir coin-cüzdan backend'i şunları gerektirir: idempotent işlemler (her işlem benzersiz ID ile güvenle yeniden denenebilir), double-entry (çift kayıt) muhasebe, **purchased vs earned coin ayrımı** (kazanılmış coin App Store komisyonuna tabi değildir), audit trail, gerçek zamanlı bakiye için write-through cache (tipik olarak Redis) ve fraud tespiti (receipt replay, jailbreak'li cihaz istismarı, anormal kazanç hızı). Kaynak, deneyimli bir ekip için ~4–6 haftalık efor öngörür.
Kaynak: https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack
*Oylama notu:* 2-1 — karşı oy yalnız "4–6 hafta" efor tahmininin doğrulanamazlığına yönelikti; mimari gereksinimler tartışmasız kabul edildi. Efor tahmini planlamada bağlayıcı değildir (09-yol-haritasi-tasklar.md kendi tahminlerini kullanır).
*Dokümanlardaki karşılık:* 05-veri-modeli-api.md cüzdan API sözleşmesi (idempotency key, transaction ledger); 06-monetizasyon.md purchased/earned ayrımı ve "earned önce harcanır" kuralı; WalletKit'te `WalletStore` actor'ünün sunucu-otoriter tasarımı (istemci bakiyeyi asla kendisi hesaplamaz).

### 2.3 Player mühendisliği

**D9 — Dikey player performans hedefleri ve HLS profili** `[3-0]`
Mikro-drama dikey video player'ı şu hedeflerle kurulmalıdır: time-to-first-frame **< 500 ms**; **2–6 sn** HLS segment süresi; portrait bitrate merdiveni **~300 kbps → 2.5 Mbps** (720p/1080p portrait tepe noktalarıyla).
Kaynak: https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack
*Dokümanlardaki karşılık:* 04-player-engine.md'nin zorunlu performans bütçeleri birebir bu bulgudan türetildi ve kanonlaştırıldı: TTFF < 500 ms, 2–6 sn segment, 240p→1080p merdiven (~300 kbps → 2.5 Mbps), H.264 + HEVC varyantları. Kabul kriteri: PlayerFeed'de p90 TTFF < 500 ms ölçümü AnalyticsKit event şemasıyla (08-analitik-deney.md) sürekli izlenir.

---

## 3. Yüksek güvenli ek bulgular (tek kaynak, oylanmadı)

Aşağıdaki bulgular oylama hattına girmedi (bkz. §1.1 süreç notu) ancak `central`/`primary` etiketli, iç tutarlılığı yüksek ve kanonda benimsenmiş verilerdir. Her satır **"tek kaynak, oylanmadı"** statüsündedir: dokümanlarda kullanılabilir, fakat yanına yaklaşıklık işareti (~) ve gerektiğinde kaynak notu düşülür.

### 3.1 Kategori boyutu ve ABD pazar payı

| # | Bulgu | Kaynak (etiket) | Dokümanlardaki karşılık |
|---|---|---|---|
| Y1 | Kategori Q1 2025: ~$700M IAP geliri (YoY ~4x), >370M indirme; 2024 başından kümülatif ~$2.3B | https://sensortower.com/blog/state-of-short-drama-apps-2025 ve https://investgame.net/wp-content/uploads/2025/11/State-of-Short-Drama-Apps-Overseas-2025-Report.pdf (primary; iki Sensor Tower yayınında tutarlı — fiilen çapraz teyitli) | 00-genel-bakis.md pazar boyutlandırması; kanonda doğrulanmış statüsünde |
| Y2 | ABD, Q1 2025'te kategori gelirinin ~%49'unu üretti (~$350M); 2024 tam yılında pay ~%60'tı. LatAm (%69) ve Güneydoğu Asya (%61) çeyreklik indirme büyümesinde lider | InvestGame PDF (primary) | 00-genel-bakis.md hedef pazar kararı: **ABD öncelikli, EN-first lokalizasyon**; TR/ES/PT ikinci dalga |
| Y3 | Hedef demografi ağırlıkla 25–45 yaş kadın | https://adjoe.io/blog/short-drama-apps-rewarded-engagement/ (secondary) | 00-genel-bakis.md hedef kitle tanımı; içerik/kreatif brief'leri |
| Y4 | Büyüme ağır biçimde paid-UA güdümlü: 2024'te indirmelerin ReelShort için ~%70'i, DramaBox/ShortMax için >%60'ı ücretli; DramaWave'de >%73–80 (Unity ~%98 impression payı). DramaBox+ShortMax+ReelShort 2024 indirmelerinin %76'sını aldı | https://sensortower.com/blog/short-drama-redefines-mobile-entertainment-and-challenges-games ve InvestGame PDF (primary) | 00-genel-bakis.md risk bölümü: **organik büyüme beklentisi düşük tutulmalı**; lansman planında UA bütçesi varsayımı (kapsam: pazarlama, bu doküman setinin dışında) |
| Y5 | DramaWave farklılaşması: güçlü lokalizasyon, çok dilli altyazı, sık içerik güncellemesi; ABD App Store puanı 4.9 | InvestGame PDF (primary) | 00-genel-bakis.md konumlanma; Ayarlar'daki altyazı dili desteğinin (uygulama + altyazı dili ayrımı) parite gerekçesi |

### 3.2 Retention benchmarkları

| # | Bulgu | Kaynak (etiket) | Dokümanlardaki karşılık |
|---|---|---|---|
| Y6 | Kategori ortalaması: D1 ~%27 (26.9), D7 ~%8.6, D14 ~%5.6; DramaBox özelinde D1 %27.5 / D7 %7.8 / D14 %5.0 (Sensor Tower verisiyle) | https://adjoe.io/blog/short-drama-apps-rewarded-engagement/ (secondary) | 08-analitik-deney.md KPI hedeflerinin tabanı. ShortSeries hedefleri bu benchmark'ın üstüne konuldu: **D1 ≥ %30, D7 ≥ %10, D30 ≥ %5** |
| Y7 | DramaBox uzun vadeli retention: 6. ayda %17, 12. ayda %15 (2024) | InvestGame PDF (primary) | 07-retention-gamification.md — abonelik ağırlıklı modelin uzun vadeli retention avantajı; VIPAbonelik'in retention aracı olarak konumlanması |
| Y8 | Rewarded engagement kullanan kullanıcılar ~3x daha sık geri dönüyor (ortalama 16.3 vs 5.0 dönüş günü) | https://adjoe.io/blog/short-drama-apps-rewarded-engagement/ (secondary) | 07-retention-gamification.md — OdulMerkezi'nin (check-in + görevler + rewarded ad kartı) varlık gerekçesi; rewarded ads'in (Faz 2) yalnız gelir değil retention aracı olduğu tezi |

> **Kullanım notu:** ShortSeries retention hedefleri (D1 ≥ %30 vb.) benchmark değil **hedef**tir; benchmark rakamlarıyla karıştırılmamalıdır. 08-analitik-deney.md'de kohort raporları her iki seti ayrı kolonlarda gösterir.

### 3.3 Player pooling ve prefetch sayıları

Bu grup `blog` etiketli ama mühendislik açısından en güçlü kaynaklardan gelir (Mux mühendislik blogu, ölçümlü AVFoundation yazıları) ve Apple birinci taraf dokümantasyonuyla uyumludur. Tamamı 04-player-engine.md'de kanonlaştırıldı.

| # | Bulgu | Kaynak (etiket) | Dokümanlardaki karşılık |
|---|---|---|---|
| Y9 | TikTok-tarzı feed'in kanıtlanmış kalıbı: `UICollectionView` dikey paging + önceden yaratılmış AVPlayer havuzu + player başına buffer ayarı + kaydırma yönüne duyarlı prefetch | https://www.mux.com/blog/building-tiktok-smooth-scrolling-on-ios (blog — sektör standardı mühendislik yazısı) | Kanonik mimari karar: player feed **UIKit'tir**, SwiftUI'ye `UIViewControllerRepresentable` köprüsüyle bağlanır (03-mimari.md, 04-player-engine.md) |
| Y10 | Sabit 3–5 player'lık havuz gerekir; yeni AVPlayer ayağa kaldırmanın cold-start maliyeti onlarca ms — havuz yeniden kullanımı "anında swipe-to-next"in ön koşulu | https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/ (blog) | `PlayerPool` actor'ü, havuz boyutu 3–5 (04-player-engine.md); swipe-to-next < 100 ms bütçesi |
| Y11 | Sonraki video için prefetch bütçesi: ~500 KB veya ilk 2 sn (hangisi önce dolarsa); tam video asla önden indirilmez | https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/ (blog) | `PrefetchController` bütçesi (04-player-engine.md) |
| Y12 | `preferredForwardBufferDuration = 1 sn` ekran dışı player'ların ağ yükünü ölçülü biçimde düşürür: 37.8 MB → 0.2 MB | https://medium.com/@sojik/avplayer-video-optimization-part-1-2a45ea002ea2 (blog — ölçüm içerir); API referansı: https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration (primary) | Kanonik buffer politikası: aktif player = 0 (otomatik), havuzdaki idle player = 1 sn |
| Y13 | Performans bütçeleri: cold start'ta ilk video < 500 ms, swipe-to-next < 100 ms, kesintisiz 60 fps; ~200 MB LRU disk cache; hücresel veri tasarrufu modunda 480p + prefetch durdur + autoplay kapat | https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/ (blog) | 04-player-engine.md zorunlu bütçeler; Ayarlar'daki "veri tasarrufu" oynatma tercihinin davranış tanımı |
| Y14 | HLS segmentleri basit URL interception ile cache'lenemez; offline/ön-indirme için `AVAssetDownloadTask` gerekir (`AVAssetResourceLoaderDelegate`/CachingPlayerItem yalnız MP4'te çalışır) | https://developer.apple.com/forums/thread/649810 (primary — birinci taraf forum) | Kanonik HLS cache kararı (04-player-engine.md); Listem → İndirilenler (Faz 3) mimarisinin ön koşulu |

Y12'nin koda birebir yansıması (ayrıntılı sözleşme 04-player-engine.md'dedir; burada yalnız bulgu→karar izlenebilirliği için):

```swift
// PlayerKit — Y12/Y13 bulgularının kanonlaşmış hâli.
// Kaynak ölçüm: idle buffer 1 sn → ekran dışı ağ yükü 37.8 MB → 0.2 MB (Mingalev).
enum PlayerBufferPolicy {
    /// Aktif (ekrandaki) player: 0 = süreyi AVFoundation otomatik yönetir.
    static let activeForwardBuffer: TimeInterval = 0
    /// Havuzdaki idle player: 1 sn — prefetch maliyetini sınırlar.
    static let idleForwardBuffer: TimeInterval = 1
}

func applyBufferPolicy(to item: AVPlayerItem, isActive: Bool) {
    item.preferredForwardBufferDuration = isActive
        ? PlayerBufferPolicy.activeForwardBuffer
        : PlayerBufferPolicy.idleForwardBuffer
}
```

**Mühendislik kaynakları arasındaki çelişkiler ve verilen kararlar:**

- *HLS vs progressive MP4:* Bir kaynak (techinterview.org) kısa videolar için fast-start progressive MP4'ü, diğerleri (Mux, FastPix, Spyro Soft) HLS'i önerir. **Karar: HLS** (adaptive bitrate + DRM yolu + CDN uyumu); MP4 fast-start + `AVAssetResourceLoaderDelegate` yalnızca "değerlendirilen alternatif" olarak anılır (04-player-engine.md).
- *AsyncDisplayKit/Texture önerisi:* Eski bir kaynak feed için Texture (off-main-thread layout) önerir. **Reddedildi:** bakımı zayıf üçüncü parti bağımlılık; modern `UICollectionView` + prefetch API'leri aynı 60 fps hedefini karşılar (Y9 kalıbı).
- *FastPix'in manifest preload snippet'i:* `.m3u8` URL'sini JavaScript `Image()` ile ön-yükleme tekniği web'e özgü ve teknik olarak şüphelidir; iOS'ta karşılığı yoktur. FastPix yalnız özellik envanteri ve genel HLS mimarisi için kullanıldı, kod örnekleri **kullanılmadı**.

---

## 4. Çürütülen / tutarsız iddialar ve alınan ders

### 4.1 Çürütülen iddialar tablosu

Aşağıdaki 13 iddia hakem oylamasında elendi (2/3 veya 3/3 çürütme). Ortak örüntü açık: **fiyat ve kota ayrıntıları kaynaktan kaynağa ciddi biçimde çelişiyor.**

| # | İddia (özet) | Oylama | Kaynak | Neden elendi / dokümanlardaki karşılık |
|---|---|---|---|---|
| Ç1 | ReelShort coin paketleri $4.99–$99.99, bonus %15–100, ilk yükleme 1300+1300 coin/$12.99 | 0-3 | ResearchGate vaka çalışması | Diğer kaynaklar $0.99–$99.99, $1.99–$50 gibi farklı aralıklar verir; paket yapısı tarihe/bölgeye göre değişken. Karşılık: yalnız aralık, E16 doğrulaması |
| Ç2 | ReelShort bölüm başı kilit maliyeti $0.36–$1.11; rewarded ile günde 20 bölüm açılabilir | 0-3 | ResearchGate | Bölüm fiyatı diğer kaynaklarda ~18 coin (~$0.18) ile 100+ coin arasında; "20/gün" cap'i başka hiçbir kaynakta yok (diğerleri 5/gün der). Karşılık: bölüm kilidi "~18–100 coin" aralığı |
| Ç3 | ReelShort gelir karışımı: %71 bölüm-başı ödeme / %21 reklam | 0-3 | ResearchGate | Birincil veriyle teyit edilemedi; kaynağın veri zinciri (TikTok for Business → şirket sitesi) zayıf. Karşılık: gelir karışımı oranı hiçbir dokümanda kullanılmaz |
| Ç4 | DramaWave VIP: $19.90/ay + $19.90/hafta + $9.99 tek seferlik teklif | 1-2 | InvestGame PDF (uygulama profili sayfası) | Haftalık ile aylığın aynı fiyat olması şüpheli bulundu; tek kaynak. Karşılık: "~$19.90 + $9.99 tek seferlik (tek kaynak, temkinli)" ibaresiyle anılır, kesin rakam değil |
| Ç5 | ReelShort'ta coin yalnız iki yolla edinilir: reklam izleme veya satın alma | 0-3 | Wikipedia | Eksik/yanlış: check-in, görev ve streak kazanımlarını dışlıyor (D6 ile çelişir). Karşılık: kazanım yolları D6'ya göre yazıldı |
| Ç6 | Rewarded ad, sonraki ~2 dakikalık segmenti açar; oturum başına 5 cap | 0-3 | Consume Our Internet | Cap değeri kaynaklar arasında 5/oturum, 5/gün, 20/gün diye çelişiyor; "segment açma" ile "bölüm açma" ayrımı tutarsız. Karşılık: ShortSeries kendi tasarımını kullanır — **günde 5–10 cap, remote config'ten** (06-monetizasyon.md) |
| Ç7 | DramaBox çift erişimli freemium: abonelik + reklam destekli ücretsiz erişim | 0-3 | Emizentech | Genelleme; DramaBox'ın gerçek modeli coin + abonelik karışımı, "reklam destekli tam erişim" doğrulanamadı. Karşılık: DramaBox "abonelik ağırlıklı" diye anılır |
| Ç8 | DramaBox-benzeri uygulamanın özellik seti: çok dilli altyazı + offline izleme + watchlist | 0-3 | Emizentech | Özellikler tek tek doğru olabilir ama kaynak pazarlama içeriği; hangi uygulamada hangisinin var olduğu doğrulanamadı. Karşılık: 01-ozellik-envanteri.md parite matrisi yalnız teardown/primary kaynaklara dayanır |
| Ç9 | Standart kalıp: 5–10 ücretsiz bölüm + coin paketleri $0.99/$4.99/$19.99/$49.99/$99.99 | 0-3 | Klon-rehberi blogları (Flicknexs ve benzerleri) | Ücretsiz bölüm sayısı kalıbı D5 ile uyumlu olsa da paket fiyat listesi diğer kaynaklarla çelişir. Karşılık: erişim modeli D5'ten; paket fiyatları ShortSeries'in kendi tasarımı olarak yazılır |
| Ç10 | DramaBox: 1–7. bölümler ücretsiz, $14.99/ay premium abonelik | 0-3 | MakeAnAppLike | D7'nin doğrulanmış merdiveniyle ($5.99 haftalık / $49.99 yıllık) çelişir. Karşılık: DramaBox fiyatları yalnız D7'den |
| Ç11 | ReelShort: 'ReelShort+' $19.99/ay abonelik + $0.99–$99.99 coin paketleri | 0-3 | MakeAnAppLike | D6/D7 haftalık-$20 bulgusuyla ve diğer paket listeleriyle çelişir. Karşılık: ReelShort aboneliği "haftalık $5.99–$20 çelişkili" aralığıyla |
| Ç12 | Kilitli bölüm 50–200 coin (~$0.10–$0.20); 80 bölümlük seri toplam $30–50 | 0-3 | Spyro Soft | Bölüm başı coin ve seri toplamı kaynaklar arasında ($10–20'den $37–47'ye) çelişiyor. Karşılık: "seri tamamlama ~$10–50" geniş aralığı, kesin rakam yok |
| Ç13 | Rewarded unlock: 30 sn %100 tamamlama, günde 5 cap, $15–40 CPM (ABD/UK) | 0-3 | Spyro Soft | CPM aralığı ve cap tek kaynaklı, diğer kaynaklarla çelişkili. Karşılık: ShortSeries kendi tasarımı — 30 sn tamamlama şartı + günde 5–10 cap (remote config); CPM rakamı hiçbir dokümanda kullanılmaz |

### 4.2 Neden bu kadar tutarsız? (yapısal analiz)

Fiyat iddialarının toplu çöküşü araştırma hatası değil, **kategorinin yapısal özelliği**dir; dokümantasyon buna göre tasarlandı:

1. **Rakipler fiyatı sürekli A/B testliyor.** Aynı uygulamada iki kullanıcı farklı coin paketi ve farklı VIP fiyatı görebilir; blog yazarları kendi gördükleri varyantı "fiyat listesi" diye yayımlıyor.
2. **Bölgesel lokalizasyon.** ReelShort minimum yüklemeyi pazarın alım gücüne göre değiştiriyor (ör. Filipinler'de ~$2 minimum; en popüler paket ABD'de $9.99 iken Filipinler'de ~$5 — tek kaynak, oylanmadı; yalnız bağlam). ABD fiyatıyla başka pazarın fiyatı aynı tabloya karışıyor.
3. **Zaman kayması.** Kaynaklar 2023–2026 arasına yayılıyor; kategori bu dönemde ~4x büyüdü ve fiyatlama agresif biçimde evrildi. Çoğu blog tarih damgası vermiyor.
4. **Blogdan bloga kopya.** Klon-rehberi siteleri birbirinden rakam kopyalıyor; aynı yanlış üç "bağımsız" kaynakta görünüp sahte teyit üretebiliyor. Hakem süreci bu yüzden kaynak bağımsızlığını da denetledi.

### 4.3 DERS ve mühendislik sonuçları

**Ders:** Rakip fiyat ayrıntısı (coin paket fiyatları, haftalık VIP fiyatı, bölüm başı maliyet) güvenilir biçimde masabaşı araştırmayla saptanamıyor. Bu nedenle:

- **Dokümanlarda aralık kullanıldı:** ReelShort haftalık VIP "$5.99–$20 (çelişkili)", bölüm kilidi "~18–100 coin", seri tamamlama "~$10–50". Bu aralıklar 00-genel-bakis.md ve 06-monetizasyon.md'de her zaman "lansman öncesi güncel App Store fiyatları doğrulanmalı" notuyla geçer (AC-R2).
- **Lansman öncesi doğrulama görevi açıldı:** 09-yol-haritasi-tasklar.md **E16** — "Rakip fiyatlarının App Store'dan birebir doğrulanması". Kapsamı ve kabul kriterleri:
  - ABD App Store'dan (ve TR ikinci dalga öncesi TR mağazasından) ReelShort, DramaBox, NetShort, DramaWave uygulamaları indirilip **uygulama içinden** CoinMagazasi/VIP muadili ekranların ekran görüntüleri alınır (App Store ürün sayfasındaki "In-App Purchases" listesiyle birlikte — ikisi farklı olabilir, A/B nedeniyle).
  - Çıktı: uygulama × SKU × fiyat × bonus × tarih kolonlu tek tablo; 06-monetizasyon.md'deki rakip benchmark tablosu bu tabloyla güncellenir, bu rapordaki §4.1 satırlarına "E16 sonucu" dipnotu düşülür.
  - Ücretsiz bölüm sayısı, rewarded cap ve ilk-yükleme teklifi her uygulamada en az bir dizi üzerinden fiilen gözlemlenir.
  - Kabul kriteri: 4 uygulamanın 4'ü için güncel (≤ 2 hafta) fiyat verisi toplanmış ve ShortSeries fiyat kararlarını etkileyen sapma varsa (±%20'den fazla) 06-monetizasyon.md sahibiyle karar kaydı açılmış olmalı.
- **İstemci mimarisine yansıması — fiyat asla hardcode edilmez:** Rakiplerin fiyatı bu kadar akışkansa ShortSeries'inki de akışkan olmalıdır. Bölüm kilidi `unlockPrice` alanıyla API'den gelir (05-veri-modeli-api.md), coin paketi/VIP kataloğu StoreKit 2 ürün listesi + remote config ile yönetilir, rewarded cap remote config'tedir (06-monetizasyon.md). İstemcide tek bir fiyat sabiti bulunmaz:

```swift
// ContentKit/WalletKit — §4.3 dersinin veri sözleşmesine yansıması.
// Fiyat/kota istemcide sabitlenmez; tamamı sunucu kaynaklıdır.
struct UnlockQuote: Codable {
    let episodeID: String
    let unlockPrice: Int          // coin — API'den (05-veri-modeli-api.md)
    let adUnlockRemaining: Int    // bugünkü kalan rewarded hakkı (cap remote config'te)
    let vipBypassAvailable: Bool  // VIP entitlement kilidi kaldırıyor mu
}
```

---

## 5. Doğrulanamayan iddialar (oylama tamamlanamadı — temkinli kullan)

Oturum limiti nedeniyle şu 3 iddianın hakem oylaması yarım kaldı. Statüleri "ne doğrulanmış ne çürütülmüş"tür; dokümanlarda **yalnız nitel yön** olarak (rakamsız) kullanılabilir:

| # | İddia | Temkinli kullanım kuralı |
|---|---|---|
| B1 | DramaBox'ın coin paketleri ReelShort'unkilerden daha ucuz (küçük paketler ~$0.99–$1.99 vs ~$1.99+; orta/büyük $4.99–$19.99 vs $4.99–$29.99+) | Rakam kullanılmaz. "DramaBox fiyat algısında daha erişilebilir konumlanıyor" nitel cümlesi serbest. E16 kesin veriyi getirir |
| B2 | DramaBox abonelik seçeneği sunarken ReelShort ağırlıkla bölüm-başı coin modeline dayanır | Nitel yön D7 ile uyumlu ve kullanılabilir ("DramaBox abonelik ağırlıklı, ReelShort coin ağırlıklı"); "minimal or no subscription" gibi mutlak ifadeler kullanılmaz (D6 ReelShort aboneliğinin varlığını doğruluyor) |
| B3 | DramaBox, ReelShort'a göre daha fazla ücretsiz bölüm veriyor | Nitel olarak anılabilir; sayısal karşılaştırma (ör. "7'ye karşı 5 bölüm") yazılamaz. E16 gözlem adımı netleştirir |

---

## 6. Kaynak listesi

### 6.1 Ana kanıt tabanı (18 kaynak)

Kalite etiketi: **primary** = birincil veri sahibi (pazar ölçüm firması, birinci taraf platform); **secondary** = ikincil derleme (ansiklopedi, akademik vaka, veri sahibi ad-tech); **blog** = üçüncü taraf blog/rehber (iç tutarlılığına göre değerlendirilir).

| # | Kaynak | URL | Kalite | Girdi verdiği bölümler/dokümanlar |
|---|---|---|---|---|
| 1 | Sensor Tower — State of Short Drama Apps 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 | primary | §2.1 (D1, D2), §3.1 (Y1); 00-genel-bakis.md |
| 2 | Sensor Tower — Short-Drama Redefines Mobile Entertainment | https://sensortower.com/blog/short-drama-redefines-mobile-entertainment-and-challenges-games | primary | §3.1 (Y4 — paid-UA bağımlılığı, ikinci dalga); 00-genel-bakis.md |
| 3 | Sensor Tower — State of Short Drama Apps 2026 Report | https://sensortower.com/report/state-of-short-drama-apps-2026 | primary | Güncel kategori boyutu içerir; rakamları kanona alınmadı (oylanmadı, Q1 2025 seti korundu) — AC-R5 kapsamındaki ilk güncellemenin birincil adayı |
| 4 | Sensor Tower (InvestGame yayını) — Overseas 2025 Report PDF | https://investgame.net/wp-content/uploads/2025/11/State-of-Short-Drama-Apps-Overseas-2025-Report.pdf | primary | §2.1 (D3), §3.1 (Y2, Y4, Y5), §3.2 (Y7), §4.1 (Ç4); 00-genel-bakis.md, 07-retention-gamification.md |
| 5 | adjoe — Microdramas' Hypergrowth Problems Meet Rewarded Engagement | https://adjoe.io/blog/short-drama-apps-rewarded-engagement/ | secondary | §3.1 (Y3), §3.2 (Y6, Y8); 07-retention-gamification.md, 08-analitik-deney.md |
| 6 | Spyro Soft — Microdrama Monetisation Models (payment stack) | https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack | blog | §2.2 (D7, D8), §2.3 (D9), §4.1 (Ç12, Ç13); 04-player-engine.md, 05-veri-modeli-api.md, 06-monetizasyon.md |
| 7 | Filmustage — ReelShort vs DramaBox in 2026 | https://filmustage.com/blog/short-drama-apps-compared-reelshort-vs-dramabox-in-2026/ | blog | §4 fiyat aralıklarının çelişki kaynağı; 00-genel-bakis.md konumlanma (nitel), 06-monetizasyon.md (aralıklarla) |
| 8 | YourAppLand — DramaBox vs ReelShort Full Comparison | https://yourappland.com/dramabox-vs-reelshort-full-comparison-of-features-and-pricing/ | blog | §4/§5 fiyat çelişkileri (B1–B3'ün kaynağı); 01-ozellik-envanteri.md (nitel parite girdisi) |
| 9 | LootBar — ReelShort Subscription Price Explained | https://www.lootbar.com/blog/en/reelshort-subscription-price-explained.html | blog | D6 çelişki notundaki "$5.99 haftalık" karşı verisi; ReelShort VIP aralığının alt ucu |
| 10 | ResearchGate — ReelShort paid advertising / user behavior vaka çalışması | https://www.researchgate.net/publication/383505184_Analyzing_the_Impact_of_User_Behavior_and_Paid_Advertising_on_App_Revenue_A_Case_Study_of_Reelshort | secondary | §4.1 (Ç1–Ç3 — üçü de çürütüldü); §4.2 lokalize fiyatlandırma içgörüsü (bağlam) |
| 11 | Wikipedia — ReelShort | https://en.wikipedia.org/wiki/ReelShort | secondary | §2.2 (D4), §4.1 (Ç5); 00-genel-bakis.md ReelShort arka planı |
| 12 | Consume Our Internet — ReelShort and the rise of dramaslop | https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop | blog | §2.2 (D5, D6), §4.1 (Ç6); tek gerçek ürün teardown'ı — 02-ekran-haritasi-navigasyon.md UnlockSheet akışı, 06-monetizasyon.md paywall UX, 07-retention-gamification.md (Live Activities gözlemi — Faz 3) |
| 13 | FastPix — How to Build a Micro Drama App | https://www.fastpix.io/tutorials/how-to-build-a-micro-drama-video-app-like-reelshort-or-dramabox | blog | 01-ozellik-envanteri.md ekran/özellik iskeleti; 04-player-engine.md HLS merdiveni (kod örnekleri kullanılmadı — bkz. §3.3 çelişki notu) |
| 14 | Emizentech — Build an App Like DramaBox | https://emizentech.com/blog/app-like-dramabox.html | blog | §4.1 (Ç7, Ç8); 01-ozellik-envanteri.md ve 02-ekran-haritasi-navigasyon.md için ekran listesi iskeleti (nitel) |
| 15 | Flicknexs — Build a Short Drama App Like DramaBox in 2026 | https://blog.flicknexs.com/build-a-short-drama-app-like-dramabox-in-2026/ | blog | §4.1 (Ç9); 07-retention-gamification.md retention özellik envanteri (check-in, streak, görevler — nitel) |
| 16 | Mux Engineering — Building TikTok: smooth scrolling video feed on iOS | https://www.mux.com/blog/building-tiktok-smooth-scrolling-on-ios | blog | §3.3 (Y9); 03-mimari.md ve 04-player-engine.md'nin UIKit player feed kararının birincil dayanağı |
| 17 | techinterview.org — Design TikTok-Style Video Feed | https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/ | blog | §3.3 (Y10, Y11, Y13); 04-player-engine.md havuz/prefetch/cache bütçeleri |
| 18 | Sergey Mingalev — AVPlayer Video Optimization (part 1) | https://medium.com/@sojik/avplayer-video-optimization-part-1-2a45ea002ea2 | blog | §3.3 (Y12); 04-player-engine.md buffer politikası (ölçümlü) |

### 6.2 Teknik referans / yardımcı kaynaklar (6)

| # | Kaynak | URL | Kalite | Kullanım |
|---|---|---|---|---|
| E1 | Apple Developer Documentation — preferredForwardBufferDuration | https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration | primary | Y12 buffer politikasının resmi API dayanağı (04-player-engine.md) |
| E2 | Apple Developer Forums — How to cache an HLS video while playing | https://developer.apple.com/forums/thread/649810 | primary | Y14 — HLS cache kararının birinci taraf teyidi (04-player-engine.md) |
| E3 | GenesisKit — Build a TikTok-like Feed on iOS (SwiftUI + UIKit) | https://medium.com/@olufemiaghe/build-a-tiktok-like-feed-on-ios-swiftui-uikit-smooth-scrolling-video-with-genesiskit-5ebacce0e877 | blog | SwiftUI↔UIKit köprüsünün referans implementasyonu (03-mimari.md — yalnız desen doğrulama) |
| E4 | MakeAnAppLike — Top 10 Vertical Drama Apps | https://makeanapplike.com/article/list/top-10-vertical-drama-apps | blog | §4.1 (Ç10, Ç11 — fiyatları çürütüldü); pazar manzarası yalnız nitel bağlam |
| E5 | MAF — Microdramas: Blending Drama and Rewarded Advertising | https://maf.ad/en/blog/microdramas-rewarded-advertising/ | blog | Rewarded ad teklifinin cliffhanger anına yerleşimi (07-retention-gamification.md UX gerekçesi — nitel) |
| E6 | Haleigh Dixon — Is ReelShort Worth It? (kullanıcı incelemesi) | https://www.haleighdixon.com/technology/is-reelshort-worth-it-review | blog | Ödül biriktirme döngüsünün kullanıcı gözünden doğrulaması (07-retention-gamification.md — nitel, veri derinliği düşük) |

---

## 7. Araştırma boşlukları ve gelecek araştırma önerileri

Aşağıdaki boşluklar bilinçli olarak açık bırakıldı; her biri için öneri, etkilenen doküman ve öncelik verilir.

### 7.1 NetShort ve DramaWave ekran-ekran teardown'ı yok (öncelik: yüksek)

Elimizdeki tek gerçek ürün teardown'ı ReelShort içindir (kaynak 12). NetShort ve DramaWave için yalnız pazar verisi ve App Store meta verisi var; onboarding akışı, UnlockSheet muadili, ödül merkezi kurgusu ve bölüm listesi UX'i **doğrudan gözlenmedi**.
**Öneri:** App Store'dan iki uygulamayı indirip elle, ekran-ekran inceleme (E16 fiyat doğrulamasıyla aynı oturumda yürütülebilir; ekran kayıtları + akış diyagramı çıktısı). Sonuçlar 01-ozellik-envanteri.md parite matrisine ve 02-ekran-haritasi-navigasyon.md akış karşılaştırmalarına işlenir.
**Riski:** Parite hedefimiz dört benchmark uygulamayı kapsıyor; ikisinin ürün ayrıntısını görmeden "neredeyse %100 parite" iddiası ancak ReelShort/DramaBox düzeyinde savunulabilir.

### 7.2 AI-generated içerik kabulüne dair veri yok (öncelik: yüksek)

Tüm benchmark veriler insan yapımı (filmed) içerikle çalışan uygulamalardan geliyor. ShortSeries'in içeriği AI üretim hattından çıkacak (00-genel-bakis.md); kullanıcıların AI-generated dizilere ödeme isteği, retention farkı veya algı cezası hakkında **hiçbir kaynak veri sunmuyor**. Bu, projenin en büyük doğrulanmamış varsayımıdır.
**Öneri:** (a) Lansman öncesi küçük ölçekli kreatif testi — paid-UA reklam kreatifleriyle tıklama/yükleme oranı ölçümü; (b) ilk kohortlarda içerik kaynağı algısını ölçen event'ler ve D1/D7 kohort karşılaştırması; (c) içerik açıklama/etiketleme stratejisinin (AI ibaresi gösterilsin mi, nasıl?) A/B deneyi. Ölçüm tasarımı 08-analitik-deney.md'ye, deney sonuçlarına göre hedef revizyonu bu rapora işlenir.

### 7.3 Türkiye pazarı verisi yok (öncelik: orta)

TR, ikinci dalga lokalizasyon dilidir; ancak elimizde TR short-drama tüketimi, alım gücüne göre coin/VIP fiyat kademesi veya yerel rakip verisi yok. §4.2'deki bölgesel fiyat lokalizasyonu bulgusu, TR fiyatlarının ABD fiyatlarının kopyası olamayacağını gösteriyor.
**Öneri:** TR dalgasından önce ayrı araştırma kolu: TR App Store'da kategori taraması, benchmark uygulamaların TR fiyat kademeleri (E16 metodolojisiyle), TR ödeme davranışı. Çıktılar 06-monetizasyon.md fiyat lokalizasyonu bölümüne girer.

### 7.4 Diğer açık boşluklar (öncelik: düşük–orta)

| Boşluk | Durum | Öneri / etkilenen doküman |
|---|---|---|
| Rewarded ad eCPM verisi | Tek iddia vardı, çürütüldü (Ç13) | AdMob entegrasyonu (Faz 2) öncesi mediation ortaklarından güncel eCPM aralığı alınır; 06-monetizasyon.md gelir modellemesi |
| FairPlay DRM uygulama maliyeti/karmaşıklığı | Kaynaklar yalnız "DRM + imzalı URL kullanın" düzeyinde (nitel) | Faz 2 öncesi teknik spike; 04-player-engine.md ve 05-veri-modeli-api.md |
| Kategori yoğunlaşması güncel verisi (2026 raporu: 717 uygulama, top-5 %68.8 gelir payı) | Tek kaynak (kaynak 3), oylanmadı; kanon dışı | AC-R5 çeyreklik güncellemesinde oylamaya alınıp 00-genel-bakis.md'ye taşınabilir |
| Push bildirim frekans/etki benchmarkları | Yalnız nitel kaynak var (Ç/E5 düzeyi) | Kendi verimizle ölçülür: 07-retention-gamification.md push stratejisi + 08-analitik-deney.md deneyleri |
| Android tarafı | Bilinçli kapsam dışı (iOS istemci projesi) | — |

---

*Bu rapor doküman setinin kanıt tabanıdır; içerik değişikliği gerektiren her yeni araştırma bulgusu önce buraya (oylama statüsüyle) işlenir, sonra ilgili dokümanlara yayılır (AC-R1).*
