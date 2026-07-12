# ShortSeries — Ürün Vizyonu ve Pazar Analizi

**Amaç:** Bu doküman ShortSeries iOS istemcisinin ürün vizyonunu, hedeflediği pazarın büyüklüğünü ve dinamiklerini, dört benchmark rakibin (ReelShort, DramaBox, NetShort, DramaWave) ayrıntılı analizini, ShortSeries'in konumlanma ve farklılaşma stratejisini, hedef kitle/pazar tanımını, başarı metriklerini (KPI hedefleri) ve temel riskleri tek yerde tanımlar. Geliştirme ekibi için "neyi, kimin için, neden ve hangi başarı ölçütleriyle yaptığımızın" bağlayıcı referansıdır; tüm alt dokümanlardaki ürün kararları buradaki vizyon ve hedeflerle tutarlı olmak zorundadır.

**İlgili dokümanlar:** README.md (doküman seti haritası), 01-ozellik-envanteri.md (rakip paritesine karşı özellik listesi), 02-ekran-haritasi-navigasyon.md (ekran/sekme yapısı), 03-mimari.md (teknik mimari), 04-player-engine.md (izleme deneyimi performans bütçeleri), 05-veri-modeli-api.md (unlockPrice ve katalog sözleşmeleri), 06-monetizasyon.md (coin/VIP ekonomisinin uygulanması), 07-retention-gamification.md (check-in, görevler, push), 08-analitik-deney.md (KPI ölçüm ve A/B altyapısı), 09-yol-haritasi-tasklar.md (fazlar ve görevler), 10-arastirma-raporu.md (kaynaklı araştırma dökümü).

---

## 1. Ürün vizyonu ve problem/fırsat

### 1.1 Ürün tanımı

ShortSeries, **AI-generated dikey mikro-dizi (short drama) platformunun iOS (Swift) istemcisidir**. İçerikler ayrı bir projede AI üretim hattında üretilir ve backend + CDN üzerinden uygulamaya servis edilir; **iOS istemcisi içerik üretmez, tüketir**. Kullanıcı uygulamayı açtığında doğrudan videoyla karşılaşır (Ana Sayfa = `PlayerFeed`), 1–3 dakikalık bölümler halinde kurgulanmış dizileri dikey tam ekran akışta izler, cliffhanger noktasında kilitli bölümle karşılaşır ve coin / rewarded ad / VIP yollarından biriyle kilidi açar.

Benchmark uygulamalar: **ReelShort, DramaBox, NetShort, DramaWave**. Hedef, bu uygulamalarla **neredeyse %100 özellik paritesidir** (parite matrisi için bkz. 01-ozellik-envanteri.md).

### 1.2 Kuzey yıldızı (öncelik sırasıyla)

1. **Akıcı, kesintisiz izleme deneyimi** — time-to-first-frame < 500 ms, swipe-to-next < 100 ms, 60 fps kaydırma (teknik bütçeler: 04-player-engine.md).
2. **Kullanıcının platformdan çıkmak istememesi (retention)** — cliffhanger + otomatik sonraki bölüm binge döngüsü, günlük check-in, görevler, push (07-retention-gamification.md).
3. **Aradığı her şeyi kolayca bulabilmesi (discovery)** — `Kesfet` rafları, `Arama`, kişiselleştirilmiş For You akışı (02-ekran-haritasi-navigasyon.md).

Bir ürün kararı bu üç önceliği birbirine düşürüyorsa, sıralama bağlayıcıdır: izleme deneyimi > retention > discovery. Örnek: `UnlockSheet` paywall'u retention için agresifleştirmek isteyen bir deney, oynatma akıcılığını (ör. sheet animasyonunun feed'i takıltması) bozuyorsa reddedilir.

### 1.3 Problem ve fırsat

