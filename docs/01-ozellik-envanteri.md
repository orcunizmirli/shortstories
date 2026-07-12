# Özellik Envanteri ve Rakip Parite Matrisi

**Amaç:** Bu doküman, ShortSeries iOS istemcisinin lansmana kadar (ve sonrasında) inşa edeceği TÜM özelliklerin tek doğruluk kaynağı envanteridir. Her özellik için davranış tanımı, kabul kriterleri, edge case'ler, MoSCoW önceliği ve faz etiketi verilir; sonunda ReelShort / DramaBox / NetShort–DramaWave ile özellik parite matrisi ve bilinçli kapsam dışı bırakılan konular yer alır. Geliştirme ekibi sprint planlamasını ve kabul testlerini doğrudan bu envanter üzerinden yürütür.

**İlgili dokümanlar:** `00-genel-bakis.md` (vizyon ve kuzey yıldızı), `02-ekran-haritasi-navigasyon.md` (ekran akışları ve Coordinator rotaları), `03-mimari.md` (SPM modülleri, MVVM+Coordinator), `04-player-engine.md` (PlayerPool, prefetch, performans bütçeleri), `05-veri-modeli-api.md` (Series/Episode modelleri, API sözleşmeleri), `06-monetizasyon.md` (coin ekonomisi, StoreKit 2, UnlockSheet ayrıntısı), `07-retention-gamification.md` (check-in, görevler, push stratejisi), `08-analitik-deney.md` (event şeması, A/B), `09-yol-haritasi-tasklar.md` (bu envanterin task kırılımı), `10-arastirma-raporu.md` (rakip araştırması ve kaynaklar).

---

## 1. Envanter yapısı ve okuma kılavuzu

### 1.1 Önceliklendirme: MoSCoW

| Etiket | Anlamı |
|---|---|
| **Must** | Bulunmadan ilgili faz "bitti" sayılamaz. Kabul kriterlerinin tamamı zorunlu. |
| **Should** | Fazın hedefi; ancak takvim baskısında bir sonraki faza kayabilir (karar: ürün + mühendislik birlikte). |
| **Could** | Değer katar, fırsat olursa yapılır; hiçbir Must/Should'u geciktiremez. |
| **Won't (bu fazda)** | Bilinçli olarak yapılmayacak; gerekçesi §4'te. |

### 1.2 Faz etiketleri

| Faz | Kapsam özeti |
|---|---|
| **F1 (MVP)** | Lansman sürümü: PlayerFeed + kilit/coin/VIP döngüsü + Keşfet/Arama + Listem + OdulMerkezi (check-in + görevler) + temel push + paylaşım/deep link. Reklamsız (rewarded ads yok). |
| **F2** | Rewarded ads (AdMob), FairPlay DRM, BildirimMerkezi, cihazlar arası senkron, gelişmiş öneri, TR/ES/PT lokalizasyon dalgası, A/B deney genişlemesi. |
| **F3** | Offline indirme (`AVAssetDownloadTask`), Live Activities, ileri kişiselleştirme; yorum/sosyal özellikler ancak F3 sonunda değerlendirilir. |

### 1.3 Özellik kaydı formatı

Her özellik `ALAN-XX` kimliğiyle anılır (örn. `PLR-02`). Bu kimlikler `09-yol-haritasi-tasklar.md` içindeki task kırılımının ve `08-analitik-deney.md` içindeki event eşlemesinin referans anahtarıdır. Format:

- **Davranış:** Kullanıcı gözünden ne olur; teknik bağlam.
- **Kabul kriterleri:** Test edilebilir, ikili (geçti/kalmadı) maddeler.
- **Edge case'ler:** (gerektiğinde) hata/kesinti/sınır durumları.

Kanonik performans bütçeleri (tüm player özelliklerinde geçerli, ayrıntı `04-player-engine.md`): time-to-first-frame < 500 ms; swipe-to-next oynatma < 100 ms; 60 fps kaydırma; player havuzu 3–5 instance; sonraki bölüm prefetch ~500 KB veya ilk 2 sn; `preferredForwardBufferDuration` aktif player = 0 (otomatik), idle player = 1 sn; disk video cache ~200 MB LRU; crash-free ≥ %99.8.

---

## 2. Özellik envanteri

### 2.1 Onboarding & hesap (`Splash`, `Onboarding`; modül: `AppFoundation`, `ProfileKit`)

#### ONB-01 — Splash + ön-yükleme — **Must, F1**
**Davranış:** Uygulama `Splash` ile açılır (logo). Splash görünürken ilk For You feed sayfası ve ilk videonun prefetch'i arka planda başlar; hedef, kullanıcı `PlayerFeed`'e düştüğünde videonun < 500 ms içinde oynamaya başlamasıdır.
**Kabul kriterleri:**
- [ ] Splash süresi ağ hızından bağımsız olarak en fazla 2 sn'de ana akışa geçer; feed hazır değilse `PlayerFeed` iskelet (skeleton) durumuyla açılır, video hazır olur olmaz oynar.
- [ ] Splash sırasında: session token yenileme, remote config çekme, ilk feed sayfası isteği ve ilk video prefetch'i paralel yürür (async let / task group).
- [ ] Soğuk açılıştan ilk frame'e medyan süre < 500 ms (Wi-Fi, iPhone 12 ve üzeri baz cihaz).
**Edge case'ler:** Ağ yoksa Splash'ten sonra çevrimdışı durum ekranı + "Tekrar dene"; cache'te feed varsa cache'ten oynatmayı dene.

#### ONB-02 — Anonim misafir hesabı — **Must, F1**
**Davranış:** İlk açılışta kullanıcıya hiçbir kayıt ekranı gösterilmeden backend'de anonim misafir hesabı otomatik oluşturulur (cihaz bazlı). Coin bakiyesi, izleme geçmişi, favoriler bu hesaba yazılır. Token Keychain'de saklanır.
**Kabul kriterleri:**
- [ ] İlk açılış → izleme başlangıcı arasında zorunlu form/giriş ekranı yoktur.
- [ ] Misafir token'ı Keychain'de saklanır; uygulama silinip yeniden kurulduğunda Keychain'de token varsa aynı hesap devam eder.
- [ ] Misafir hesabı coin satın alabilir, bölüm açabilir, VIP olabilir (satın alma hesap bağlamayı ZORUNLU kılmaz; bağlama teşvik edilir).
- [ ] Token yenileme (refresh) sessizce yapılır; yenileme başarısızsa kullanıcı akışı kesilmeden yeni misafir oturumu + destek yönlendirmesi denenir.
**Edge case'ler:** Keychain erişim hatası (cihaz kilitli ilk açılış) → geçici bellek-içi oturum + ilk fırsatta Keychain'e yazma.

#### ONB-03 — Onboarding: dil seçimi — **Must, F1**
**Davranış:** `Onboarding` adım 1: uygulama + altyazı dili seçimi (varsayılan: sistem dili; lansmanda EN, ikinci dalga TR/ES/PT). Seçim `Ayarlar`'dan sonradan değiştirilebilir.
**Kabul kriterleri:**
- [ ] Sistem dili desteklenen dillerdeyse adım önceden seçili gelir ve tek dokunuşla geçilebilir.
- [ ] Seçim hem UI dilini hem varsayılan altyazı dilini belirler; ikisi `Ayarlar`'da ayrı ayrı değiştirilebilir (bkz. LOC-02).

#### ONB-04 — Onboarding: tür tercihi (atlanabilir) — **Should, F1**
**Davranış:** `Onboarding` adım 2: 8–12 tür kartından çoklu seçim ("Atla" her zaman görünür). Seçim ilk For You sıralamasına sinyal olarak gönderilir.
**Kabul kriterleri:**
- [ ] "Atla" ile geçildiğinde feed genel popülerlikle başlar; seçim yapıldığında ilk 10 feed öğesinin en az yarısı seçilen türlerden gelir (API sözleşmesi: `05-veri-modeli-api.md`).
- [ ] Adım 15 sn'den uzun etkileşim almazsa analitik olarak `onboarding_genre_timeout` işaretlenir (A/B için; `08-analitik-deney.md`).

#### ONB-05 — Bildirim izni + ATT istemi (değer önerisinden SONRA) — **Must, F1**
**Davranış:** Sistem bildirim izni ve ATT (App Tracking Transparency) istemi `Onboarding` sonunda, değer önerisi ekranından ("Yeni bölüm çıkınca haber verelim + coin kazan") SONRA gösterilir. Bildirim iznine onay, OdulMerkezi'ndeki "bildirim izni" göreviyle coin ödülüne bağlanır (RWD-02).
**Kabul kriterleri:**
- [ ] Sistem izin diyaloğundan önce her zaman uygulama içi ön-açıklama (pre-prompt) ekranı gösterilir; kullanıcı ön-açıklamada "Şimdi değil" derse sistem diyaloğu HİÇ tetiklenmez (hak yakılmaz).
- [ ] ATT istemi bildirim izninden ayrı adımda ve yalnızca bir kez sistem diyaloğu olarak sunulur; reddedilirse kişiselleştirilmiş reklam/attribution kapalı çalışılır.
- [ ] İzin sonuçları (verildi/reddedildi/ertelendi) analitiğe yazılır.
**Edge case'ler:** Kullanıcı `Onboarding`'i tamamen atlarsa istemler ilk anlamlı ana taşınır (örn. ilk favorileme sonrası) — asla ilk video izlenmeden önce değil.

#### ONB-06 — Hesap bağlama: Apple / Google / e-posta — **Must (Apple) F1; Should (Google, e-posta) F2**
**Davranış:** Misafir hesabı `Profil` üzerinden Sign in with Apple (F1), Google ve e-posta (F2) ile kalıcı hesaba bağlanır. Bağlama sırasında misafir hesabının TÜM varlıkları (coin, VIP entitlement, geçmiş, favoriler) korunur.
**Kabul kriterleri:**
- [ ] Bağlama sonrası coin bakiyesi, kilidi açılmış bölümler, VIP durumu, Listem içeriği bire bir aynıdır (sunucu tarafı merge; sözleşme `05-veri-modeli-api.md`).
- [ ] Aynı Apple kimliği daha önce başka hesaba bağlıysa çakışma diyaloğu: "Var olan hesapla devam et" / "Vazgeç" (misafir varlıkları kaybolacaksa açıkça uyarılır).
- [ ] Sign in with Apple, App Store Review 4.8 gereği üçüncü parti girişlerle birlikte her zaman sunulur.
- [ ] Çıkış (sign out) sonrası cihaz yeni misafir oturumuna döner; kalıcı hesaba tekrar girilebilir.

#### ONB-07 — Hesap silme — **Must, F1**
**Davranış:** `Ayarlar` → Hesap yönetimi → Hesabı sil. App Store zorunluluğu. Sunucuda hesap ve kişisel veriler silinir; aktif aboneliğin App Store üzerinden ayrıca iptal edilmesi gerektiği açıkça belirtilir.
**Kabul kriterleri:**
- [ ] Silme akışı en fazla 2 onay adımıdır; tamamlanınca oturum kapanır ve yeni misafir oturumu açılır.
- [ ] Kullanıcıya kalan coin/VIP hakkının geri ödenmeyeceği silmeden ÖNCE net biçimde gösterilir.

#### ONB-08 — Cihazlar arası senkron — **Should, F2**
**Davranış:** Bağlı hesapla giriş yapılan ikinci cihazda izleme konumu, favoriler, coin ve entitlement'lar sunucudan gelir.
**Kabul kriterleri:**
- [ ] İkinci cihazda "Devam Et" son izleme konumunu ±5 sn hassasiyetle gösterir.
- [ ] Cüzdan bakiyesi tek doğruluk kaynağı sunucudur; istemci cache'i her ön plana gelişte tazelenir.

---

### 2.2 PlayerFeed — Ana Sayfa / For You (modül: `PlayerKit`, `ContentKit`)

#### FEED-01 — Dikey tam ekran For You akışı — **Must, F1**
**Davranış:** Uygulama DOĞRUDAN video ile açılır: **Ana Sayfa** sekmesi = `PlayerFeed`, dikey tam ekran, portrait-locked, sayfa başına bir bölüm. Teknik: `UICollectionView` (dikey paging) + AVPlayer havuzu; SwiftUI kabuğuna `UIViewControllerRepresentable` köprüsü (gerekçe ve ayrıntı: `04-player-engine.md`).
**Kabul kriterleri:**
- [ ] Yukarı kaydırma → sonraki içerik; aşağı kaydırma → önceki içerik; sayfalar arası yapışkan (snap) geçiş.
- [ ] Swipe-to-next'te oynatma < 100 ms (havuzdan hazır player); kaydırma sırasında 60 fps korunur.
- [ ] Video safe area'ları taşacak şekilde tam ekran; overlay UI (FEED-04) safe area içinde kalır.
- [ ] Status bar/home indicator davranışı: oynatma sırasında otomatik gizlenir, dokunuşla döner.

#### FEED-02 — Player havuzu + prefetch — **Must, F1**
**Davranış:** 3–5 instance'lık `PlayerPool` (actor) mevcut/önceki/sonraki bölümleri hazır tutar. Sonraki bölüm ~500 KB veya ilk 2 sn prefetch edilir (hangisi önce). Aktif player `preferredForwardBufferDuration = 0` (otomatik), idle player'lar = 1 sn.
**Kabul kriterleri:**
- [ ] Havuz boyutu remote config ile 3–5 arası ayarlanabilir.
- [ ] Ekran dışı player'lar oynatmaz ve buffer sınırı dışında ağ tüketmez.
- [ ] Disk video cache ~200 MB LRU; limit aşımında en eski erişilen segmentler silinir.
- [ ] Kaydırma yönü değişince prefetch hedefi yeni yöne göre güncellenir.
**Edge case'ler:** Bellek uyarısında havuz 3'e düşürülür ve idle player'ların item'ları boşaltılır; ayrıntı `04-player-engine.md`.

#### FEED-03 — Akış sıralama mantığı — **Must, F1**
**Davranış:** Bölüm biter → aynı dizinin SONRAKİ bölümü otomatik gelir (PLR-09 ile birlikte). Dizi biterse veya kullanıcı diziyi kaydırarak atlarsa → yeni dizi önerisi (1. bölümünden). Sıralama sunucu tarafındadır; istemci `feed` API sayfalarını tüketir.
**Kabul kriterleri:**
- [ ] Aynı dizi içinde ilerlerken sıra asla bölüm atlamaz (n → n+1).
- [ ] Kullanıcı bir dizinin bölümünü izlerken feed'i yukarı kaydırırsa varsayılan davranış: aynı dizinin sonraki bölümü; aynı diziden art arda 2 bölüm ≥%90 izlenmeden kaydırılırsa sunucuya "skip" sinyali gider ve yeni dizi önerilir (eşik remote config).
- [ ] Kilitli bölüme gelindiğinde FEED-05 devreye girer; sıra kilit yüzünden sessizce atlanmaz.

#### FEED-04 — Feed overlay UI — **Must, F1**
**Davranış:** Video üzerinde: dizi adı + bölüm numarası (dokununca `DiziDetay`), sağ kenarda dikey aksiyon sütunu (favori PLR-08, paylaş PLR-07, bölüm listesi PLR-06), altta scrubber (PLR-05). Overlay, etkileşimsiz 3 sn sonra sadeleşir (scrubber ince çizgiye düşer), dokunuşla geri gelir.
**Kabul kriterleri:**
- [ ] Tüm dokunma hedefleri ≥ 44×44 pt.
- [ ] Dizi adına dokunuş `DiziDetay`'ı push eder; geri dönüşte oynatma kaldığı yerden sürer.
- [ ] Overlay durum değişimleri oynatmayı etkilemez (pause tetiklemez).

#### FEED-05 — Kilitli bölümde UnlockSheet tetikleme — **Must, F1**
**Davranış:** Feed kilitli bölüme geldiğinde video oynamaz; bulanık kapak karesi + kilit rozeti + `unlockPrice` gösterilir ve `UnlockSheet` otomatik açılır (UNL-01).
**Kabul kriterleri:**
- [ ] Kilitli bölümün medya URL'i istemciye hiç verilmez (imzalı URL yalnız entitlement sonrası; UNL-06).
- [ ] Sheet kapatılırsa kullanıcı feed'de kalır; yukarı kaydırırsa yeni dizi önerisine geçer, aynı kilitli bölüme dönerse sheet yeniden açılır.
- [ ] Unlock başarılı olunca video kullanıcı etkileşimi gerektirmeden oynamaya başlar.

#### FEED-06 — Veri tasarrufu modu — **Must, F1**
**Davranış:** `Ayarlar` → Oynatma tercihleri → Veri tasarrufu (varsayılan: hücreselde açık önerilir, kullanıcı seçer). Açıkken hücresel ağda: bitrate 480p ile sınırlanır (`preferredPeakBitRateForExpensiveNetwork` + varyant seçimi), prefetch durdurulur.
**Kabul kriterleri:**
- [ ] Wi-Fi ↔ hücresel geçişinde politika oynatma kesilmeden uygulanır.
- [ ] Veri tasarrufu açıkken hücresel oturumda prefetch trafiği ölçülür ve ~0'dır (yalnız aktif player buffer'ı).
- [ ] iOS "Low Data Mode" sinyali de aynı politikayı tetikler.

#### FEED-07 — Feed'de kaldığı yerden başlama — **Should, F1**
**Davranış:** Uygulama yeniden açıldığında feed, kullanıcının en son izlediği bölümden (kaldığı saniyeden) başlar; onun altında normal For You sırası devam eder.
**Kabul kriterleri:**
- [ ] Son izleme konumu SwiftData'ya en geç 5 sn'de bir ve her pause/arka plan geçişinde yazılır.
- [ ] Bölümün son 10 sn'sinde bırakıldıysa bir SONRAKİ bölümden başlatılır (bitmiş sayılır).

#### FEED-08 — Sonsuz kaydırma + sayfalama — **Must, F1**
**Davranış:** Feed API'si cursor tabanlı sayfalarla tüketilir; kullanıcı sona yaklaşınca (son 3 öğe) sıradaki sayfa istenir.
**Kabul kriterleri:**
- [ ] Sayfa isteği başarısızsa sessiz yeniden deneme (exponential backoff, en fazla 3); kullanıcı gerçekten sona ulaşırsa hafif hata durumu + "Tekrar dene".
- [ ] Aynı oturumda aynı bölüm feed'de iki kez üst üste gösterilmez (istemci taraflı dedup).

#### FEED-09 — Yaşam döngüsü ve kesinti davranışı — **Must, F1**
**Davranış:** Arka plana geçişte oynatma duraklar; ön plana dönüşte aynı karede devam eder. Telefon araması/Siri kesintisinde `AVAudioSession` kesinti bildirimine göre duraklat/sürdür.
**Kabul kriterleri:**
- [ ] Arka plan → ön plan dönüşünde player yeniden kurulmaz (position korunur), TTFR < 300 ms.
- [ ] Kesinti bitiminde `shouldResume` seçeneği varsa otomatik sürdürülür.
- [ ] Kulaklık çıkarılınca (route change, `oldDeviceUnavailable`) oynatma duraklar.

---

### 2.3 Player etkileşimleri (modül: `PlayerKit`)