**Kategorinin problemi — içerik üretim maliyeti:** Kategori liderleri gerçek oyuncu ve setlerle çekim yapar. Kamuya yansıyan verilere göre bir ReelShort dizisinin (60–90 bölüm) ortalama prodüksiyon maliyeti **~$300K** seviyesindedir (kaynak: https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop — tek kaynaklı sektör tahmini, kesin muhasebe verisi değildir); lisanslı içerik operatörleri için seri başına içerik edinim maliyeti $150K–$250K aralığında raporlanmıştır (https://filmustage.com/blog/short-drama-apps-compared-reelshort-vs-dramabox-in-2026/). Bu maliyet yapısı iki sonuç doğurur:

- Katalog genişletme hızı sermaye ile sınırlıdır; her yeni dizi bir prodüksiyon yatırımıdır.
- Maliyeti geri kazanma baskısı, agresif paywall ve pahalı fiyatlamayı zorlar (bkz. §7.4 fiyat şikayetleri riski).

**ShortSeries'in fırsatı — AI üretim hattı:** İçerik AI hattında üretildiği için:

| Boyut | Geleneksel prodüksiyon (rakipler) | AI üretim hattı (ShortSeries) |
|---|---|---|
| Seri başı maliyet | ~$300K (ReelShort ortalaması, tek kaynak) / $150K–$250K lisans | Marjinal maliyet dramatik ölçüde düşük; asıl maliyet hesaplama + kürasyon |
| Katalog genişletme | Sermaye ve çekim takvimiyle sınırlı | İterasyon hızıyla sınırlı; tema/tür denemeleri ucuz |
| Yerelleştirme | Dublaj/altyazı sonradan eklenir | Çok dilli üretim hatta yerleşik olabilir (EN başta, TR/ES/PT ikinci dalga) |
| Veri döngüsü | İzleyici verisi bir sonraki çekime aylar sonra yansır | İzleme/terk verisi üretim hattına hızlı geri beslenebilir |

**Fırsatın sınırı (dürüst değerlendirme):** Maliyet avantajı ancak içerik kalitesi algısı eşiği aşılırsa değere dönüşür. Kategori zaten "düşük prodüksiyon değeri, hızlı twist" formatına alışkındır (bu bir avantajdır — çıta sinema değil, duygusal kanca), ama AI içerik algısı ayrı bir risktir ve §7.3'te azaltma stratejileriyle ele alınır.

**Vizyon cümlesi:** *"Kullanıcının cebinde, açar açmaz oynayan, hiç bitmeyen ve ona göre yazılmış bir dizi kanalı: AI üretim hattının maliyet ve hız avantajını, kategorinin en akıcı izleme deneyimi ve en adil hissettiren ödeme modeliyle birleştirmek."*

---

## 2. Pazar büyüklüğü ve büyüme

Aşağıdaki rakamlar doğrulanmış verilerdir (Sensor Tower / InvestGame). Bu tablo dışındaki hiçbir pazar rakamı dokümanlarda "kesin veri" olarak kullanılamaz; kaynaklar arası tutarsız fiyat/oran verileri yalnızca "aralık, doğrulanmalı" notuyla anılır (bkz. 10-arastirma-raporu.md).

| Metrik | Değer | Dönem | Kaynak |
|---|---|---|---|
| Kategori IAP geliri | ~$700M (YoY ~4x) | Q1 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| Kategori indirme | >370M | Q1 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| Kümülatif kategori geliri | ~$2.3B | 2024 başından itibaren | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| ReelShort geliri | $130M çeyreklik / ~$490M kümülatif | Q1 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| DramaBox geliri | $120M çeyreklik / ~$450M kümülatif | Q1 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| ReelShort + DramaBox pazar payı | Küresel short-drama IAP'ının ~%70'i | Q1 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| DramaWave büyümesi | İndirmede 10x çeyreklik büyüme; 53M kümülatif indirme; ~$47M gelir | Q1 2025 / Nisan 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| NetShort büyümesi | %171 çeyreklik gelir büyümesi; ~$57M kümülatif gelir | Q1 2025 | https://sensortower.com/blog/state-of-short-drama-apps-2025 |
| ABD gelir payı | Kategori gelirinin ~%49'u (Q1 2025); kaynaklara göre ~%49–60 bandı | Q1 2025 / 2024 | https://sensortower.com/blog/state-of-short-drama-apps-2025 , https://investgame.net/wp-content/uploads/2025/11/State-of-Short-Drama-Apps-Overseas-2025-Report.pdf |
| Kategori retention ortalaması | D1 ~%27, D7 ~%8.6, D14 ~%5.6 | 2024–2025 | https://adjoe.io/blog/short-drama-apps-rewarded-engagement/ |
| DramaBox uzun vadeli retention | 6. ay %17 / 12. ay %15 | 2024 | https://investgame.net/wp-content/uploads/2025/11/State-of-Short-Drama-Apps-Overseas-2025-Report.pdf |
| Rewarded engagement etkisi | Rewarded engagement kullanan kullanıcılar ~3x daha sık geri dönüyor | 2024–2025 | https://adjoe.io/blog/short-drama-apps-rewarded-engagement/ |

### 2.1 Pazardan çıkan ürün sonuçları

1. **Pazar büyük ve hâlâ hiper-büyümede** (~4x YoY IAP geliri). Kategoriye giriş penceresi açık; ama iki lider IAP'ın ~%70'ini alıyor — kazanma stratejisi liderle kafa kafaya değil, ikinci dalga oyuncuların (DramaWave, NetShort) kanıtladığı "hızlı büyüyen challenger" oyun kitabıdır (bkz. §4).
2. **İkinci dalga mümkün:** DramaWave ve NetShort 2024 H2'de çıkıp aylar içinde on milyonlarca indirme ve on milyonlarca dolar gelire ulaştı. Kategori "kazanan her şeyi aldı" aşamasında değildir.
3. **Retention kategorinin en zayıf halkası:** D7 ~%8.6, D14 ~%5.6. Kategori ortalamasını mütevazı oranda geçmek bile (hedeflerimiz §6) birim ekonomide belirgin avantaj yaratır; rewarded engagement verisi (3x geri dönüş) `OdulMerkezi` yatırımının gerekçesidir.
4. **ABD tek başına pazarın yarısı:** Monetizasyon tasarımı (fiyat noktaları, paywall dili) ABD'ye göre kalibre edilir; büyüme coğrafyaları (LatAm/SEA) ikinci dalga lokalizasyonla adreslenir (§5.2).

---

## 3. Rakip analizi

> **Veri notu:** Bu bölümdeki fiyat ve puan bilgileri kaynaklar arasında kısmen tutarsızdır ve zamanla değişir. Tablolarda "doğrulanmış" işaretli olmayan her fiyat/puan, **lansman öncesi güncel App Store verisiyle doğrulanmalıdır** (doğrulama görevi: 09-yol-haritasi-tasklar.md). Ayrıntılı kaynak dökümü: 10-arastirma-raporu.md.

### 3.0 Özet karşılaştırma

| | ReelShort | DramaBox | NetShort | DramaWave |
|---|---|---|---|---|
| Gelir (Q1 2025, doğrulanmış) | $130M / ~$490M küm. | $120M / ~$450M küm. | ~$57M küm. (%171 çeyreklik büyüme) | ~$47M (Nisan 2025) |
| Konumlanma | Kategori kurucusu, orijinal içerik, premium | Disiplinli operatör, geniş katalog, abonelik ağırlıklı | Hızlı büyüyen challenger | En hızlı büyüyen challenger (indirmede 10x) |
| Monetizasyon ağırlığı | Coin (bölüm başı ödeme) | Abonelik + coin | Doğrulanmış detay yok — lansman öncesi incelenmeli | VIP abonelik + tek seferlik teklif (tek kaynak) |
| iOS App Store puanı (anlık, doğrulanmalı) | ~4.6 | ~4.8 | Veri yok — doğrulanmalı | ~4.9 (ABD) |
| Ücretsiz bölüm cömertliği | Daha az | Daha fazla | Bilinmiyor | Bilinmiyor |

### 3.1 ReelShort

- **Kimlik:** Ağustos 2022'de Crazy Maple Studio (COL Group destekli) tarafından lansmanlandı; kategoriyi Batı pazarında kuran uygulama (https://en.wikipedia.org/wiki/ReelShort).
- **Konumlanma:** Pazar lideri, "orijinal içerik + marka" oyunu. Q1 2025'te $130M gelir, ~$490M kümülatif (doğrulanmış).
- **İçerik stratejisi:** Ağırlıkla orijinal İngilizce prodüksiyonlar (kaynaklara göre 200+ orijinal; Los Angeles'ta çekim — https://filmustage.com/blog/short-drama-apps-compared-reelshort-vs-dramabox-in-2026/ , tek kaynak). Format: hızlı twist, yüksek duygusal çatışma, bilinçli düşük prodüksiyon değeri, tanınmamış oyuncular. Seri başı ortalama prodüksiyon ~$300K (tek kaynak, §1.3).
- **Monetizasyon modeli:** Coin ağırlıklı; ilk hikayede paywall ~10 dakika sonra gelir ve tam cliffhanger noktasına yerleşir (doğrulanmış — https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop). Bölüm kilidi kaynaklara göre ~18–100 coin; bir seriyi tamamlama ~$10–50. Haftalık VIP fiyatı kaynaklar arasında **$5.99–$20 arası çelişkili** raporlanıyor — kesin rakam olarak kullanılamaz, lansman öncesi App Store'dan doğrulanmalı. Coin kazanım yolları: bildirim izni, e-posta paylaşımı, rewarded ad, günlük streak (doğrulanmış).
- **Güçlü yönleri:** Kategori bilinirliği ve en yüksek gelir; orijinal içerik kütüphanesinin IP değeri; agresif ve kanıtlanmış paywall/cliffhanger disiplini; devasa paid-UA makinesi.
- **Zayıf yönleri:** Pahalılık algısı (fiyat şikayetleri, §7.4); coin ağırlıklı modelin abonelik modeline göre daha sert monetizasyon-retention gerilimi; indirmelerin ~%70'inin paid olması (Sensor Tower — https://sensortower.com/blog/short-drama-redefines-mobile-entertainment-and-challenges-games) organik büyüme zafiyetine işaret eder.
- **iOS App Store puanı:** ~4.6 (birden çok ikincil kaynak; anlık değer, doğrulanmalı).

### 3.2 DramaBox

- **Konumlanma:** İkinci büyük oyuncu; Q1 2025'te $120M gelir, ~$450M kümülatif (doğrulanmış). ReelShort'a göre daha "cömert ve disiplinli operatör" imajı.
- **İçerik stratejisi:** Hibrit model — kaynaklara göre 2.000+ ağırlıkla çevrilmiş/lisanslı başlık + az sayıda ABD orijinali (https://filmustage.com/blog/short-drama-apps-compared-reelshort-vs-dramabox-in-2026/ , tek kaynak). Geniş katalog = discovery ve uzun kuyruk avantajı.
- **Monetizasyon modeli:** Abonelik ağırlıklı. **Doğrulanmış fiyatlar:** $3.99 haftalık intro / $5.99 haftalık standart / $49.99 yıllık (https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack). Rakiplere göre daha fazla ücretsiz bölüm sunar (kanonik benchmark).
- **Güçlü yönleri:** Kategorinin en iyi bilinen uzun vadeli retention'ı (6. ay %17 / 12. ay %15 — doğrulanmış); abonelik gelirinin öngörülebilirliği; cömert ücretsiz katman ile daha düşük fiyat-şikayet baskısı; yüksek mağaza puanı.
- **Zayıf yönleri:** Çeviri/lisans içeriğin ABD pazarında "yerli hissetmemesi"; orijinal IP zayıflığı; indirmelerin >%60'ı paid (Sensor Tower).
- **iOS App Store puanı:** ~4.8 (ikincil kaynaklar; anlık değer, doğrulanmalı).

### 3.3 NetShort

- **Konumlanma:** 2024 H2'de lansmanlanan ikinci dalga challenger'lardan (https://sensortower.com/blog/short-drama-redefines-mobile-entertainment-and-challenges-games). Q1 2025'te **%171 çeyreklik gelir büyümesi, ~$57M kümülatif gelir** (doğrulanmış) — challenger'lar arasında gelirde en hızlı ölçeklenen.
- **İçerik stratejisi ve monetizasyon:** Araştırma setimizde çapraz doğrulanmış içerik/fiyat detayı yoktur. Genel kategori kalıbını (ücretsiz ilk bölümler → coin kilidi → VIP) izlediği raporlanır; **spesifik SKU'lar, ücretsiz bölüm sayısı ve puanı lansman öncesi App Store'dan ve uygulama içi incelemesiyle doğrulanmalıdır** (görev: 09-yol-haritasi-tasklar.md; teardown şablonu: 10-arastirma-raporu.md).
- **Güçlü yönleri:** Kanıtlanmış hızlı gelir ölçekleme; geç girişe rağmen pay alabilmesi "pazar doymadı" tezimizin kanıtı.
- **Zayıf yönleri:** Marka bilinirliği ve orijinal IP eksikliği; liderlere göre küçük katalog (varsayım — doğrulanmalı).
- **iOS App Store puanı:** Elimizde doğrulanmış veri yok — lansman öncesi kaydedilmeli.

### 3.4 DramaWave

- **Konumlanma:** Q1 2025'in indirme bazında **en hızlı büyüyen** uygulaması: çeyreklik 10x büyüme, 53M kümülatif indirme, Nisan 2025 itibarıyla ~$47M gelir (doğrulanmış).
- **İçerik stratejisi:** App Store konumlanması çeşitli temalar, HD streaming, çok dilli altyazı ve sık içerik güncellemesi üzerine kuruludur (Sensor Tower/InvestGame raporu). Lokalizasyon vurgusu belirgin farklılaştırıcısıdır.
- **Monetizasyon modeli:** Reklam + IAP karması; en çok satan SKU'ları haftalık/aylık VIP ~$19.90 ve $9.99 tek seferlik teklif olarak raporlanır — **tek kaynak (InvestGame PDF), hakem oylamasında tutarsız bulundu; kesin rakam olarak kullanılamaz, lansman öncesi doğrulanmalı.**
- **Güçlü yönleri:** Kategorinin en yüksek raporlanan ABD App Store puanı (~4.9); lokalizasyon ve içerik yenileme temposu; indirme büyüme hızı.
- **Zayıf yönleri:** Büyümenin aşırı paid-UA bağımlı olması — indirmelerin %73–80'inden fazlası paid, ad impression'larının ~%98'i tek kanaldan (Unity) (Sensor Tower/InvestGame; §7.1'deki tek-kanal riskinin kategorideki en uç örneği); gelirin indirme hacmine göre görece düşük olması (monetizasyon derinliği liderlerin gerisinde).
- **iOS App Store puanı:** ~4.9 (ABD; Sensor Tower kaynaklı, anlık değer — doğrulanmalı).

### 3.5 Rakip analizinden çıkan tasarım kararları

| Gözlem | ShortSeries kararı | Uygulandığı yer |
|---|---|---|
| Paywall'un cliffhanger'a yerleşmesi kategori standardı | Kilit noktası içerik ekibince belirlenir; istemci `unlockPrice`'ı API'den okur, kilidi hardcode etmez | 05-veri-modeli-api.md, 06-monetizasyon.md |
| DramaBox'ın cömert ücretsiz katmanı + aboneliği retention'a çalışıyor | İlk 5–10 bölüm ücretsiz (~ilk 10 dakika); VIP + coin ikili model | 06-monetizasyon.md |
| ReelShort'un pahalılık algısı en büyük şikayet kaynağı | Earned-coin ekonomisi geniş tutulur (check-in, görevler, rewarded ad); harcamada earned öncelikli | 06-monetizasyon.md, 07-retention-gamification.md |
| Rewarded engagement 3x geri dönüş getiriyor | `OdulMerkezi` ayrı sekme (Ödüller) olarak birinci sınıf yüzey | 02-ekran-haritasi-navigasyon.md, 07-retention-gamification.md |
| DramaWave lokalizasyonla puan/indirme kazanıyor | Çok dilli altyapı gün-1 mimaride (EN başta, TR/ES/PT ikinci dalga); dil seçimi `Onboarding` adımı | 01-ozellik-envanteri.md, 02-ekran-haritasi-navigasyon.md |
| Liderler dahil kimse izleme deneyimini "kusursuz" yapmıyor | Performans bütçeleri sözleşme düzeyinde bağlayıcı (TTFF < 500 ms, swipe < 100 ms, 60 fps) | 04-player-engine.md |

---

## 4. ShortSeries konumlanması ve farklılaşması

### 4.1 Konumlanma cümlesi

> **25–45 yaş, dizi tutkunu kadın kullanıcı için** ShortSeries, **açar açmaz oynayan ve asla bitmeyen bir mikro-dizi akışıdır**; ReelShort ve DramaBox'tan farklı olarak **AI üretim hattı sayesinde daha hızlı yenilenen katalog, kategorinin en akıcı player deneyimi ve daha adil hissettiren bir kilit-açma ekonomisi** sunar.

### 4.2 Farklılaşma sütunları

1. **Maliyet yapısı (yapısal avantaj):** Seri başı ~$300K prodüksiyon ekonomisine karşı AI üretim hattı (§1.3). Bu, (a) daha fazla ücretsiz bölümü sürdürülebilir kılar, (b) niş tür/tema denemelerini ucuzlatır, (c) izleme verisinin içerik üretimine geri beslenmesini hızlandırır. *İstemci tarafındaki karşılığı:* zengin izleme telemetrisi (08-analitik-deney.md) ve bölüm-bazlı release schedule desteği (06-monetizasyon.md, 05-veri-modeli-api.md).
2. **İzleme deneyimi (kuzey yıldızı #1):** `PlayerFeed`'de UIKit `UICollectionView` + AVPlayer havuzu mimarisi ve zorunlu performans bütçeleri (04-player-engine.md). Uygulama doğrudan videoyla açılır — mağaza vitrini değil, oynayan içerik. Kategoride "ilk kareye kadar geçen süre" ölçülebilir bir rekabet silahıdır.
3. **Retention makinesi (kuzey yıldızı #2):** Günlük check-in (7 günlük artan döngü), görev merkezi, streak, cliffhanger + otomatik sonraki bölüm, "devam et"in her yüzeyde olması (Ana Sayfa rafı, Listem, push, DiziDetay) — 07-retention-gamification.md. Hedef: kategori ortalamasının üstü (D1 ≥ %30 vs ~%27; D7 ≥ %10 vs ~%8.6).
4. **Adil hissettiren monetizasyon:** İlk 5–10 bölüm ücretsiz; `UnlockSheet` her zaman üç yol sunar (coin / rewarded ad / VIP); earned coin harcamada önceliklidir; rewarded ad cap'i remote config ile ayarlanır (günde 5–10). Rakip şikayet analizinin (fiyat, §7.4) doğrudan cevabıdır — 06-monetizasyon.md.
5. **Discovery (kuzey yıldızı #3):** `Kesfet` (Trend/Yeni/Top 10 rafları, tür filtreleri) + `Arama` (otomatik tamamlama, popüler aramalar). Geniş ve hızlı yenilenen AI kataloğu ancak iyi discovery ile değere döner.

### 4.3 Neden kazanabiliriz

- **Pazar kanıtı:** DramaWave ve NetShort, 2024 H2 girişiyle aylar içinde ölçeklendi (§2.1) — geç giriş engel değil.
- **Yapısal maliyet avantajı:** Rakipler her katalog genişlemesinde $150K–$300K/seri sınıfında sermaye yakar; bizim marjinal içerik maliyetimiz bunun kesirleri düzeyindedir. Aynı UA bütçesinde daha fazla "hook" deneyebiliriz.
- **Parite + üstünlük stratejisi:** Özellik envanterinde %100 pariteyi hedefleyip (01-ozellik-envanteri.md) üç kuzey yıldızında ölçülebilir üstünlük kurarız; kullanıcıya "eksik uygulama" hissi vermeden farklılaşırız.
- **Dürüst karşı-argümanlar (bilinçli kabul edilen):** (a) İçerik kalitesi algısı riski bizde rakiplerden yüksek (§7.3); (b) liderlerin UA makinesi ve marka bilinirliğiyle kısa vadede yarışamayız — ilk fazda hedef pazar payı değil, birim ekonomisi kanıtıdır (§6); (c) AI içerik App Store politikaları açısından ek inceleme yüzeyi yaratır (§7.2).

---

## 5. Hedef kitle ve hedef pazarlar

### 5.1 Hedef kitle

**Birincil persona — kategori kanonuna göre 25–45 yaş, ağırlıkla kadın kullanıcı:**

| Boyut | Tanım | Ürün karşılığı |
|---|---|---|
| Tüketim anı | Kısa boşluklar: işe gidiş-geliş, uyku öncesi, mola | Bölümler 1–3 dk; portrait-locked; ses kapalıyken altyazı okunabilirliği |
| İçerik beklentisi | Yüksek duygusal kanca (romantizm, intikam, statü dönüşü), hızlı twist | Tür tercihi `Onboarding`'de isteğe bağlı sorulur; For You akışı buna göre başlar |
| Ödeme davranışı | Duygusal yatırım anında (cliffhanger) mikro-ödeme; fiyat hassasiyeti yüksek | `UnlockSheet` cliffhanger anında; earned-coin yolları görünür |
| Teknik profil | Ortalama iPhone kullanıcısı, hücresel veri hassasiyeti | Veri tasarrufu modu: 480p + prefetch durdurma (04-player-engine.md) |
| Bildirim toleransı | Değer gördükten sonra yüksek ("yeni bölüm çıktı") | Bildirim izni + ATT istemi değer önerisinden SONRA (`Onboarding` kanonu) |

**İkincil kitleler (tasarımı değiştirmez, dışlanmaz):** genç erkek kitleye hitap eden alt türler (aksiyon/intikam), 45+ kullanıcılar (erişilebilirlik: Dynamic Type desteği `Ayarlar` ve DesignSystem kapsamında).

**Kabul kriterleri (persona uyumu):**
- [ ] `Onboarding` 3 adımı geçmez ve tür tercihi atlanabilir; atlanırsa For You genel-popüler içerikle başlar.
- [ ] ATT ve bildirim izin istemleri ilk video izlenmeden ÖNCE gösterilmez.
- [ ] `PlayerFeed` ses kapalı başlatılan cihaz durumunda altyazıyı otomatik gösterir (davranış detayı: 04-player-engine.md).

### 5.2 Hedef pazarlar

1. **Faz 1 — ABD (birincil):** Kategori gelirinin ~%49'u (Q1 2025), kaynaklara göre ~%49–60 bandı. İçerik dili EN; fiyatlandırma USD App Store kademeleri (§6 ve 06-monetizasyon.md). Tüm KPI kalibrasyonu ABD kohortları üzerinden yapılır.
2. **Faz 2 — ikinci dalga diller: TR/ES/PT.** ES/PT, LatAm'ın kategorideki en hızlı indirme büyümesi bölgesi olmasıyla gerekçelenir (Sensor Tower). Çok dilli altyapı (uygulama dili + altyazı dili ayrımı, `Ayarlar`) gün-1'de mimaride bulunur; içerik lokalizasyonu AI hattının sorumluluğudur, istemci yalnızca dil metadata'sını tüketir (05-veri-modeli-api.md).
3. **Bilinçli erteleme:** Android istemci ve LatAm/SEA dağıtım stratejisi bu doküman setinin kapsamı dışındadır (iOS 17.0+, iPhone-only Faz 1 kanonu).

---

## 6. Başarı metrikleri ve KPI hedefleri

### 6.1 Hedef tablosu (kanonik — tüm ekipler için bağlayıcı)

| KPI | Hedef | Kategori benchmark'ı | Ölçüm tanımı |
|---|---|---|---|
| D1 retention | **≥ %30** | ~%27 (kategori ort.) | İlk açılış gününü izleyen 1. takvim gününde ≥1 oturum |
| D7 retention | **≥ %10** | ~%8.6 (kategori ort.) | 7. takvim gününde ≥1 oturum |
| D30 retention | **≥ %5** | D14 ~%5.6 (kategori ort.; D30 için kategori verisi sınırlı) | 30. takvim gününde ≥1 oturum |
| Ödeme dönüşümü | **≥ %3** | Kategori verisi kamuya açık değil | Kurulumdan itibaren 30 gün içinde ≥1 başarılı IAP (coin veya VIP) yapan kullanıcı / toplam yeni kullanıcı |
| Crash-free kullanıcı oranı | **≥ %99.8** | — | Firebase Crashlytics, haftalık pencere |

Destekleyici teknik guardrail'ler (ihlali release engelidir; ayrıntı 04-player-engine.md): time-to-first-frame < 500 ms, swipe-to-next < 100 ms, 60 fps kaydırma.

### 6.2 Ölçüm kuralları ve edge case'ler

- **Kohort tanımı:** Retention kohortları ilk açılış (anonim misafir hesabı oluşturma) anına göre kurulur; sonradan Apple/Google/e-posta bağlama kohortu DEĞİŞTİRMEZ (kimlik birleştirme kuralları: 05-veri-modeli-api.md, 08-analitik-deney.md).
- **Takvim günü:** Kullanıcının cihaz saat dilimine göre değil, sunucu tarafında sabitlenen kohort saat dilimine göre hesaplanır (deney tutarlılığı için; 08-analitik-deney.md).
- **Ödeme dönüşümünde iade/başarısız işlem:** Yalnızca server-side doğrulanmış (App Store Server API) işlemler sayılır; refund edilen işlem dönüşümden düşülmez ama ayrı `refund_rate` metriği izlenir (06-monetizasyon.md).
- **Reinstall edge case'i:** Aynı cihazda yeniden kurulum, Keychain'de yaşayan misafir kimliği üzerinden aynı kullanıcıya bağlanır; yeni kohort açılmaz.
- **ÇÜRÜTÜLMÜŞ verilerle kıyas yasağı:** ReelShort'a atfedilen tekil dönüşüm/gelir-karması oranları (ör. %71 bölüm-başı ödeme payı) çapraz doğrulamada tutarsız bulunmuştur; hedef gerekçelendirmede kullanılamaz.

### 6.3 KPI hedeflerinin koda bağlanması

Hedefler `AnalyticsKit` içinde tek kaynaktan tanımlanır; dashboard'lar ve deney guardrail'leri bu sabitleri okur (tam event şeması ve deney çerçevesi: 08-analitik-deney.md):

```swift
// AnalyticsKit/Sources/AnalyticsKit/KPITargets.swift
/// Kanonik KPI hedefleri — kaynak: docs/00-genel-bakis.md §6.1.
/// Değişiklik yalnızca ürün kanonu güncellemesiyle yapılır.
public enum KPITargets {
    public static let d1Retention: Double = 0.30
    public static let d7Retention: Double = 0.10
    public static let d30Retention: Double = 0.05
    public static let paymentConversionD30: Double = 0.03
    public static let crashFreeUsers: Double = 0.998

    /// Player guardrail'leri (bkz. 04-player-engine.md) — deneylerde
    /// ihlal eden varyant otomatik durdurma adayıdır.
    public enum PlayerGuardrails {
        public static let timeToFirstFrame: Duration = .milliseconds(500)
        public static let swipeToNextPlayback: Duration = .milliseconds(100)
        public static let minScrollFPS: Double = 60
    }
}
```

**Kabul kriterleri (analitik hazırlığı):**
- [ ] D1/D7/D30, ödeme dönüşümü ve crash-free metrikleri lansman gününden itibaren dashboard'da kohort bazlı izlenebilir.
- [ ] Her A/B deneyi bu KPI'lardan en az birini birincil metrik, crash-free + player guardrail'lerini zorunlu guardrail olarak tanımlar (08-analitik-deney.md şablonu).
- [ ] KPI hesapları, `AnalyticsKit` event şemasındaki kanonik event adlarıyla üretilir; ad-hoc SQL tanımı tek başına kaynak sayılmaz.

---

## 7. Temel riskler ve azaltma stratejileri

| # | Risk | Olasılık | Etki | Sahip |
|---|---|---|---|---|
| 7.1 | Paid-UA bağımlılığı ve pahalı büyüme | Yüksek | Yüksek | Growth |
| 7.2 | App Store politikaları (IAP, AI içerik, ATT) | Orta | Kritik | iOS + Legal |
| 7.3 | İçerik kalitesi algısı (AI-generated) | Yüksek | Yüksek | İçerik + Ürün |
| 7.4 | Fiyat şikayetleri ve mağaza puanı erozyonu | Yüksek | Orta | Ürün/Monetizasyon |
| 7.5 | Pazar verisi ve fiyat istihbaratı belirsizliği | Orta | Orta | Ürün |

### 7.1 Paid-UA bağımlılığı

**Risk:** Kategori büyümesi ağırlıkla satın alınmış trafiktir — Sensor Tower'a göre 2024'te indirmelerin ReelShort için ~%70'i, DramaBox için >%60'ı paid'dir; DramaWave'de paid pay %73–80+ ve impression'ların ~%98'i tek kanaldan (Unity) gelmiştir (https://sensortower.com/blog/short-drama-redefines-mobile-entertainment-and-challenges-games , https://investgame.net/wp-content/uploads/2025/11/State-of-Short-Drama-Apps-Overseas-2025-Report.pdf). Bir akademik vaka çalışması ReelShort'un 30 günlük retention'ını ~%2 olarak raporlar (tek kaynak, çapraz doğrulanmamış — temkinli kullan): paid-UA + düşük retention = sürekli para yakan koşu bandı riski.

**Azaltma:**
- Retention hedeflerini (§6.1) büyümenin ön koşulu yapmak: D7 ≥ %10 kanıtlanmadan UA harcaması ölçeklenmez (faz kapıları: 09-yol-haritasi-tasklar.md).
- Kanal çeşitliliği: tek ad network'e >%50 bağımlılık kırmızı çizgi (DramaWave dersi).
- Organik döngüler gün-1'de: `DiziDetay` paylaş aksiyonu, paylaşım görevleri (`OdulMerkezi`), rich push ile geri çağırma (07-retention-gamification.md).
- ROAS disiplini: kohort bazlı LTV/CAC dashboard'u (08-analitik-deney.md); kreatif üretiminde AI içerik hattının klip üretme avantajı kullanılır (aynı diziden çok varyantlı UA kreatifi).

### 7.2 App Store politikaları

**Risk yüzeyleri:** (a) Coin/abonelik ekonomisinin IAP kurallarına tam uyumu; (b) AI-generated içeriğin App Review'de ek inceleme/etiketleme gereksinimleri; (c) ATT ve izin akışlarının reddi; (d) abonelik fiyat/iptal şeffaflığı şikayetleri.

**Azaltma:**
- Tüm dijital içerik satışları StoreKit 2 IAP üzerinden; harici ödeme yönlendirmesi yok. Server-side receipt doğrulama (App Store Server API + Server Notifications V2) gün-1'de (06-monetizasyon.md).
- Coin'ler yalnızca uygulama içi kapalı ekonomi (çekilemez, devredilemez); purchased vs earned ayrımı muhasebe ve komisyon uyumu için zorunlu (kanon §5; 06-monetizasyon.md).
- ATT istemi `Onboarding`'de değer önerisinden sonra; izin reddedilirse kişiselleştirme cihaz-içi sinyallere düşer, uygulama işlevi kısıtlanmaz (kabul kriteri: ATT reddi hiçbir içeriği kilitlemez).
- İçerik moderasyonu: AI hattından gelen her dizi yayın öncesi insan onaylı kürasyon kapısından geçer; App Review notlarında içerik kaynağı şeffaf beyan edilir. Kullanıcı tarafında "bildir" mekanizması (`Profil` > destek akışı) bulunur.
- Politika değişikliği izleme: her release döngüsünde App Review Guidelines diff kontrolü (süreç görevi: 09-yol-haritasi-tasklar.md).

### 7.3 İçerik kalitesi algısı

**Risk:** Kategori zaten "dramaslop" eleştirisi alıyor (https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop); AI-generated içerikte tekinsiz vadi, ses/dudak senkronu ve süreklilik hataları algıyı daha da kırılganlaştırır. Kötü ilk izlenim = D1 hedefinin altında kalmak.

**Azaltma:**
- **Kalite kapısı:** Yayın öncesi kürasyon + bölüm bazlı kalite skoru; düşük skorlu içerik For You'ya girmez (feed sıralama girdileri: 05-veri-modeli-api.md).
- **Veriyle ayıklama:** Bölüm bazında erken terk (ilk 10 sn drop-off) telemetrisi içerik hattına geri beslenir; eşik altı bölümler otomatik düşük gösterime alınır (08-analitik-deney.md).
- **Beklenti yönetimi:** Konumlanma "sinema" değil "bağımlılık yapan hikaye" üzerinedir; kapak/başlık vaatleri içerikle tutarlı tutulur (clickbait kapak = iade ve kötü yorum kaynağı).
- **Teknik algı katkısı:** Akıcı oynatma kalite algısının parçasıdır — buffering ve düşük bitrate başlangıcı algılanan kaliteyi düşürür; bitrate merdiveni ve prefetch politikası 04-player-engine.md'de bu gerekçeyle sıkılaştırılmıştır.

### 7.4 Fiyat şikayetleri ve puan erozyonu

**Risk:** Kategoride negatif yorumların ~%49'u pahalılık şikayetidir (ReelShort örnekleminde %48.7 — https://www.researchgate.net/publication/383505184_Analyzing_the_Impact_of_User_Behavior_and_Paid_Advertising_on_App_Revenue_A_Case_Study_of_Reelshort ; tek akademik kaynak, örneklem bazlı — temkinli kullan). Düşen mağaza puanı hem organik indirmeyi hem paid-UA dönüşümünü pahalılaştırır.

**Azaltma:**
- Ücretsiz katman cömertliği: dizi başına ilk 5–10 bölüm ücretsiz (~ilk 10 dakika) — DramaBox'ın kanıtladığı yaklaşım.
- Her `UnlockSheet` üç yol sunar: coin ile aç / reklam izle / VIP ol; coin yetersizse akış `CoinMagazasi`'na kesintisiz devam eder. "Tek çıkış yolu ödeme" ekranı yasaktır (kabul kriteri: rewarded ad cap'i dolmadıkça UnlockSheet'te ücretsiz yol her zaman görünür).
- Earned-coin ekonomisi görünür ve gerçek: günlük check-in (10–50 coin, 7 günlük artan döngü), görevler, streak bonusu; harcamada earned önceliklidir (06-monetizasyon.md, 07-retention-gamification.md).
- Fiyat deneyleri guardrail'li: fiyat/paywall A/B'lerinde `negatif yorum oranı` ve `refund_rate` zorunlu guardrail metriktir (08-analitik-deney.md).
- Puan yönetimi: SKStoreReviewController istemi yalnızca pozitif anlarda (bölüm bitirme + streak günü) tetiklenir; şikayet sinyali veren kullanıcıya önce destek akışı gösterilir.

### 7.5 Pazar verisi ve fiyat istihbaratı belirsizliği

**Risk:** Rakip fiyatları kaynaklar arasında ciddi tutarsızdır (ör. ReelShort haftalık VIP $5.99–$20 aralığında çelişkili; DramaWave SKU'ları tek kaynaklı). Yanlış benchmark ile kalibre edilen fiyatlama, dönüşüm veya gelir kaybettirir.

**Azaltma:** Lansman öncesi doğrulama listesi (aşağıda) tamamlanmadan fiyat kalibrasyonu dondurulmaz; tüm dokümanlarda tutarsız rakamlar "aralık + doğrulanmalı" notuyla anılır; birincil kaynak olarak yalnız kanon §5 sınıfı doğrulanmış veriler kullanılır.

---

## 8. Lansman öncesi doğrulama listesi (rakip istihbaratı)

Aşağıdaki maddeler 09-yol-haritasi-tasklar.md'de görev olarak izlenir; sonuçlar 10-arastirma-raporu.md'ye işlenir:

- [ ] ReelShort, DramaBox, NetShort, DramaWave güncel iOS App Store puanları ve yorum dağılımı (ABD storefront) kaydedilir.
- [ ] Dört rakipte güncel coin paketi SKU'ları, VIP fiyatları ve intro teklifler uygulama içinden ekran görüntüsüyle belgelenir (özellikle: ReelShort haftalık VIP, DramaWave ~$19.90 SKU'ları, NetShort'un tüm modeli).
- [ ] Dört rakipte ücretsiz bölüm sayısı, rewarded ad cap'i ve günlük coin kazanım tavanı ölçülür (teardown protokolü: 10-arastirma-raporu.md).
- [ ] ShortSeries fiyat merdiveni ($0.99–$99.99 coin paketleri; VIP haftalık $5.99 / intro $3.99 / aylık $14.99 / yıllık $49.99) bu verilerle son kez kalibre edilir (06-monetizasyon.md).

---

## 9. Kaynaklar

Sayısal pazar iddiaları yalnızca kanon §5 doğrulanmış verilerinden gelir; tam kaynak dökümü ve doğrulama kararları için bkz. 10-arastirma-raporu.md.

- https://sensortower.com/blog/state-of-short-drama-apps-2025
- https://sensortower.com/blog/short-drama-redefines-mobile-entertainment-and-challenges-games
- https://investgame.net/wp-content/uploads/2025/11/State-of-Short-Drama-Apps-Overseas-2025-Report.pdf
- https://adjoe.io/blog/short-drama-apps-rewarded-engagement/
- https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack
- https://filmustage.com/blog/short-drama-apps-compared-reelshort-vs-dramabox-in-2026/
- https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop
- https://en.wikipedia.org/wiki/ReelShort
- https://www.researchgate.net/publication/383505184_Analyzing_the_Impact_of_User_Behavior_and_Paid_Advertising_on_App_Revenue_A_Case_Study_of_Reelshort