Jest öncelik tablosu (çakışma çözümü `04-player-engine.md`'de gesture recognizer bağımlılıklarıyla verilir):

| Jest | Eylem | Öncelik notu |
|---|---|---|
| Tek tap | Play/pause | Anında uygulanır — `require(toFail:)` ile 250 ms çift-tap beklemesi YAPILMAZ; dokunuşun çift tap'in ilk yarısı olduğu anlaşılırsa tek tap etkisi geri alınır (kanonik tanıma stratejisi: `04-player-engine.md` §8) |
| Çift tap (sağ %40 bölge) | +10 sn ileri | Uygulanmış tek tap etkisini geri alır |
| Çift tap (sol %40 bölge) | −10 sn geri | Uygulanmış tek tap etkisini geri alır |
| Uzun bas (≥ 400 ms) | Basılıyken 2x hız | Bırakınca önceki hıza döner; scrubber sürüklemesiyle çakışmaz |
| Dikey kaydırma | Feed sayfa geçişi | Collection view'a aittir; player jestleri dikey pan'ı bloklamaz |
| Scrubber sürükleme | Konum arama | Sürükleme sırasında dikey paging kilitlenir |

```swift
// PlayerKit — jest komutlarının tek noktadan aktığı sözleşme (iskelet)
enum PlayerGesture: Sendable {
    case togglePlayPause
    case seekRelative(seconds: Double)   // +10 / -10
    case holdSpeedBegan                  // 2x başlat
    case holdSpeedEnded                  // önceki hıza dön
    case scrub(progress: Double, phase: ScrubPhase)
}

@MainActor
protocol PlayerGestureHandling: AnyObject {
    func handle(_ gesture: PlayerGesture)
}
```

#### PLR-01 — Tek tap: play/pause — **Must, F1**
**Davranış:** Video alanına tek dokunuş oynat/duraklat arasında geçiş yapar. Duraklatınca büyük play ikonu + overlay tam görünür; oynatınca ikon söner.
**Kabul kriterleri:**
- [ ] Tek tap etkisi ANINDA uygulanır — 250 ms çift-tap bekleme gecikmesi yoktur; dokunuşun çift tap'in ilk yarısı olduğu anlaşılırsa play/pause geri alınır ve çift tap davranışı uygulanır (kanonik strateji: `04-player-engine.md` §8).
- [ ] Pause durumunda feed kaydırılabilir kalır; kaydırılan yeni sayfa otomatik oynar.
- [ ] Pause anı FEED-07 için konum yazımını tetikler.

#### PLR-02 — Çift tap sağ/sol: ±10 sn — **Must, F1**
**Davranış:** Ekranın sağ bölgesine çift tap +10 sn, sol bölgesine çift tap −10 sn atlar. Görsel geri bildirim: yarım daire ripple + "10" etiketi. Art arda çift tap'ler birikir (örn. 3 kez sağ = +30 sn tek seek).
**Kabul kriterleri:**
- [ ] Bölge ayrımı: sol %40 / orta %20 (yalnız tek tap) / sağ %40.
- [ ] Bölüm sonuna 10 sn'den az kala ileri atlama bölüm sonuna gider (otomatik sonraki bölüme taşmaz); başa 10 sn'den az kala geri atlama 0'a gider.
- [ ] Seek `tolerance` ayarı ile keskin (`toleranceBefore/After = .zero` yalnız scrubber bırakışında; çift tap'te hızlı tolerant seek) — ayrıntı `04-player-engine.md`.
- [ ] Kilitli bölüme ileri atlanamaz (bölüm zaten oynuyorsa bu durum oluşmaz; ileri atlama mevcut bölüm içinde sınırlıdır).

#### PLR-03 — Uzun bas: 2x hız — **Must, F1**
**Davranış:** Video alanına basılı tutunca oynatma 2.0x'e çıkar; ekranda "2x ▶▶" rozeti görünür; parmak kalkınca kullanıcının seçili hızına (PLR-04) geri döner.
**Kabul kriterleri:**
- [ ] Eşik 400 ms; öncesinde bırakılırsa tek tap sayılır.
- [ ] 2x sırasında ses tonu korunarak hızlanır (`AVPlayerItem.audioTimePitchAlgorithm = .timeDomain`).
- [ ] Uzun bas sırasında dikey kaydırma başlarsa 2x iptal edilir ve kaydırma işler.

#### PLR-04 — Hız seçici — **Should, F1**
**Davranış:** Overlay'deki hız rozetinden (varsayılan "1x") seçici açılır: 0.75x / 1x / 1.25x / 1.5x / 2x. Seçim oturum boyunca ve bölümler arası kalıcıdır; UserDefaults'a yazılır.
**Kabul kriterleri:**
- [ ] Seçilen hız otomatik sonraki bölümde de korunur.
- [ ] PLR-03 (geçici 2x) bittiğinde bu seçime dönülür.
- [ ] Hız ≠ 1x iken rozet vurgulu gösterilir.

#### PLR-05 — Scrubber + zaman göstergesi — **Must, F1 (thumbnail önizleme: Could, F2)**
**Davranış:** Alt kenarda ilerleme çubuğu; dokun-sürükle ile konum arama. Sürükleme sırasında geçerli/toplam süre büyük tipografiyle gösterilir; bırakınca oynatma o konumdan sürer. F2'de sürükleme sırasında kare önizlemesi (trick play/I-frame varyantı) eklenebilir.
**Kabul kriterleri:**
- [ ] Sürükleme başlayınca dikey paging kilitlenir; bırakınca açılır.
- [ ] Sürükleme sırasında video sesi susturulur, bırakınca döner.
- [ ] Bırakış → yeni konumda oynatma ≤ 300 ms (buffer'lı bölge içinde ≤ 100 ms).
- [ ] Pasif durumda çubuk ince (2 pt), etkileşimde kalın (6 pt) — `DesignSystem` token'ları.

#### PLR-06 — Bölüm listesi sheet (`BolumListesi`) — **Must, F1**
**Davranış:** Overlay'deki bölüm butonu player üzerinde `BolumListesi` sheet'ini açar: bölüm numarası ızgarası; izlenenler işaretli, mevcut bölüm vurgulu, kilitliler kilit ikonu + coin fiyatıyla. Bölüme dokununca player o bölüme geçer (kilitliyse `UnlockSheet`).
**Kabul kriterleri:**
- [ ] Sheet açıkken video oynamaya devam eder (arka planda görünür kalır); tam ekran kaplamaz (yaklaşık %60 yükseklik, sürüklenebilir).
- [ ] 100+ bölümlü dizilerde ızgara aralık sekmeleriyle (1–30, 31–60, …) gezinilebilir; hedef bölüme kaydırma < 1 kare takılma.
- [ ] Kilitli bölüm hücresinde `unlockPrice` API değeri gösterilir; VIP kullanıcıda kilit ikonu yerine VIP rozeti ve doğrudan oynatma.
- [ ] Sheet, `DiziDetay`'daki bölüm ızgarasıyla aynı bileşeni paylaşır (tek kaynak: `ContentKit` + `DesignSystem`).

#### PLR-07 — Paylaş — **Must, F1**
**Davranış:** Aksiyon sütunundaki paylaş butonu sistem share sheet'ini açar: dizi/bölüm Universal Link'i + kapak görseli + kısa metin (SHR-01/02 ile aynı altyapı).
**Kabul kriterleri:**
- [ ] Paylaşım sırasında video duraklar; sheet kapanınca sürer.
- [ ] Paylaşılan link açıldığında doğru dizi/bölüme gider (SHR-02 kabul kriterleri).
- [ ] Paylaşma eylemi tamamlanınca (activity completed) OdulMerkezi "paylaş" görevi ilerler (RWD-02).

#### PLR-08 — Favori — **Must, F1**
**Davranış:** Kalp butonu diziyi favorilere ekler/çıkarır; anlık optimistic UI, arka planda API çağrısı; `Listem` → Favoriler ile senkron.
**Kabul kriterleri:**
- [ ] Optimistic güncelleme başarısız API çağrısında geri alınır ve hafif toast gösterilir.
- [ ] Favori durumu `PlayerFeed`, `DiziDetay` ve `Listem` arasında tek kaynaktan (LibraryKit store) tutarlıdır.
- [ ] İlk favorileme "görev" ilerlemesi sayılır (RWD-02).

#### PLR-09 — Otomatik sonraki bölüm — **Must, F1**
**Davranış:** Bölüm bitince otomatik olarak sonraki bölüme geçilir ve oynatma kesintisiz sürer (cliffhanger→binge döngüsünün istemci yarısı; `07-retention-gamification.md`). Sonraki bölüm kilitliyse `UnlockSheet` açılır. `Ayarlar` → Oynatma tercihleri → "Otomatik oynatma" kapatılabilir; kapalıyken bölüm sonunda "Sonraki bölüm" kartı gösterilir.
**Kabul kriterleri:**
- [ ] Otomatik geçişte ekran kararması/boş kare olmadan < 100 ms'de sonraki bölüm oynar (prefetch edilmiş player).
- [ ] Geçiş, feed'in görsel olarak bir sayfa ilerlemesiyle eşzamanlıdır (kullanıcı feed'de nerede olduğunu kaybetmez).
- [ ] Otomatik oynatma kapalıyken sayaç yoktur; kullanıcı karta dokunana ya da kaydırana kadar beklenir.
- [ ] Dizi son bölümünde bitti ekranı: "Diziyi bitirdin" + yeni dizi önerisi kartı; kaydırma yeni diziye götürür.

#### PLR-10 — Altyazı kontrolü — **Must, F1**
**Davranış:** Overlay'den altyazı aç/kapa ve dil seçimi (mevcut diller bölümün HLS manifest'inden). Ayrıntı LOC-01/02.
**Kabul kriterleri:**
- [ ] Seçim bölümler arası ve oturumlar arası kalıcıdır.
- [ ] Altyazı yoksa buton pasif ve "Bu bölümde altyazı yok" tooltip'i gösterilir.

#### PLR-11 — Ses oturumu ve sessiz mod — **Must, F1**
**Davranış:** `AVAudioSession` kategori `.playback`: cihaz sessiz anahtarı açık olsa da video sesli oynar (kategori standardı; ReelShort/DramaBox davranışıyla parite). Arka plan sesi YOK (video-first uygulama).
**Kabul kriterleri:**
- [ ] Müzik çalan başka uygulama, video oynatılınca duraklatılır (kategori gereği); uygulamadan çıkınca sistem davranışına bırakılır.
- [ ] AirPods/hoparlör route değişimlerinde oynatma kesilmez (yalnız kulaklık ÇIKARILINCA duraklar, FEED-09).

---

### 2.4 Keşfet & Arama (`Kesfet`, `Arama`; modül: `DiscoverKit`)

#### DSC-01 — Keşfet rafları — **Must, F1**
**Davranış:** **Keşfet** sekmesi (`Kesfet`) sunucudan gelen raf düzenini çizer: üstte banner karuseli, altında koleksiyon rafları ve sıralamalar (**Trend**, **Yeni**, **Top 10**). Raf sırası ve içerik tamamen API'den (server-driven layout; sözleşme `05-veri-modeli-api.md`).
**Kabul kriterleri:**
- [ ] Raf türleri: banner (tam genişlik, otomatik dönen ≤ 5 sn aralıklı), poster rafı (yatay kaydırma), Top 10 rafı (büyük sıra numaralı).
- [ ] Karta dokunuş `DiziDetay`'a; bannera dokunuş banner'ın hedef rotasına (dizi/koleksiyon/kampanya — deep link rotalarıyla aynı şema, SHR-02).
- [ ] Kapak görselleri disk cache'li; raf kaydırma 60 fps.
- [ ] İçerik yüklenene kadar iskelet raflar; hata durumunda raf bazında yeniden deneme.

#### DSC-02 — Tür filtreleri — **Must, F1**
**Davranış:** `Kesfet` üst bölümünde yatay tür çipleri (API'den). Seçim, raf görünümünü o türün ızgara listesine çevirir; "Tümü" ile raf görünümüne dönülür.
**Kabul kriterleri:**
- [ ] Tür listesi sıralaması sunucudan gelir; seçim tekli.
- [ ] Izgara cursor sayfalamalı sonsuz kaydırma; boş tür için boş durum tasarımı.

#### DSC-03 — Arama — **Must, F1**
**Davranış:** `Kesfet` üstündeki arama alanına dokununca `Arama` ekranı açılır: arama çubuğu + (boş durumda) popüler aramalar ve son aramalar; yazarken otomatik tamamlama; göndermede sonuç ızgarası (dizi kartları).
**Kabul kriterleri:**
- [ ] Sorgu debounce 300 ms; önceki istek iptal edilir (task cancellation).
- [ ] Sonuç yoksa: "Sonuç bulunamadı" + popüler diziler rafı (boş elde bırakma).
- [ ] Son aramalar cihazda tutulur (en çok 10), tek tek ve toplu silinebilir.

#### DSC-04 — Otomatik tamamlama — **Should, F1**
**Kabul kriterleri:**
- [ ] İlk 2 karakterden sonra öneri listesi; öneriye dokunuş doğrudan `DiziDetay`'a (dizi önerisi) veya sonuç listesine (sorgu önerisi) gider.
- [ ] Öneri yanıtı p95 < 300 ms hedefi (backend SLO; istemci 1 sn'de zaman aşımıyla sessiz düşer).

#### DSC-05 — Popüler aramalar — **Should, F1**
**Kabul kriterleri:**
- [ ] Liste remote'tan gelir ve en az günlük tazelenir; dokunuş sorguyu doldurup aramayı çalıştırır.

#### DSC-06 — Kişiselleştirilmiş öneri rafları — **Should, F2**
**Davranış:** `Kesfet` içinde "Sana özel" rafı ve `PlayerFeed` sıralamasının izleme sinyalleriyle (tamamlama, skip, favori, unlock) beslenmesi. Model sunucu tarafındadır; istemci sinyalleri `AnalyticsKit` event'leriyle gönderir.
**Kabul kriterleri:**
- [ ] İzleme sinyali sözleşmesi `08-analitik-deney.md` ile bire bir aynıdır (çift şema yok).

---

### 2.5 DiziDetay & BolumListesi (modül: `ContentKit`, `DiscoverKit`)

#### DTL-01 — DiziDetay ekranı — **Must, F1**
**Davranış:** `DiziDetay`: büyük kapak, başlık, özet (2 satır + "devamı"), etiketler (tür çipleri), bölüm sayısı/durumu ("80 bölüm • Tamamlandı" ya da "34 bölüm • Devam ediyor"), bölüm ızgarası, sabit alt CTA.
**Kabul kriterleri:**
- [ ] Ekran kapak + özet iskeletiyle anında açılır; bölüm ızgarası ayrı istekle dolar.
- [ ] Etiket çipine dokunuş `Kesfet`'in o tür ızgarasına gider.
- [ ] Paylaş ve listeye ekle (favori) başlık bölgesinde; davranışları PLR-07/PLR-08 ile aynı bileşenden.

#### DTL-02 — "İzlemeye Başla / Devam Et" CTA — **Must, F1**
**Davranış:** Kullanıcının diziyle geçmişi yoksa "İzlemeye Başla" (1. bölüm); geçmişi varsa "Devam Et • B12 03:24". Dokunuş `PlayerFeed` player'ını ilgili bölüm+konumda açar.
**Kabul kriterleri:**
- [ ] CTA durumu LibraryKit izleme geçmişinden türetilir; `Listem` → Devam Et ile aynı veriyi gösterir.
- [ ] Devam edilen bölüm sonradan kilitlendiyse (edge case: fiyat/politika değişimi) CTA `UnlockSheet`'e yönlendirir.

#### DTL-03 — Bölüm ızgarası + kilit durumu — **Must, F1**
**Davranış:** Numaralı bölüm hücreleri: izlendi (soluk + tik), mevcut (vurgu), açık (normal), kilitli (kilit ikonu + coin fiyatı). PLR-06'daki `BolumListesi` sheet ile AYNI bileşen.
**Kabul kriterleri:**
- [ ] Kilitli hücreye dokunuş `UnlockSheet` açar; unlock sonrası ızgara anında güncellenir.
- [ ] Henüz yayınlanmamış bölümler (release schedule, DTL-05) "🗓 12 Tem" gibi tarih rozetiyle pasif gösterilir.

#### DTL-04 — Listeye ekle / paylaş — **Must, F1**
(PLR-07 ve PLR-08 kabul kriterleri geçerli; tek fark yüzeyin `DiziDetay` olması.)

#### DTL-05 — Yeni bölüm takvimi — **Should, F2**
**Davranış:** Bölüm bölüm yayınlanan dizilerde `DiziDetay` üstünde "Yeni bölüm: Cuma" bilgisi; kullanıcı "Hatırlat" ile diziye özel push aboneliği açar (NTF-02).
**Kabul kriterleri:**
- [ ] Takvim verisi API'den (`releaseSchedule`); cihaz saat dilimine göre gösterilir.

---

### 2.6 Kilit / unlock akışı (`UnlockSheet`; modül: `WalletKit`)

Kanonik erişim modeli: dizi başına ilk 5–10 bölüm ücretsiz (~ilk 10 dakika), sonrası bölüm başına kilitli; kilit cliffhanger noktasına denk gelir (içerik ekibi belirler). İstemci hiçbir kilit kuralını hard-code ETMEZ; `unlockPrice` ve ücretsiz bölüm sayısı API'den okunur. Ayrıntılı ekonomi: `06-monetizasyon.md`.

#### UNL-01 — UnlockSheet (paywall) — **Must, F1**
**Davranış:** Kilitli bölüme gelindiğinde açılan sheet üç seçenek sunar: **(a)** coin ile aç (fiyat + mevcut bakiye), **(b)** reklam izleyerek aç (F2; F1'de bu satır gizli), **(c)** VIP ol (tüm bölümler açık). Coin yetersizse (a) satırı "Coin al" CTA'sına dönüşür ve `CoinMagazasi`'na akar (UNL-03).
**Kabul kriterleri:**
- [ ] Sheet'te bölüm bilgisi (dizi adı + bölüm no), `unlockPrice`, kullanıcının purchased+earned toplam bakiyesi görünür.
- [ ] "Coin ile aç" tek dokunuş + tek onaydır (ekstra ara ekran yok); başarıda sheet kapanır ve video otomatik başlar (FEED-05).
- [ ] VIP satırı `VIPAbonelik`'e gider; abonelik tamamlanırsa dönüşte bölüm açılmış olur.
- [ ] Sheet kapatma her zaman mümkündür (kapatma X + aşağı sürükleme); zorla izletme yok.
- [ ] Tüm unlock denemeleri idempotency key ile gönderilir; çift dokunuş çift harcama YARATAMAZ.

```swift
// WalletKit — unlock akışının durum makinesi (iskelet)
enum UnlockRoute: Sendable {
    case spendCoins(price: Int)          // bakiye yeterli
    case needsTopUp(missing: Int)        // CoinMagazasi'na akış
    case watchRewardedAd                 // F2, remote config ile açılır
    case subscribeVIP
}

enum UnlockResult: Sendable {
    case unlocked(playbackToken: SignedPlaybackToken)
    case cancelled
    case failed(UnlockError)             // insufficientCoins, network, adNotReady...
}
```

#### UNL-02 — Dinamik unlockPrice — **Must, F1**
**Davranış:** Bölüm kilidi 50–100 coin aralığında, API'den `unlockPrice` alanıyla gelir; dizi/bölüm bazında farklılaşabilir.
**Kabul kriterleri:**
- [ ] İstemcide varsayılan/fallback fiyat YOKTUR; `unlockPrice` gelmeyen kilitli bölüm oynatılamaz ve hata telemetrisi düşülür.
- [ ] Fiyat, `BolumListesi`, `DiziDetay` ızgarası ve `UnlockSheet`'te aynı kaynaktan gösterilir.

#### UNL-03 — Yetersiz bakiye → CoinMagazasi akışı — **Must, F1**
**Davranış:** Bakiye < fiyat ise `UnlockSheet` içinden `CoinMagazasi` açılır (aynı sheet yığını içinde; bağlam korunur). Başarılı satın alma sonrası `UnlockSheet`'e geri dönülür; bakiye güncellenmiştir ve "Coin ile aç" butonu aktiftir. **Unlock otomatik yürütülmez** — son dokunuşu kullanıcı yapar (sürpriz harcama şikâyeti/iade riskini düşürür). Tek istisna: otomatik-unlock toggle'ı açıksa (UNL-04) bekleyen bölüm dönüşte sorulmadan açılır. Ayrıntı: `06-monetizasyon.md`.
**Kabul kriterleri:**
- [ ] Satın alma tamamlanınca kullanıcı `UnlockSheet`'e güncellenmiş bakiyeyle döndürülür; birincil buton aktifleşir ve tek dokunuşla bölüm açılır (yeniden fiyat onayı ara ekranı yoktur).
- [ ] Otomatik coin harcaması YALNIZ otomatik-unlock toggle'ı açıkken gerçekleşir (UNL-04); toggle kapalıyken kullanıcı dokunuşu olmadan hiçbir coin düşülmez.
- [ ] Satın alma iptalinde `UnlockSheet`'e eski haliyle geri dönülür; hiçbir coin düşülmemiştir.

#### UNL-04 — Otomatik unlock (auto-unlock) — **Should, F1**
**Davranış:** Kullanıcı `UnlockSheet`'te "Sonraki bölümleri otomatik aç" anahtarını açarsa, bakiye yettiği sürece o dizinin kilitli bölümlerinde sheet gösterilmeden coin düşülür ve binge kesintisiz sürer. Anahtar **dizi başına** bir ayardır ve sunucuda saklanır (dizi bazlı kullanıcı tercihi; sözleşme `05-veri-modeli-api.md`); yönetimi `UnlockSheet` üzerindendir. Otomatik akış yalnız coin harcar; rewarded ad ve VIP kapsam dışıdır. Ayrıntı: `06-monetizasyon.md`.
**Kabul kriterleri:**
- [ ] Otomatik harcamada ekranda kısa, engellemeyen bilgi çipi görünür ("−60 coin • B13 açıldı"); çipte "geri al" YOKTUR (unlock kalıcıdır) ama toggle'ı kapatan hızlı eylem vardır.
- [ ] Bakiye yetmediği anda normal `UnlockSheet` açılır (UNL-03 coin yetersiz akışı).
- [ ] Aynı bölüm hiçbir durumda iki kez ücretlendirilmez (sunucu idempotency); art arda kaydırılan çoklu kilitli bölümlerde istekler sıralı, teker teker işlenir (aynı anda en fazla 1 bekleyen unlock).
- [ ] Varsayılan: KAPALI (kullanıcı açıkça açar; varsayılan değer remote config ile deneye açıktır).

#### UNL-05 — Rewarded ad ile kilit açma — **Must, F2**
**Davranış:** `UnlockSheet` (b) seçeneği: 30 sn'lik rewarded ad %100 tamamlanınca bölüm açılır. Günlük cap 5–10 (remote config). AdMob birincil aday; köprü `RewardsKit` üzerinden.
**Kabul kriterleri:**
- [ ] Ödül YALNIZ ad ağının tamamlanma callback'i + sunucu doğrulaması (SSV) sonrası verilir; erken kapatma ödül vermez ve hakkı tüketmez.
- [ ] Cap dolunca satır pasifleşir ve "Yarın yeniden" etiketi gösterilir; cap durumu sunucuda tutulur (cihaz saati oynatmaları işe yaramaz).
- [ ] Reklam envanteri hazır değilse (no-fill) satır gizlenir, coin/VIP yolları etkilenmez.

#### UNL-06 — İmzalı URL + FairPlay DRM — **Must, F1 (imzalı URL) / Must, F2 (FairPlay)**
**Davranış:** Tüm medya erişimi kısa ömürlü imzalı URL ile; kilitli bölümün playback token'ı yalnız unlock/entitlement sonrası verilir. FairPlay DRM Faz 2'de imzalı URL'in üzerine eklenir.
**Kabul kriterleri:**
- [ ] Süresi dolan imzalı URL oynatma sırasında sessizce yenilenir (kullanıcı hata görmez).
- [ ] Entitlement'sız playback token isteği sunucuda 403 döner; istemci bu durumda `UnlockSheet`'e düşer.

---

### 2.7 CoinMagazasi & VIPAbonelik (modül: `WalletKit`)

ShortSeries fiyat kanonu (App Store, USD): coin paketleri **$0.99 / $4.99 / $9.99 / $19.99 / $49.99 / $99.99**, artan bonus coin kademeleri (%0→%100), ilk yüklemeye özel **2x bonus**. VIP: **haftalık $5.99 (intro $3.99/ilk hafta), aylık $14.99, yıllık $49.99**. Ayrıntı ve SKU tablosu: `06-monetizasyon.md`.

#### PAY-01 — Coin paketleri — **Must, F1**
**Davranış:** `CoinMagazasi` altı paket kademesini bonus yüzdeleriyle listeler; paket içerikleri (coin adedi + bonus) StoreKit ürün metadata'sı + backend kataloğundan gelir. Coin = StoreKit 2 consumable.
**Kabul kriterleri:**
- [ ] Fiyatlar her zaman StoreKit'in yerelleştirilmiş `displayPrice` değeriyle gösterilir (hard-code fiyat yok).
- [ ] Satın alma → sunucu makbuz doğrulaması (App Store Server API) → cüzdana purchased coin yazımı; başarı ancak sunucu onayıyla gösterilir.
- [ ] Aynı transaction'ın tekrar bildirimi (replay) sunucuda idempotent'tir; istemci "zaten işlendi" yanıtını başarı sayar.
- [ ] Askıda kalan transaction'lar (`Transaction.updates`) uygulama açılışında işlenir — kesintiye uğrayan satın alma coin kaybettirmez.

#### PAY-02 — İlk yükleme 2x bonus teklifi — **Must, F1**
**Davranış:** Hesap bazında yalnız ilk coin satın alımında geçerli 2x bonus rozeti; `CoinMagazasi` üstünde vurgulu kart.
**Kabul kriterleri:**
- [ ] "İlk yükleme" durumu sunucuda tutulur (cihaz değişse de bir kez); kullanıldıktan sonra kart kaybolur.
- [ ] Teklifin gösterimi/dönüşümü A/B deneyine açıktır (`08-analitik-deney.md`).

#### PAY-03 — StoreKit 2 + server-side doğrulama — **Must, F1**
**Davranış:** Tüm IAP StoreKit 2 (`Product.purchase()`, `Transaction`); makbuzlar App Store Server API ile sunucuda doğrulanır; abonelik yaşam döngüsü App Store Server Notifications V2 ile sunucuya akar. İstemci entitlement'ı sunucudan okur.
**Kabul kriterleri:**
- [ ] İstemcide makbuz doğrulaması TEK BAŞINA güven kaynağı değildir; cüzdan/entitlement yazımı yalnız sunucuda olur.
- [ ] "Ask to Buy" (aile onayı) bekleyen durumu kullanıcıya doğru anlatılır; onay gelince arka planda işlenir.
- [ ] Sandbox ve production ortam ayrımı yapılandırmayla yönetilir.

#### PAY-04 — Purchased vs earned coin ayrımı — **Must, F1**
**Davranış:** Cüzdan iki bakiye tutar: **purchased** (IAP ile alınan) ve **earned** (check-in/görev/rewarded ad). Harcama önceliği: **earned önce**. Ayrım muhasebe + App Store komisyon farkı için zorunludur; earned coin'ler son kullanma tarihli olabilir (RWD-05). İstemci `WalletStore` actor'ü sunucu cüzdanının cache'idir; idempotent işlemler, double-entry kayıt, audit trail ve fraud kontrolleri (receipt replay, jailbreak, anormal kazanç hızı) sunucu sorumluluğudur (`05-veri-modeli-api.md`, `06-monetizasyon.md`).
**Kabul kriterleri:**
- [ ] UI'da toplam bakiye tek sayı olarak gösterilir; dokununca purchased/earned kırılımı ve (varsa) yaklaşan son kullanma tarihi görünür.
- [ ] Unlock işlemi sunucuda earned→purchased sırasıyla düşer; istemci sıralamayı asla kendi hesaplamaz.
- [ ] Bakiye uyuşmazlığında (istemci cache ≠ sunucu) sunucu kazanır ve cache sessizce düzeltilir.

#### PAY-05 — VIP planları — **Must, F1**
**Davranış:** `VIPAbonelik` üç planı karşılaştırmalı gösterir: haftalık $5.99 (intro $3.99/ilk hafta), aylık $14.99, yıllık $49.99 (auto-renewable subscription; intro offer StoreKit'te tanımlı).
**Kabul kriterleri:**
- [ ] Intro offer uygunluğu StoreKit `eligibleForIntroOffer` üzerinden kontrol edilir; uygun olmayana intro fiyat GÖSTERİLMEZ.
- [ ] Plan değişimi (upgrade/downgrade/crossgrade) StoreKit yönetim ekranına yönlendirilir; durum Server Notifications V2 ile senkronlanır.
- [ ] Abonelik durumu (aktif, grace period, billing retry, expired) `Profil`'de doğru rozetle görünür.

#### PAY-06 — VIP ayrıcalıkları — **Must, F1**
**Davranış:** Aktif VIP: tüm bölümler açık (unlock ekranı hiç görülmez) + günlük bonus coin (OdulMerkezi'nden claim, RWD-01 döngüsüne ek satır) + reklamsız (F2'de rewarded ad kartı VIP'e gizlenmez — isteğe bağlı kazanım — ama interstitial benzeri hiçbir zorunlu reklam YOKTUR; zaten F1–F3'te zorunlu reklam formatı planlanmıyor).
**Kabul kriterleri:**
- [ ] VIP entitlement'ı sunucudan gelir ve kilit kontrolünün önünde değerlendirilir; VIP'ken `BolumListesi`/`DiziDetay`'da kilit ikonu yerine VIP rozeti.
- [ ] VIP süresi biterse kilitler geri gelir; VIP döneminde coin'le açılmış bölümler AÇIK kalır (unlock kalıcıdır).

#### PAY-07 — Satın alma geri yükleme & abonelik yönetimi — **Must, F1**
**Kabul kriterleri:**
- [ ] "Satın alımları geri yükle" `CoinMagazasi`, `VIPAbonelik` ve `Ayarlar`'da bulunur; abonelik entitlement'ını ve işlenmemiş transaction'ları toplar.
- [ ] "Aboneliği yönet" sistem abonelik sayfasını açar.

#### PAY-08 — Cüzdan görünümü ve işlem geçmişi — **Should, F1 (bakiye), Should, F2 (işlem geçmişi listesi)**
**Kabul kriterleri:**
- [ ] Coin bakiyesi `OdulMerkezi`, `CoinMagazasi`, `UnlockSheet` ve `Profil`'de aynı store'dan, tutarlı gösterilir.
- [ ] F2: işlem geçmişi (kazanım/harcama satırları, tarih, kaynak) `Profil` altından erişilir.

---

### 2.8 OdulMerkezi — Ödüller sekmesi (modül: `RewardsKit`)

Retention hedefleri bağlamı (kanon): D1 ≥ %30, D7 ≥ %10, D30 ≥ %5; kategori ortalaması D1 ~%27 / D7 ~%8.6 / D14 ~%5.6; rewarded engagement kullanıcıları ~3x daha sık geri dönüyor (adjoe). Mekanik ayrıntıları: `07-retention-gamification.md`.

#### RWD-01 — Günlük check-in (7 gün döngü) — **Must, F1**
**Davranış:** `OdulMerkezi` üstünde 7 günlük takvim: her gün artan coin (10–50 aralığında, değerler remote config), 7. günde en yüksek ödül; döngü tamamlanınca yeniden başlar. Gün atlanırsa döngü 1. güne döner (streak bonusu F2'de bunu yumuşatır, RWD-06). Claim tek dokunuştur.
**Kabul kriterleri:**
- [ ] "Gün" tanımı server-otoritatiftir; gün sınırı kullanıcının cihaz saat diliminde 00:00'dır (istemci her istekte IANA timezone gönderir, sunucu doğrular ve karar verir). Cihaz saati/saat dilimi manipülasyonu kazanım yaratamaz: son check-in'den 20 saatten kısa aralıkla ikinci claim sunucuda reddedilir (`07-retention-gamification.md`).
- [ ] Claim idempotent'tir; çift dokunuş tek ödül yazar.
- [ ] Claim edilen coin **earned** bakiyeye yazılır (PAY-04) ve animasyonla bakiyeye akar.
- [ ] Bugünün ödülü claim edilmişse kart "yarın gel" durumuna düşer ve kalan süreyi gösterir.

#### RWD-02 — Görev listesi — **Must, F1**
**Davranış:** Sunucu tanımlı görevler: örn. "Bugün 10 dk izle" (izleme süresi), "Bir diziyi favorile", "Bir bölüm paylaş", "Bildirimlere izin ver" → her biri coin ödüllü. İlerleme çubuğu + "Topla" butonu. Görev kataloğu ve ödüller remote'tan gelir; istemci yeni görev tipi eklemek için güncelleme gerektirmeyecek şekilde generic görev modeli kullanır (bilinmeyen tip = gizle).
**Kabul kriterleri:**
- [ ] Görev ilerlemesi ilgili gerçek event'lerden beslenir (`AnalyticsKit` event'leriyle aynı tanım; çifte sayım yok).
- [ ] "Topla" sunucu onayıyla earned coin yazar; toplandıktan sonra görev "tamamlandı" durumunda görünür (günlük görevler ertesi gün sıfırlanır).
- [ ] Bildirim izni görevi, izin zaten verilmişse otomatik tamamlanmış görünür.

#### RWD-03 — Rewarded ad kartı — **Must, F2**
**Davranış:** `OdulMerkezi`'nde "Reklam izle, coin kazan" kartı: kalan günlük hak (cap 5–10, remote config), 30 sn tamamlama şartı. Kart, UNL-05'teki bölüm-unlock ile **AYNI günlük cap havuzunu paylaşır** (karar: `06-monetizasyon.md`); UI her iki yüzeyde de kalan hakkı gösterir ("Bugün 3/5"). Ödül **earned** coin'dir (son kullanma tarihli olabilir, RWD-05).
**Kabul kriterleri:**
- [ ] UNL-05'teki SSV, cap ve no-fill kuralları aynen geçerli.
- [ ] Kart, reklam envanteri yokken gizlenir; VIP kullanıcıya isteğe bağlı olarak gösterilmeye devam eder (reklamsızlık vaadi zorunlu reklamları kapsar).

#### RWD-04 — Coin bakiyesi gösterimi — **Must, F1**
**Kabul kriterleri:**
- [ ] `OdulMerkezi` başlığında bakiye + `CoinMagazasi` kısayolu; kazanımlarda bakiye animasyonlu güncellenir.

#### RWD-05 — Earned coin son kullanma tarihi — **Should, F2**
**Davranış:** Earned coin'lere sunucu politikasıyla son kullanma tarihi eklenebilir; süresi yaklaşanlar cüzdan kırılımında ve `OdulMerkezi`'nde uyarı çipiyle gösterilir.
**Kabul kriterleri:**
- [ ] Süre dolumu yalnız sunucuda işler; istemci yalnız gösterir.
- [ ] Son 48 saat için "coinlerin yanmak üzere" bilgilendirmesi (push'a bağlanabilir, NTF-02).

#### RWD-06 — Streak bonusu — **Should, F2**
**Davranış:** Kesintisiz check-in serilerine ek bonus (örn. 30 gün rozeti); seri kaybında "seri kurtarma" teklifi (reklam izle ya da küçük coin bedeli — remote config ile açılır/kapanır).
**Kabul kriterleri:**
- [ ] Seri durumu sunucuda; kurtarma günde en fazla 1 kez.

---

### 2.9 Listem (modül: `LibraryKit`)

#### LIB-01 — Favoriler — **Must, F1**
**Davranış:** **Listem** sekmesinin ilk segmenti: favorilenen diziler, son eklenen üstte; kart üzerinde yeni bölüm rozeti (varsa).
**Kabul kriterleri:**
- [ ] PLR-08/DTL-04 ile aynı store; ekleme/çıkarma her yüzeyde anında yansır.
- [ ] Boş durum: açıklama + `Kesfet`'e CTA.
- [ ] Kaydırarak (swipe) favoriden çıkarma + geri al (undo) snackbar'ı.

#### LIB-02 — Devam Et (izleme geçmişi + kaldığı yer) — **Must, F1**
**Davranış:** İkinci segment: izlenen diziler, her kartta ilerleme çubuğu ("B12 • %63") ve dokununca player'ın o bölüm+konumdan açılması. Sıralama: son izlenen üstte.
**Kabul kriterleri:**
- [ ] Kaynak SwiftData izleme geçmişi; FEED-07 ve DTL-02 ile aynı tek kaynak.
- [ ] Bitirilen diziler listede "Tamamlandı" rozetiyle kalır; kart menüsünden geçmişten kaldırılabilir.
- [ ] F2: hesap bağlıysa sunucu senkronu (ONB-08) bu listeyi cihazlar arası birleştirir.

#### LIB-03 — İndirilenler — **Must (F3 kapsamı içinde), F3**
**Davranış:** Üçüncü segment F1–F2'de görünmez; F3'te offline indirilen bölümler burada listelenir (DLD-02). F1–F2'de segment kontrolü iki seçeneklidir.
**Kabul kriterleri:** (bkz. §2.14 DLD-02)

#### LIB-04 — Yerel persistence — **Must, F1**
**Kabul kriterleri:**
- [ ] Favoriler, geçmiş ve kaldığı yer SwiftData'da saklanır; uygulama çevrimdışıyken de okunabilir.
- [ ] Çevrimdışı yapılan favori/kaldırma işlemleri kuyruklanır ve bağlantı gelince sunucuya işlenir (last-write-wins).

---

### 2.10 Profil & Ayarlar (modül: `ProfileKit`)

#### PRF-01 — Profil ekranı — **Must, F1**
**Davranış:** **Profil** sekmesi: hesap durumu (misafir → "Hesabını bağla" kartı; bağlı → ad/e-posta), coin bakiyesi + `CoinMagazasi` kısayolu, VIP durumu + `VIPAbonelik` kısayolu, izleme geçmişi girişi, `Ayarlar` girişi, destek/yardım.
**Kabul kriterleri:**
- [ ] Misafir kullanıcıda hesap bağlama kartı değer önerisiyle sunulur ("İlerlemen ve coinlerin güvende kalsın").
- [ ] VIP satırı abonelik durumunu (aktif/bitiş tarihi/grace) doğru gösterir (PAY-05).

#### PRF-02 — Coin/VIP durumu — **Must, F1**
(PAY-08 ve PAY-05 kabul kriterleri geçerli; yüzey `Profil`.)

#### PRF-03 — Ayarlar — **Must, F1**
**Davranış:** `Ayarlar` bölümleri: **Dil** (uygulama dili + varsayılan altyazı dili, ayrı ayrı), **Bildirim tercihleri** (tür bazında anahtarlar: yeni bölüm / devam et hatırlatması / coin-ödül / öneriler), **Oynatma tercihleri** (otomatik oynatma PLR-09, veri tasarrufu FEED-06; otomatik unlock dizi başına bir ayardır ve `UnlockSheet` üzerinden yönetilir, UNL-04), **Hesap yönetimi** (bağlama, çıkış, hesap silme ONB-07), **Yasal** (kullanım koşulları, gizlilik, üçüncü parti lisansları, künye).
**Kabul kriterleri:**
- [ ] Uygulama dili değişimi uygulama yeniden başlatılmadan uygulanır (scene yeniden yüklenebilir).
- [ ] Bildirim tür anahtarları sunucuya yazılır (push segmentasyonu bunlara uyar; NTF-03).
- [ ] Sistem bildirim izni kapalıysa bildirim bölümü ayarlara yönlendiren durum kartı gösterir.

#### PRF-04 — İzleme geçmişi — **Must, F1**
**Kabul kriterleri:**
- [ ] `Profil` → İzleme geçmişi, LIB-02 ile aynı veriden tam listeyi (tarih gruplu) gösterir; tekil silme ve tümünü temizleme vardır.

#### RTG-01 — Mağaza puanı isteme (SKStoreReviewController) — **Should, F1**
**Davranış:** Sistem puan isteme diyaloğu yalnız pozitif anlarda tetiklenir: bölüm tamamlama ve/veya check-in streak günü (tetik kombinasyonu remote config). Yakın zamanda hata (oynatma hatası, başarısız satın alma) ya da iade/şikayet sinyali yaşayan kullanıcıya istem gösterilmez; bu kullanıcılara önce destek akışı sunulur. Mekanizma, `00-genel-bakis.md`'deki "fiyat şikayetleri ve puan erozyonu" riskinin (yüksek olasılık) azaltmasıdır.
**Kabul kriterleri:**
- [ ] İstem yalnız pozitif an tetiklerinde çağrılır; oynatma sırasında, paywall'da ya da hata ekranlarında ASLA gösterilmez.
- [ ] iOS'un yıllık en fazla 3 gösterim sınırına saygı duyulur; istemci kendi frekans kuralını tutar (tetikler arası asgari süre remote config) ve gösterim hakkını israf etmez.
- [ ] Şikayet/hata sinyali penceresi (örn. son X gün, remote config) içindeki kullanıcıda istem bastırılır ve destek akışı önceliklenir.
- [ ] Remote config kill-switch ile istem tamamen kapatılabilir.
- [ ] İstem tetiklenmesi analitik event olarak yazılır (`08-analitik-deney.md`); sistemin diyaloğu gerçekten gösterip göstermediği API tarafından garanti edilmediğinden event "istek" düzeyindedir.
**Etki notu:** `09-yol-haritasi-tasklar.md`'ye ilgili task açılmalıdır.

---

### 2.11 Bildirimler (modül: `AppFoundation` + `RewardsKit` tetikleri)

#### NTF-01 — APNs push + rich push — **Must, F1**
**Davranış:** APNs entegrasyonu; rich push (görselli — dizi kapağı) Notification Service Extension ile. İzin akışı ONB-05'e bağlı.
**Kabul kriterleri:**
- [ ] Push'a dokunuş deep link rotasına gider (SHR-02 şeması): dizi, bölüm, `OdulMerkezi` veya `CoinMagazasi`.
- [ ] Görsel indirilemezse bildirim metin haliyle düşer (extension asla bildirimi düşürmez).
- [ ] Token kaydı/silmesi oturum yaşam döngüsüne bağlıdır (hesap değişince eski token temizlenir).

#### NTF-02 — Push türleri — **Must, F1 (yeni bölüm, devam et) / Should, F2 (coin-ödül, kişiselleştirilmiş öneri)**
**Davranış:** Kanonik push stratejisi: (1) takip edilen dizide yeni bölüm, (2) "kaldığın yerden devam et" hatırlatması, (3) coin/ödül hatırlatması (check-in kaçırma, yanmak üzere earned coin), (4) kişiselleştirilmiş dizi önerisi. İçerik ve zamanlama sunucu tarafındadır.
**Kabul kriterleri:**
- [ ] Her tür, `Ayarlar`'daki ilgili anahtara saygı duyar (PRF-03); kapalı türden push gelmez.
- [ ] Push payload'ında kampanya/tür kimliği vardır ve açılış attribution'ı `AnalyticsKit`'e yazılır.

#### NTF-03 — Sessiz saat + frekans limiti — **Must, F2**
**Davranış:** Sunucu politikası: kullanıcı yerel saatine göre sessiz saat penceresi (örn. 22:00–09:00, remote config) ve günlük/haftalık push frekans limiti. İstemci, saat dilimi bilgisini profil API'sine bildirir.
**Kabul kriterleri:**
- [ ] İstemci saat dilimi değişikliklerini (seyahat) günceller; sessiz saat yeni dilime göre uygulanır.

#### NTF-04 — BildirimMerkezi (uygulama içi) — **Must, F2**
**Davranış:** `BildirimMerkezi`: uygulama içi bildirim listesi (yeni bölüm, ödül, kampanya); okunmamış rozeti `Profil` girişinde.
**Kabul kriterleri:**
- [ ] Push'la gelen her kampanya kaydı burada da listelenir (push kaçıranlar için ikinci yüzey).
- [ ] Satıra dokunuş push ile aynı deep link rotasını izler.

#### NTF-05 — Live Activities — **Could, F3**
**Davranış:** Takip edilen dizinin yeni bölüm geri sayımı / günlük ödül hatırlatması için Live Activity. (Rakip gözlemi: ReelShort kilit ekranında kalıcı Live Activity kullanıyor — `10-arastirma-raporu.md`.)
**Kabul kriterleri:**
- [ ] Kullanıcı başına aynı anda en fazla 1 aktif Live Activity; `Ayarlar`'dan kapatılabilir.

---

### 2.12 Altyazı & çoklu dil (modüller: `PlayerKit`, `AppFoundation`)

#### LOC-01 — Altyazı render — **Must, F1**
**Davranış:** Altyazılar HLS içindeki WebVTT track'lerinden `AVPlayer`'ın yerleşik seçim mekanizmasıyla (`AVMediaSelectionGroup`) render edilir; stil `DesignSystem` standardına göre (alt üçte-bir, yarı saydam arka plan şeridi, Dynamic Type'a duyarlı taban boyut).
**Kabul kriterleri:**
- [ ] Altyazı, hız değişimlerinde (PLR-03/04) senkron kalır.
- [ ] Sistem "Kapalı Altyazı + SDH" erişilebilirlik tercihi açıksa altyazı varsayılan AÇIK başlar.
- [ ] Scrubber ve overlay, altyazı şeridiyle çakışmayacak şekilde konumlanır.

#### LOC-02 — Altyazı dil seçimi — **Must, F1**
**Davranış:** PLR-10 seçicisi bölüm manifest'indeki dilleri listeler; kullanıcının tercihi (`Ayarlar` → Dil → Altyazı dili) her bölümde otomatik uygulanır; bölümde o dil yoksa öncelik sırası: tercih → uygulama dili → EN → kapalı.
**Kabul kriterleri:**
- [ ] Fallback zinciri yukarıdaki sırayla işler ve seçilen fallback kullanıcıya çip ile belli edilir.

#### LOC-03 — Uygulama UI lokalizasyonu — **Must, F1 (EN) / Must, F2 (TR/ES/PT)**
**Davranış:** String catalog (xcstrings) tabanlı lokalizasyon; lansman EN, ikinci dalga TR/ES/PT (kanon §1 hedef pazar). Katalog metinleri (dizi adı/özet) sunucudan seçili içerik diliyle gelir.
**Kabul kriterleri:**
- [ ] Hard-coded kullanıcı-görünür string YOK (lint kuralı); tarih/sayı biçimleri locale'e uyar.
- [ ] F2 dillerinde ekran taşma denetimi (pseudo-localization testi) yapılmıştır.

---

### 2.13 Paylaşım & deep link (modüller: `AppFoundation`, `ShortSeriesApp` koordinatörleri)

#### SHR-01 — Paylaşım içeriği — **Must, F1**
**Davranış:** Paylaş eylemi (PLR-07/DTL-04) sistem share sheet'ine şunları verir: Universal Link (dizi ya da dizi+bölüm), kapak görseli, yerelleştirilmiş kısa metin ("Bunu izlemen lazım: {dizi}").
**Kabul kriterleri:**
- [ ] Link her zaman dizi düzeyine iner; bölüm parametresi varsa alıcıda o bölüm hedeflenir (kilit kuralları alıcının kendi entitlement'ına göre işler).
- [ ] Paylaşım metni ve linki A/B ile değiştirilebilir (remote config şablonu).

#### SHR-02 — Universal Links deep link rotaları — **Must, F1**
**Davranış:** Uygulama şu rotaları çözer: dizi (`/s/{seriesId}`), bölüm (`/s/{seriesId}/e/{episodeNumber}`), koleksiyon/kampanya (`/c/{collectionId}`), sekmeler (`/rewards`, `/store`). Push (NTF-01) ve banner (DSC-01) hedefleri aynı şemayı kullanır. Rota → Coordinator eşlemesi `02-ekran-haritasi-navigasyon.md`'de.
**Kabul kriterleri:**
- [ ] Soğuk açılışta deep link, Splash ön-yüklemesinden sonra hedef ekrana gider (feed'e uğramadan); sıcak açılışta mevcut yığının üstüne doğru rota push edilir.
- [ ] Bilinmeyen/bozuk rota sessizce Ana Sayfa'ya düşer ve telemetri yazar.
- [ ] Kilitli bölüm deep link'i: `DiziDetay` açılır + `UnlockSheet` gösterilir (doğrudan oynatma denenmez).
- [ ] Uygulama yüklü değilken link App Store'a düşer (standart Universal Link davranışı).

```swift
// AppFoundation — deep link rota sözleşmesi (iskelet)
enum DeepLinkRoute: Equatable, Sendable {
    case series(id: String)
    case episode(seriesId: String, episodeNumber: Int)
    case collection(id: String)
    case rewards            // OdulMerkezi
    case coinStore          // CoinMagazasi
}
```

#### SHR-03 — Deferred deep link / attribution — **Should, F2**
**Davranış:** Paid UA ağırlıklı kategoride (paylaşım + reklam tıklaması → kurulum → ilk açılışta hedef içerik) deferred deep link çözümü; ATT durumuna saygılı attribution (`08-analitik-deney.md`).
**Kabul kriterleri:**
- [ ] İlk açılışta deferred hedef varsa `Onboarding` SONRASI o içeriğe gidilir; onboarding atlanmaz.

---

### 2.14 Offline indirme — **F3** (modül: `LibraryKit` + `PlayerKit`)

#### DLD-01 — Bölüm indirme (`AVAssetDownloadTask`) — **Must (F3 kapsamı), F3**
**Davranış:** HLS segmentleri basit URL interception ile cache'lenemediğinden offline indirme `AVAssetDownloadTask` (ve `AVAssetDownloadURLSession`) ile yapılır (kanon §2 HLS cache notu). İndirme yalnız erişim hakkı olan bölümler için (ücretsiz, coin'le açılmış ya da VIP) başlatılabilir; kalite seçimi: standart (480p) / yüksek (720p).
**Kabul kriterleri:**
- [ ] İndirme arka planda sürer (background session); uygulama öldürülse de tamamlanır.
- [ ] Hücreselde indirme varsayılan kapalıdır (`Ayarlar` anahtarı).
- [ ] İndirme sırasında ilerleme `DiziDetay`/`BolumListesi` hücrelerinde görünür; duraklat/sürdür/iptal edilebilir.

#### DLD-02 — İndirilenler yönetimi (Listem 3. segment) — **Must (F3 kapsamı), F3**
**Kabul kriterleri:**
- [ ] `Listem` → İndirilenler: dizi altında gruplanmış bölümler, boyut bilgisi, tekil/toplu silme.
- [ ] Toplam indirme alanı `Ayarlar`'da görünür; cihaz alanı kritik seviyedeyse indirme başlatılamaz ve açıklayıcı hata gösterilir.

#### DLD-03 — Offline entitlement ve oynatma — **Must (F3 kapsamı), F3**
**Kabul kriterleri:**
- [ ] Offline oynatma FairPlay offline key (F2'de gelen DRM'in offline uzantısı) ile korunur; key süresi dolan içerik "yenilemek için çevrimiçi ol" durumuna düşer.
- [ ] VIP süresi bitmiş kullanıcının VIP'ken indirdiği kilitli bölümler çevrimiçi ilk kontrole kadar oynatılabilir; kontrol sonrasında kilit kuralı uygulanır.
- [ ] Offline izleme konumları ve analitik event'leri cihazda kuyruklanır, bağlantı gelince senkronlanır.

---

### 2.15 İçerik güvenliği & moderasyon (modüller: `ContentKit`, `AppFoundation`, `ProfileKit`)

Bağlam: İçerik AI üretim hattından gelir ve yayın öncesi insan onaylı kürasyon kapısından geçer (`00-genel-bakis.md`); yine de hatalı/rahatsız edici içerik olasılığı vardır ve App Review, kullanıcı tarafında raporlama + içeriği kaldırma mekanizması bekler. Bu bölüm bunun istemci yüzeyini tanımlar. **Etki notu:** `02-ekran-haritasi-navigasyon.md`'ye bildirme akışının ekran/rotası, `05-veri-modeli-api.md`'ye `POST /reports` ucu ve takedown sinyali, `09-yol-haritasi-tasklar.md`'ye ilgili task'lar eklenmelidir.

#### RPT-01 — Bölümü/diziyi bildir — **Must, F1**
**Davranış:** Player overlay'indeki aksiyon menüsünden ("Bildir") ve `DiziDetay` üst menüsünden bildirme akışı açılır: sebep listesi (örn. rahatsız edici içerik, hatalı/bozuk video, yanıltıcı başlık/kapak, telif şüphesi, diğer + serbest metin), gönderimde sunucuya rapor yazılır. Rapor bölüm ya da dizi düzeyinde olabilir. Akışa `Profil` > destek üzerinden de erişilir (`00-genel-bakis.md` taahhüdü).
**Kabul kriterleri:**
- [ ] Bildirme girişi hem player overlay'inden hem `DiziDetay`'dan en fazla 2 dokunuşla erişilebilir; sebep listesi remote'tan gelir (bilinmeyen sebep tipi = gizle).
- [ ] Gönderim sunucuya yazılır (bölüm/dizi kimliği, sebep, isteğe bağlı serbest metin, oturum bağlamı); başarıda "Bildirimin alındı" onayı gösterilir ve akış izlemeyi kesintiye uğratmaz.
- [ ] Aynı kullanıcı aynı içeriği tekrar bildirirse sunucu idempotent yanıt verir; istemci "daha önce bildirdin" durumunu gösterir.
- [ ] Misafir hesap da bildirebilir (giriş şartı yok).
**Edge case'ler:** Çevrimdışı/başarısız gönderim kuyruklanır ve bağlantı gelince işlenir (LIB-04 kalıbı); kalıcı hata durumunda kullanıcı bilgilendirilir.

#### RPT-02 — Uzaktan içerik kaldırma (takedown) davranışı — **Must, F1**
**Davranış:** Sunucu bir bölümü/diziyi yayından kaldırdığında (moderasyon kararı, telif, kalite): istemci içeriği feed'den, `Kesfet`/`Arama` sonuçlarından, `Listem` (Favoriler + Devam Et) yüzeylerinden ve disk cache'ten temizler. Dizi bazlı kill-switch remote config / feed metadata ile anında etkilidir ve uygulama güncellemesi gerektirmez.
**Kabul kriterleri:**
- [ ] Kaldırılan içeriğin imzalı URL/playback token isteği sunucuda reddedilir (UNL-06 kalıbı); istemci bu durumda oynatmayı durdurur ve "Bu içerik artık kullanılamıyor" durum kartı gösterir (crash/boş ekran yok).
- [ ] Feed'de sıradaki öğe kaldırılmışsa sessizce atlanır; `Listem`/`DiziDetay` yüzeylerinde kaldırılan içerik en geç bir sonraki tazelemede kaybolur.
- [ ] Disk video cache'indeki (ve F3'te indirilmiş) kopyalar ilk fırsatta silinir.
- [ ] Takedown'ın istemcide yakalandığı yüzey telemetriye yazılır.

#### RPT-03 — AI içerik şeffaflık etiketi — **Should, F1**
**Davranış:** İçeriğin AI-generated olduğu kullanıcıya şeffaf biçimde belirtilir: `DiziDetay` açıklama bölgesinde kalıcı etiket (örnek metin: "Bu dizi yapay zekâ ile üretilmiştir"; kesin metin ve gösterim yeri remote config'ten, lokalize). Player feed'i etiketle kirletilmez; ayrıntı isteyen kullanıcı `DiziDetay`'da görür. Etiket, App Review notlarındaki içerik kaynağı beyanıyla tutarlıdır (`00-genel-bakis.md`).
**Kabul kriterleri:**
- [ ] Etiketin metni ve gösterim yeri remote config ile yönetilir (politika değişikliğinde uygulama güncellemesi gerektirmez); etiket hiçbir konfigürasyonda tamamen kapatılamaz (mağaza/yasal uyum tabanı).
- [ ] Etiket tüm desteklenen dillerde lokalizedir (LOC-03 kuralları; hard-coded string yok).

---

## 3. Rakip parite matrisi

Gösterim: ✅ = var (doğrulanmış kaynak, bkz. `10-arastirma-raporu.md`); ◐ = raporlandı ama çapraz doğrulanmadı (tek/az kaynak); **?** = tespit edilemedi/bilinmiyor; ✖ = yok/kapsam dışı. ShortSeries sütununda faz etiketi hedefi gösterir. **Not:** Rakip fiyat ve limit ayrıntıları kaynaklar arasında tutarsızdır; tüm rakip fiyatları **lansman öncesi güncel App Store fiyatlarından doğrulanmalıdır.**

| Özellik | ReelShort | DramaBox | NetShort / DramaWave | ShortSeries |
|---|---|---|---|---|
| Dikey tam ekran bölüm feed'i (For You) | ✅ | ✅ | ✅ | **F1** (FEED-01) |
| Ücretsiz ilk bölümler → bölüm kilidi | ✅ (~ilk 10 dk ücretsiz) | ✅ (daha fazla ücretsiz bölüm ◐) | ◐ | **F1** (5–10 bölüm, API'den) |
| Coin ile bölüm açma | ✅ | ✅ | ◐ | **F1** (UNL-01/02) |
| Coin paketleri + bonus kademeleri | ✅ (kademe rakamları tutarsız) | ◐ | ◐ | **F1** ($0.99–$99.99, %0→%100 bonus) |
| İlk yükleme bonus teklifi | ◐ | ◐ | ? | **F1** (2x bonus, PAY-02) |
| VIP abonelik | ✅ (haftalık $5.99–$20 arası ÇELİŞKİLİ raporlar → aralık olarak ele al) | ✅ ($3.99 intro / $5.99 haftalık / $49.99 yıllık — doğrulanmış) | ◐ (DramaWave ~$19.90 haftalık/aylık + $9.99 tek seferlik — tek kaynak) | **F1** ($5.99 haftalık, intro $3.99; $14.99 aylık; $49.99 yıllık) |
| Rewarded ad ile kilit açma | ✅ (cap raporları çelişkili: oturum başına ~5 ↔ günde 20) | ◐ | ◐ | **F2** (günde 5–10 cap, remote config) |
| Günlük check-in (artan ödül) | ✅ (10–50 coin, streak) | ◐ | ◐ | **F1** (RWD-01) |
| Görev merkezi (coin karşılığı görevler) | ✅ (bildirim izni, paylaşım, streak) | ◐ | ? | **F1** (RWD-02) |
| Otomatik sonraki bölüm (binge/auto-play) | ◐ | ◐ | ? | **F1** (PLR-09) |
| Devam et / kaldığın yerden | ◐ | ◐ | ? | **F1** cihaz içi, **F2** cihazlar arası |
| Player jestleri (çift tap, hız) | ? | ◐ (double-tap raporlandı) | ? | **F1** (PLR-01…04) |
| Bölüm listesi + kilit fiyatı gösterimi | ✅ | ✅ | ◐ | **F1** (PLR-06, DTL-03) |
| Keşfet: raflar + Top listeleri | ✅ | ✅ | ◐ | **F1** (DSC-01/02) |
| Arama + otomatik tamamlama | ◐ | ◐ | ? | **F1** (DSC-03/04) |
| Çoklu dil altyazı | ◐ | ◐ (30+ dil raporlandı) | ✅ (DramaWave: multilingual subtitles — Sensor Tower) | **F1** (LOC-01/02) |
| Push bildirim (yeni bölüm, hatırlatma) | ✅ | ◐ | ◐ | **F1**/F2 (NTF-01/02/03) |
| Paylaşım + deep link | ◐ | ◐ | ? | **F1** (SHR-01/02) |
| Offline indirme | ? | ◐ (raporlar çapraz doğrulanamadı) | ? | **F3** (DLD-01…03) |
| Live Activities (kilit ekranı varlığı) | ◐ | ? | ? | **F3** (NTF-05) |
| Kişiselleştirilmiş öneri motoru | ◐ | ◐ (hybrid engine raporlandı) | ◐ | **F1** basit sinyaller, **F2** gelişmiş (DSC-06) |
| UGC / creator portal | ✖ | ◐ (creator portal raporlandı) | ? | ✖ (kapsam dışı, §4) |
| Yorumlar / sosyal etkileşim | ? | ? | ? | ✖ F1–F2; F3 sonunda değerlendirme (§4) |

**Parite okuması:** F1 sonunda ShortSeries, doğrulanmış rakip çekirdeğinin (feed + kilit + coin + VIP + check-in/görev + keşfet/arama + push + paylaşım) tamamını karşılar; F2 rewarded ads, DRM ve senkronla pariteyi tamamlar; F3 offline indirme ve Live Activities ile doğrulanamamış-ama-raporlanmış rakip yüzeylerini kapatır. Bu, kanonun "benchmark uygulamalarla neredeyse %100 özellik paritesi" hedefiyle uyumludur.

---

## 4. Bilinçli kapsam dışı bırakılanlar (Won't)

| Konu | Karar | Gerekçe |
|---|---|---|
| Kullanıcı içerik yükleme (UGC) / creator portal | **Won't (kalıcı, istemci için)** | Kanon §1: iOS istemcisi içerik ÜRETMEZ, TÜKETİR. İçerik AI üretim hattından (ayrı proje) backend + CDN ile gelir. UGC; moderasyon, telif ve App Store inceleme yükü getirir, kuzey yıldızındaki üç hedefin hiçbirine hizmet etmez. |
| Yorumlar ve sosyal etkileşim (beğeni sayacı, takip, DM) | **Won't F1–F2; F3 sonunda değerlendirme** | Moderasyon altyapısı (UGC metin!) ve App Store 1.2 gereklilikleri MVP takvimini riske atar; kategori liderlerinde de çekirdek döngünün parçası olduğuna dair doğrulanmış veri yok. Binge + retention döngüsü yorumsuz çalışır. |
| Android / iPad / landscape | **Won't (bu proje kapsamı)** | Kanon §2: iOS 17+, iPhone-only, portrait-locked. İçerik dikey formatta üretiliyor; içerik/CDN bitrate merdiveni portrait üretilir (240p→1080p dikey, kanon §2) — landscape desteği yalnız istemci işi değildir, içerik üretim/CDN hattında ayrı karar gerektirir. |
| PiP (Picture-in-Picture) + arka plan oynatma | **Won't (Faz 1); F2 kapısında yeniden değerlendirme** | Portrait-locked mikro-drama deneyiminde PiP, retention döngüsünü (tam ekran + overlay + UnlockSheet) baltalar ve kilitli bölüm kesişimini karmaşıklaştırır; arka planda ses devam ettirme de aynı gerekçeyle kapalıdır (background mode yetkisi binary'ye eklenmez; FEED-09, PLR-11). Teknik ayrıntı ve kabul kriterleri: `04-player-engine.md` §11. |
| Canlı yayın / gerçek zamanlı içerik | **Won't** | Kategori VOD mikro-dizidir; canlı yayın tamamen farklı player, altyapı ve moderasyon problemi. |
| Chromecast / AirPlay / harici ekran | **Won't F1–F2** | Dikey, telefonda-tek-kişilik tüketim formatı; DRM/imzalı URL akışını karmaşıklaştırır. Talep verisi gelirse F3+ değerlendirilir. |
| Uygulama içi coin transferi / hediye etme | **Won't** | Fraud yüzeyini büyütür (kanon §5 fraud kontrolleri); coin kapalı ekonomidir, kullanıcılar arası transfer App Store ve muhasebe riskidir. |
| Web / TV istemcileri | **Won't (bu proje kapsamı)** | Proje kapsamı iOS istemcisidir (kanon §1). |
| Zorunlu reklam formatları (interstitial, pre-roll) | **Won't** | Kuzey yıldızı #1 kesintisiz izleme deneyimi; reklam yalnız kullanıcı-iradeli rewarded formatta (F2) var. |
| İstemci taraflı fiyat/kilit kuralı | **Won't** | Tüm `unlockPrice`, ücretsiz bölüm sayısı, cap ve ödül değerleri API/remote config'ten gelir (UNL-02, RWD-01); istemcide iş kuralı sabitlenmez. |

Bu envanterdeki her `ALAN-XX` kimliği `09-yol-haritasi-tasklar.md`'de task'lara kırılır; player davranışlarının teknik ayrıntısı `04-player-engine.md`'de, ekonomi ayrıntısı `06-monetizasyon.md`'de, event eşlemesi `08-analitik-deney.md`'dedir. Rakip iddialarının kaynak ve doğrulama durumu için `10-arastirma-raporu.md`'ye bakınız.
