# Manuel Prep Bekleyen Kalemler (F2/F3)

**Amaç:** Bu dosya, istemci tarafı KODU hazır/soyutlanmış ama gerçek entegrasyonu için
**dışarıdan manuel hazırlık** (hesap, SDK, sertifika, sunucu ucu, çeviri) gerektiren
kalemleri izler. Kod-içsel iş bittiğinde bu kalemler burada beklerki; prep sağlanınca
her biri mevcut **injectable port**'un arkasına ince bir adaptörle takılır (desen
fraud/win-back/rewarded-ad/hesap-bağlama'da kanıtlandı).

Durum tarihi: 2026-07-20 · Referans: `09-yol-haritasi-tasklar.md`

---

## 1. AdMob rewarded ads — GERÇEK SDK (SS-113)
- **Client durumu:** ✅ GERÇEK ENTEGRASYON TAMAM (test ID'leriyle uçtan uca çalışır). GoogleMobileAds
  SDK 11.13.0 App target'ında (`project.yml`); `App/DI/Adapters/RealRewardedAdProvider.swift`
  gerçek `GADRewardedAd` adaptörü (`RewardedAdProviding` conformance — preload/present +
  `GADFullScreenContentDelegate` + `userDidEarnRewardHandler` → CheckedContinuation →
  `AdWatchOutcome`); `AdMobConfiguration.start()` (GADMobileAds init, `AppDelegate.didFinishLaunching`);
  `Info.plist` GADApplicationIdentifier + 44 SKAdNetwork + NSUserTrackingUsageDescription. Wiring
  canlı (`AppComposition.rewardedAdProvider = RealRewardedAdProvider()`, tek instance); **mock testte
  kalır** (`RewardedAdWiringTests` kendi stub'ıyla). Server-otoriter korundu (istemci ödül vermez,
  `proofPayload` boş, nonce SSV korelasyonu), VIP reklamsız (preload/availability/**watchAdToUnlock**
  hepsi VIP kapısı). Review 4 bug düzeltildi: reentrancy guard, **topmost-VC sunum** (UnlockSheet modal
  → taban root'tan present `.failed` verirdi), preload in-flight guard, watchAdToUnlock VIP gate.
- **Sağlanan prep:** AdMob **Yayıncı Kimliği** `pub-1147476807575834` (2026-07-20).
- **Şu an TEST ID kullanılıyor** (release öncesi değişecek — kod `AdMobConfiguration` + Info.plist tek
  yerde): App ID `ca-app-pub-3940256099942544~1458002511`, rewarded unit
  `ca-app-pub-3940256099942544/1712485313`.
- **HÂLÂ gereken (release öncesi manuel — Yayıncı Kimliği tek başına yetmez):**
  - **Gerçek App ID** — `ca-app-pub-1147476807575834~XXXXXXXXXX` (AdMob konsol → Uygulamalar →
    App settings). `AdMobConfiguration.applicationIdentifier` + `Info.plist GADApplicationIdentifier`
    (İKİSİ EŞLEŞMELİ) test App ID'yle değişecek.
  - **Gerçek Rewarded Ad Unit ID** — `ca-app-pub-1147476807575834/XXXXXXXXXX` →
    `AdMobConfiguration.rewardedAdUnitID`.
  - Backend: **SSV** (Server-Side Verification) ucu — Google S2S imzalı callback'i `custom_data`
    (=customRewardString=nonce) ile `/rewards/ad-unlock` POST'undaki nonce'a korele edip unlock yazar.
  - `RealRewardedAdProvider.userIdentifier()` şu an cihaz `identifierForVendor` — SS-021 backend
    userId gelince gerçek kullanıcı kimliğiyle değişecek (SSV `user_id` / kullanıcı-bazlı cap).

## 2. Google/e-posta hesap bağlama — GERÇEK SDK (SS-132)
- **Client durumu:** ✅ HAZIR. ProfileKit provider-agnostic linking (`LinkCredential` .apple/
  .google/.email; `GoogleSignInProviding`/`EmailLinkProviding` portları + mock). Merge/conflict/
  **sıfır bakiye-ilerleme kaybı** akışı + hesap-değişimi store-reset (§575) çalışıyor. Apple canlı.
- **Gereken manuel prep:**
  - Google Cloud Console → **OAuth client-ID** (iOS) + reversed-client-ID URL scheme.
  - GoogleSignIn SDK (SPM: `GoogleSignIn-iOS`) `project.yml`'ye eklenir.
  - E-posta: backend e-posta/OTP link ucu (varsa) — `/auth/link` provider="email" zaten
    sağlayıcı-bağımsız.
- **Prep gelince yapılacak:** `App/DI/Adapters/AccountServiceAdapters.swift` (veya yeni dosya)
  içinde gerçek `GIDSignIn` adaptörü (`GoogleSignInProviding`) + `makeHesapBaglamaModel`
  enjeksiyonu `MockGoogleSignInProvider` yerine gerçeğiyle.

## 3. FairPlay DRM (SS-053)
- **Client durumu:** 🟡 KISMİ. ContentKit `PlaybackAuthorization.drm` alanı (Faz 2, API
  değişikliği olmadan açılır — 05 §8.2/§4.4) HAZIR. `AVContentKeySession` istemci akışı +
  lisans-istek/hata-fallback YAZILMADI (gerçek sertifika/sunucu olmadan test-değeri düşük).
- **Gereken manuel prep:**
  - Apple **FairPlay Streaming sertifikası** (FPS SDK / deployment package, Apple'dan talep).
  - Backend **lisans (KSM) sunucusu** ucu.
  - DRM'li mock içerik (test için).
- **Prep gelince yapılacak:** PlayerKit `AVContentKeySession` + `AVContentKeySessionDelegate`
  (anahtar ön-alımı prefetch ile uyumlu, SS-053) + lisans-istek gateway portu + hata event'i.
  İstenirse önce **mock lisans-sunucuyla client-scaffold** kurulabilir (spekülatif; gerçek
  sertifika gelince yeniden şekillenir).

## 4. TR/ES/PT lokalizasyon (SS-163–166)
- **Client durumu:** ⚠️ DÜZELTME (2026-08-28, kod-doğrulandı): **SS-160 String Catalog altyapısı commit'li kodda YOK.**
  `.xcstrings`/`.strings`/`.stringsdict` hiçbiri, project.yml'de `knownRegions`/`developmentRegion`/localization
  bloğu yok. UI `LocalizedStringKey` kullanıyor (doğru desen) ama katalog+knownRegions olmadan hiçbir dile
  lokalize edilemez. Önceki "✅ Altyapı HAZIR" iddiası YANLIŞTI. **SS-160 (F0 task) gerçekten yapılmalı**:
  `.xcstrings` katalog + `knownRegions`(+`developmentRegion`) + literal→key çıkarımı + base-dil (EN vs mevcut TR
  literaller) kararı + pseudo-locale build. Büyük + base-dil kararı → docs/RAKIP-GAP-ANALIZI.md'de kullanıcı-kararı.
- **Gereken manuel prep (SÜREÇ, kod değil — SS-160 altyapısı KURULDUKTAN sonra):**
  - SS-163: TMS/çeviri sağlayıcı seçimi + terim sözlüğü (coin/unlock/VIP/check-in...).
  - SS-164: string freeze ritmi + eksik-çeviri CI kontrolü.
  - SS-165: native reviewer dil QA + cihazda taşma turu.
  - SS-166: ASC metadata + ekran görüntüleri + IAP display name lokalizasyonu.

## 5. Offline İndirilenler (SS-124, F3)
- FairPlay **persistent key** (SS-053'e bağlı) + `AVAssetDownloadTask` motoru + İndirilenler UI.
  SS-053 gerçek DRM olmadan başlanamaz. F3 kapsamı.

## 7. RWD-07 davet-arkadaş (referral) — canlı endpoint + ürün/ekonomi kararı (2026-08-30)
- **Client durumu:** ✅ İstemci soyutlaması TAMAM (commit'li, flag-KAPALI): RewardsKit `ReferralGateway`
  portu + value tipleri (`ReferralStatus`/`ReferralRedeemOutcome`/`ReferralConflict`) + `MockReferralGateway`
  + `ReferralModel` (server-otoriter redeem, optimistik-kredi-YOK, bayat-akış coin-kaybı guard'ı) + tam
  unit test süiti (13 model + 3 kart testi) + `DavetMerkeziView` + OdulMerkezi giriş kartı + App
  `APIReferralGateway` adaptörü + composition + coordinator/share wiring + analitik (registry + docs/08).
  `rewards.referral_card_enabled` VARSAYILAN KAPALI → yapı ships, kullanıcıya gizli (SS-113 rewarded-ad
  kartı precedent'i). Flag-kapalı yolda `MockReferralGateway` bağlıdır (canlı çağrı YOK).
- **Gereken manuel prep (ürün/sunucu kararı — otonom implement EDİLMEZ):**
  1. **Ürün/ekonomi kararı + KANON ratifikasyonu:** RWD-07 kapsam onayı, `01-ozellik-envanteri.md` §4
     "Won't (gifting)" ile bitişikliğin çözümü (referral ≠ gifting ama fraud gerekçesi ortak), kredi kuralı
     (davet-eden nitelikli-davet başına vs gelen tek-sefer), `rewardPerReferral`/`maxReferrals` remote-config.
  2. **Canlı `GET /rewards/referral` + `POST /rewards/referral/redeem`** server sözleşmesi (05 §4.7'ye eklenen
     MOCK sözleşme doğruluk kaynağı): idempotency store ≥24s, çakışma HTTP kodları / `error.code`, attribution
     + fraud velocity (`X-Earn-Velocity-Flag`, self/device/velocity anti-fraud).
  3. **AASA `/r/{code}` yayını + gelen davet linki çözümü** (`DiscoverKit.DeepLinkRoute`'a referral case;
     şu an yalnız giden link `DeepLinkFactory.referralURL` fallback'i var — server `inviteURL`'i tercih edilir).
  4. **`rewards.referral_card_enabled` flag'inin canlı açılması** (server + doc + attribution hazır olunca).
- **Not (adaptör sınırı):** APIClient yalnız HTTP `status` yüzdürür, `error.code` yüzdürmez → 422 kendine-davet
  ↔ idempotency-mismatch ayrımı belirsiz; canlı entegrasyonda endpoint çakışma-başına ayrık HTTP kodu döner.

## 6. Audit-ertelenen: sunucu-sözleşmesi / altyapı bekleyen (2026-08-28)
- **`/rewards/ad-unlock` response `remainingToday` (bug 78, App/DI/Adapters/RewardedAdAdapters.swift):**
  İstemci `AdUnlockResponseWire.remainingToday: Int?` opsiyonel decode eder (yoksa nil → "Bugün N/M
  kaldı" sayacı render edilmez). KANON §4.7 (satır 1261) response zarfını "Faz 2 tasarımında
  netleşecek" der — DONMAMIŞ. **Prep gelince:** backend response'ta alanın kesin ADI/KONUMU
  (top-level mi, cap-state objesi içinde mi) doğrulanınca wire eşlemesi kesinleştirilir; sözleşme
  donunca `Int?` → zorunlu yapılabilir.
- **Banner clock-skew server-time (bug 96, ContentKit/Models/BannerCollection.swift):**
  `Banner.isActive(at date: Date = .now)` zaten INJECTABLE (server-düzeltmeli saat threadlenebilir).
  Eksik: server-time senkronizasyon altyapısı (API `Date` header'ından offset takibi). **Prep/enhancement
  gelince:** APIClient response `Date` header'ından cihaz-saat offset'i hesaplayan bir `ServerClock`
  portu + Kesfet render'ında `isActive(at: serverClock.now)`. LOW/kozmetik; cihaz saati pragmatik interim.

### AppFoundation auth bug-hunt — ertelenen 2 kalem (2026-08-30)
Auth/session bug-hunt'ın 9 bulgusundan 7'si düzeltildi (4 commit); 2'si düşük-değer/atomiklik-doğası
gereği ertelendi:
- **linkSession snapshot/token ayrışması (finding 5, MEDIUM):** 3 Keychain yazması (refresh/access/
  snapshot) atomik değil. Torn-write TOKEN sırası (refresh-first) DÜZELTİLDİ (saatli bomba engellendi);
  ama snapshot en son + best-effort yazıldığından, refresh+access başarılı olup snapshot yazması koparsa
  relaunch'ta "guest snapshot + linked token" ayrışması (UI misafir gösterir ama istekler linked) kalır.
  Keychain transaction olmadığı için 3-yazma tam atomiklik imkânsız; **kurtarılabilir UI/kimlik uyuşmazlığı**
  (server hesap sağlam, re-login düzeltir), güvenlik açığı/veri kaybı DEĞİL. Prep gelince: SecureStore'a
  atomik çok-anahtar-yazma primitifi (tek SecItem update / staging+swap) → linkSession o primitifi kullanır.
- **handleRefreshFailure redundant Keychain re-read (finding 225, LOW):** Başarılı misafir re-bootstrap
  sonrası access token'ı bellekteki `response.accessToken` yerine Keychain'den `try?` ile yeniden okuyor;
  o tek okuma geçici glitch'lerse uçuştaki istek gereksiz `sessionExpired` alır (sonraki istek self-heal).
  Benign/self-healing; iyileştirme: `singleFlightGuestBootstrap` bellekteki taze access'i döndürsün
  (Keychain re-read yerine). Değer düşük, ertelendi.

### PlayerKit bug-hunt — ertelenen 1 kalem (2026-08-30)
PlayerKit engine/pool/feed bug-hunt'ının 7 bulgusundan 6'sı düzeltildi (3 commit: warm-reuse fence
HIGH+MEDIUM, recovery-intent MEDIUM×2, settle snapshot-kayması MEDIUM×2); 1'i ertelendi:
- **Başarısız prefetch "completed warmup" sayılıyor (LOW) → DÜZELTİLDİ (e8d9ec7):** `warm`/`prepareNext`
  geçici authorize hatasını (5xx/timeout) yutup normal dönüyor, `taskCompleted` onu `completedWarmups`'a
  ekliyordu → bölüm pencere-içi kaldıkça bir daha WARM EDİLMİYOR (cold-start spinner) + telemetri over-count.
  Fix: `EpisodeWarming.warm` + `FeedPlaybackPooling.prepareNext` Void→Bool (başarı/kilitli true, geçici
  hata/iptal false); completedWarmups + recordWarmupCompleted YALNIZ true'da. `prepareNext @discardableResult`
  (mevcut çağıranlar korunur). TDD: geciciHataAlanWarmPencereIciYenidenDenenir (revert-verify) +
  basariliWarmYenidenDenenmez. 271 PlayerKit testi yeşil.

### LibraryKit/ProfileKit bug-hunt — ertelenen 2 kalem (2026-08-30)
Kütüphane (favoriler/devam-et) + Profil bug-hunt'ının 5 bulgusundan 3'ü düzeltildi (3 commit:
compensatingDeletes cross-account leak MEDIUM, loadContinue generation-guard MEDIUM, ProfilModel
sessionExpired-çıkış cüzdan-restore MEDIUM); 2'si düşük-değer/self-healing doğası gereği ertelendi:
- **WatchHistoryStore.mergeServerProgress synced-newer LWW boşluğu (WatchHistoryStore.swift:31, LOW) →
  DÜZELTİLDİ:** merge guard'ı yalnız pendingUpload yerel kaydı koruyordu; synced yerel kayıt server
  batch'inden DAHA YENİ ise (bayat/out-of-order response) eski server kaydı yeni synced'i EZİYORDU. Fix:
  guard syncState-BAĞIMSIZ `existing.watchedAt > record.watchedAt` (pending + synced korunur; yalnız
  synced-newer case değişir); dead `isNewerLocalPending` kaldırıldı. RED→GREEN, 313 AppFoundation test yeşil.
- **FavoritesService kalıcı-red rollback yok (FavoritesService.swift:202/223, LOW):** `syncAdd`/`syncRemove`
  offline-DIŞI tüm hataları tek `catch` ile `.skipped` sayar → kayıt `pendingAdd`/`pendingRemove` kalır ve
  HER sync turunda süresiz retry edilir. Sunucu KALICI reddederse (4xx: seri yok/403/422) iyimser yerel
  favori geri ALINMAZ → istemci "favorili" gösterirken sunucu asla kabul etmez (kendini düzeltmeyen
  local/server ayrışması). Pratikte nadir (UI yalnız var olan katalog öğesini favoriletir) + retry sync-başı
  sınırlı (hot-loop değil). **Fix:** AppError durum-kodu sınıflandırması (kalıcı 4xx ↔ geçici 5xx/timeout)
  + kalıcı redde iyimser yerel yazmayı rollback (veya terminal-failed işaretle + kullanıcıya yüzey).
  Hata-sınıflandırma altyapısı + ürün kararı (rollback mı hata-göster mi) gerektirir → ertelendi.

### DiscoverKit bug-hunt — ertelenen 1 kalem (2026-08-30)
DiscoverKit (Arama/DiziDetay/Kesfet/DeepLink) adversarial bug-hunt'ının 4 CONFIRMED bulgusundan 3'ü
düzeltildi (2 commit: DiziDetay CTA hedef-sayfa paywall-bypass MEDIUM + sayfalama dedup MEDIUM;
BolumListesi scheduled-bölüm MEDIUM); 1'i veri-modeli sınırı gereği ertelendi:
- **DiziDetay cellState isWatched ileri-atlamada yanlış (DiziDetayModel.swift:175, LOW):** `isWatched`
  yalnız `episode.index < ctaTarget.episodeNumber` ile türetilir → kullanıcı ileri atladığında (ör.
  deep-link'le bölüm 30'u izleyip 1-29'u atlamak) izlenmemiş erken bölümler yanlışça 'izlendi' (soluk+tik)
  gösterilir. Kök: `WatchHistoryReading` portu YALNIZ `latestProgress(forSeries:)` (tek en-güncel kayıt)
  sunar — per-bölüm izlenmiş-küme YOK; sıralı-izleme varsayımı (kısa-drama common case) dışında doğru
  türetilemez. **Fix:** portu (+ repository + backend) izlenmiş-bölüm kümesi dönecek şekilde genişlet
  (`watchedEpisodeIDs(forSeries:)`) → cellState kümeyle türetsin. Port/katman genişletmesi gerektirir,
  değer düşük (kozmetik soluk+tik), izole değil → ayrı pass'e bırakıldı.

### RewardsKit bug-hunt — ertelenen 3 kalem (2026-08-30)
RewardsKit (CheckIn/OdulMerkezi/Tasks) adversarial bug-hunt'ının 9 kept bulgusundan 3'ü düzeltildi
(2 commit: check-in refresh generation-guard MEDIUM + claim lastSeen-persist LOW; reconcileClaimed
günlük-reset unpin MEDIUM); 3'ü App-wiring/port-versiyonlama gerektirdiği için ertelendi:
- **OdulMerkeziModel hesap-değişiminde reset yok (OdulMerkeziModel.swift:79, MEDIUM CONFIRMED):** model
  TabCoordinator ile bir kez kurulup uygulama ömrü boyunca yaşar; kimlik/generation guard'ı ve reset yolu
  YOK. `claimedTaskIDs` (ve `hasLoaded` gate'i nedeniyle bayat `coinBalance`) hesap/oturum değişiminde
  önceki kimlikten TAŞINIR → yeni hesabın aynı-id görevleri çapraz-hesap `.claimed` sabitlenir (claim
  edilemez); bakiye başlığı akış-replay'i gelene dek önceki hesabınkini gösterir. **Fix:** App
  account-switch koordinatörü modeli yeniden yaratsın VEYA `resetForAccountSwitch()` (FavoritesService
  deseni: claimedTaskIDs/awaitedBalance/checkInState/hasLoaded temizle) wiring'le çağrılsın. App-katmanı
  wiring gerektirir → ertelendi. İlgili: [[shortseries-project]] SS-132/§575 cross-account deseni.
- **applyBalance `>= awaited` guard'ı MEŞRU bakiye DÜŞÜŞÜNÜ yutar (OdulMerkeziModel.swift:257, MEDIUM
  PLAUSIBLE):** awaitedBalance (claim değeri) set iken, gelen bir bakiye DÜŞÜŞÜ (harcama/debit veya
  hesap-değişimi→daha düşük) `guard balance >= awaited` ile yutulur; awaited HİÇ temizlenmez (yalnız
  >= değer temizler) → başlık bayat-YÜKSEK değerde DONAR. Exact-match→>= audit fix'i donmayı azalttı ama
  meşru debit'i açığa çıkardı. **Fix:** value-heuristic yerine cüzdan akışına monoton VERSİYON/sequence
  eklenip applyBalance yalnız STRICTLY-NEWER sürümü uygulasın (RewardsWalletReading + WalletStore port
  değişimi) → bayat düşük SEQUENCE'e göre ayrılır, meşru düşük uygulanır. Port versiyonlama gerektirir → ertelendi.
- **claim/applyAuthoritativeBalance epoch guard yok (OdulMerkeziModel.swift:267/289, MEDIUM/LOW PLAUSIBLE):**
  claimToday/claimTask `await claim()` ÖNCESİ epoch yakalamaz, SONRASINDA apply-öncesi doğrulamaz →
  uçuştaki claim yanıtı bir bağlam/hesap değişiminden sonra uygulanınca cross-account/bayat kredi; ayrıca
  eşzamanlı iki claim'de geç dönen DAHA ESKİ bakiye anlık-görüntüsü yeniyi ezebilir. Yukarıdaki reset
  (§hesap-değişimi) + akış-versiyonlama ile AYNI altyapıyı paylaşır → o iki fix'le birlikte ele alınacak.
  (Not: todayReward computed var'ının schedule fallback'i [OdulMerkeziModel.swift:159, LOW] → **DÜZELTİLDİ
  (b523b27):** paylaşılan CheckInCycle.todayReward(for:) — buton etiketi + takvim bugün hücresi tek kaynak.)

### ContentKit bug-hunt — ertelenen 1 kalem (2026-08-30)
ContentKit (Wire decode/Models/API) adversarial bug-hunt'ının 3 kept bulgusundan 2'si düzeltildi
(2 commit: SeriesWire genres/tags lossy MEDIUM + boş-string nextCursor normalize LOW); 1'i cross-package
(AppFoundation APIClient) olduğu için ertelendi:
- **200 + boş gövde → sessiz boş son-sayfa (PageWire.swift:14 / AppFoundation APIClient, LOW):** PageWire
  ve DiscoverWire TÜM alanları opsiyonel/lossy olduğundan `{}`'dan ve BOŞ gövdeden başarıyla decode olur.
  APIClient.performOnce boş-gövde kısa-devresi (`data.isEmpty` → `decodeEmptyBody(as:)` → `{}` fallback)
  204 uçları için tasarlandı ama içerik uçlarının tümü-opsiyonel wire'larını da yakalar: bir CDN/proxy
  `/feed` veya `/discover`'ın N. sayfasına 200 + 0-bayt (truncation/bozuk-cache) dönerse → Page(items:[],
  nextCursor:nil) → isLastPage=true → sayfalama SESSİZCE durur (yarım feed "bitti" sanılır) / Keşfet
  sessizce boşalır; hata/retry YOK. Self-healing (sonraki fetch düzeltir), crash/para/güvenlik yok → LOW.
  **Fix:** decodeEmptyBody yalnız GERÇEKTEN gövdesiz uçlar (EmptyResponse) için geçerli olmalı; içerik
  Response tipleri için 200 + boş gövde bir decode HATASI sayılmalı (retry/hata yüzeyi). AppFoundation
  APIClient (cross-package, shared infra) değişimi gerektirir → ayrı pass'e bırakıldı.

### AnalyticsKit bug-hunt — ertelenen 2 kalem (2026-08-30)
AnalyticsKit (Experiment assignment/override/exposure) adversarial bug-hunt'ının 5 kept bulgusundan 3'ü
düzeltildi (2 commit: variant-seçimi trafik-bağımsız HIGH + negatif-weight clamp MEDIUM; ab_variants
format break→continue LOW); 2'si App-wiring/spec-config olduğu için ertelendi:
- **makeExperimentClient previouslyExposed beslenmiyor (LOW) → DÜZELTİLDİ (c36ddb2):** ExperimentClient
  `previouslyExposed` + `exposedExperimentKeys` zaten hazır+test-kaplıydı; eksik App-wiring'di → her oturum
  `first_exposure=true` düşüp DÖNEN kullanıcı KPI'sini şişiriyordu. Fix (LastSeenStreakStore deseni):
  `UserDefaultsExposedExperimentsStore` (load/merge, deviceID-scoped tek anahtar) → makeConfigGraph launch'ta
  `load()`→previouslyExposed tohumlar, scenePhase `.background` `AppComposition.persistExposedExperiments()`
  birikimli merge eder. TDD: `ExposedExperimentsPersistenceTests` (store round-trip + cross-session dönen-kullanıcı
  first_exposure=false). 2 App testi lokal yeşil.
- **Duplicate variant id tespit edilmez (Experiment.swift:49, LOW PLAUSIBLE) → DÜZELTİLDİ (f254bea):**
  aynı id'li iki variant → `variant(withID:)` `first`'ü döner ama hash bucketing SONRAKİ duplike'yi
  seçebilir → aynı raporlanan id FARKLI payload'a eşlenirdi. Fix: Experiment yapımda `dedupedByID` (İLK'i
  tut) — designated + custom decode init (remote config decode yolu dahil).

### App-integration bug-hunt — ertelenen kalemler (2026-08-30)
App katmanı (coordinators/adapters/analytics-wiring) adversarial bug-hunt'ının 10 kept bulgusundan 3'ü
düzeltildi (3 commit: ab_exposure registry crash HIGH; rewarded-preload kill-switch LOW; deeplink_opened
decorated LOW); kalanlar App-mimari (session-observation/reset altyapısı) veya küçük navigasyon olduğu için
ertelendi. **App CI'da DEĞİL — hepsi lokal AppTests + build ile doğrulanır.**
- **HESAP-DEĞİŞİMİNDE UZUN-ÖMÜRLÜ UI STATE RESET (cluster, MEDIUM) — TAM DÜZELTİLDİ (rewards 3f9bb17+5b60be1
  +accountEpoch fence; feed a26ea83-sonrası):** App'te session-state gözlemcisi yoktu; coordinator/model'ler
  app-init'te bir kez kurulup switch'te yeniden yaratılmıyordu → önceki hesabın state'i sızıyordu. **ÇÖZÜM
  (her iki koordinatör de always-alive `session.stateUpdates` gözlemci, userID FARKLI hesaba geçince reset):**
  (b+c) **RewardsCoordinator** → `OdulMerkeziModel.resetForAccountSwitch()` (checkInState/claimedTaskIDs/
  coinBalance/awaitedBalance/catalog + generation bump + kalıcı lastSeenStreak clear; uçuştaki claim/load/
  refreshTasks yolları `accountEpoch` ile fence'lenir → in-flight yanıt yeni hesaba yazılmaz). (a) **HomeCoordinator**
  → feed reset (seedGeneration bump + feedState=FeedState() [`.unlocked` işaretleri temizlenir] + feedEntry/
  pendingPlayback/activeEpisodeID + feedMountToken remount). link (guest→aynı userID §3.3)/session-death/re-auth
  reset ETMEZ. Testler: testDifferentAccountSwitchResetsModelButSameUserIDDoesNot + claimInFlightDuringAccount
  SwitchDoesNotWriteOldAccountData + testDifferentAccountSwitchRemountsFeedButSameUserIDDoesNot. (Not: PlayerPool
  warm-slot'ları account-agnostik kalır ama re-seed sonrası B'nin feed'inde A'nın bölümü olmadığından leak değil.)
- **Deep-link `search?q=` Arama açıkken query düşürülür (DiscoverCoordinator.swift:52, LOW CONFIRMED):** showSearch
  `guard searchStackDepth == nil else { return }` — Arama zaten stack'teyse yeni universal-link query'si sessizce
  atlanır, ön-doldurma uygulanmaz. **Fix:** Arama açık+query doluysa mevcut frame'i pop+repush VEYA AramaModel'e forward.
- **`.series` deep-link idempotent değil (DiscoverCoordinator.swift:41, LOW):** showDetail `path.append` (NavigationPath,
  peek yok) → aynı diziye ikinci push özdeş DiziDetay çoğaltır. **Fix:** son diziDetay seriesID marker'ı (search deseni),
  özdeşse tekrar push etme.
- **Standalone VIP aktivasyonu feed'i reaktive etmez (WalletFlowCoordinator.swift:159, LOW):** vipSubscriptionDidActivate
  yalnız vipModel=nil yapar; feed reaktivasyon kancası (onEpisodeUnlocked) bölüm-bazlı, VIP-hepsini-aç için çağrılmaz
  → VIP sonrası feed'deki kilitli bölümler `.locked` kalır. **Fix:** onVIPActivated → feed'i reaktive et (feedState-reset task'ıyla ilişkili).

### Oturum-değişikliği self-review — ertelenen 2 LOW (2026-08-30)
Bu oturumun 26 fix diff'inin adversarial self-review'ı 7 bulgu üretti: 5'i düzeltildi (cross-account
accountEpoch fence HIGH; DiziDetay dead-button MEDIUM + ensureEpisodeLoaded bound LOW; ayrıca load/
refreshTasks/runRefresh fence #3/#4 aynı accountEpoch commit'inde). 2'si dar-edge/karmaşıklık gereği ertelendi:
- **ProfilModel sessionExpired-çıkış restore, daha taze observeWallet emission'ını clobber edebilir
  (ProfilModel.swift:~124, LOW):** `wallet = await walletSummary.currentSummary()` await'i sırasında
  observeWallet daha taze bir emission (E) uygular, sonra restore'un currentSummary() okuması (E'den eski
  olabilir) E'yi ezer (review #12 clobber sınıfı). Dar yarış: currentSummary() cache'i E store'undan ÖNCE
  okur AMA atama observeWallet'ten SONRA olur. Pratikte currentSummary() otoriter cache → çoğu interleave'de
  ≥ E. **Fix:** wallet-emission sayacı/generation → restore yalnız daha taze emission gelmediyse uygular.
  Değer düşük + dar → ertelendi.
- **reconcileClaimed unpin, Fix 4 kalıcı-pin garantisini read-replica edge'inde zayıflatır
  (OdulMerkeziModel+Tasks.swift:~133, LOW):** server bir görevi ÖNCE .claimed SONRA tekrar .claimable
  dönerse (read-your-writes ihlali, read-replica), unpin sonrası görev .claimable'a döner. Değişim, daha
  impactful günlük-reset bug'ını (unbounded pin) kapatmak için bu nadir edge'i kabul etti (net-pozitif).
  **Fix (istenirse):** claimedTaskIDs'i periyot/gün-anahtarıyla scope'la (server .claimed→.claimable
  regresyonuna karşı dayanıklı). Nadir server-inconsistency → ertelendi.

### Oturum-değişikliği self-review-2 — accountEpoch fence + feed reset (2026-08-30, HEPSİ DÜZELTİLDİ)
Bir önceki self-review SONRASI eklenen YENİ kompleks concurrency değişikliklerinin (accountEpoch fence +
feed reset) ikinci adversarial self-review'ı (2 paralel run) 5 CONFIRMED + 1 PLAUSIBLE gerçek regresyon/boşluk
buldu — TAMAMI TDD ile düzeltildi (99e7ad3 RewardsKit CI-yeşil + 8d74a4b App lokal-yeşil):
- **refreshCheckIn CATCH generation-fence'siz (MEDIUM):** başarı yolu guard'lıydı, catch koşulsuz loadState
  yazıyordu → başarılı claim SONRASI uçuştaki status() THROW ederse para-ekranı tam-ekran hataya kırılırdı
  (buton regresyonu throw yolundan) + switch throw yolunda B sahte hataya düşerdi. Fix: catch'e generation guard.
- **resetForAccountSwitch loadTask iptal/serbest bırakmıyordu (MEDIUM):** switch uçuştaki İLK yüklemeye denk
  gelirse loadTask non-nil kalır → B döndüğünde onAppear→startRefreshIfIdle reload'u boğulur → sonsuz .loading
  (retry butonu yok). Fix: reset loadTask.cancel()+nil; runRefresh bayat görev loadTask'ı EZMESİN.
- **YERLEŞMİŞ claimFailure/taskClaimFailure cross-account sızıntı (MEDIUM):** A'nın başarısız-claim hata
  banner'ı B ekranında görünürdü (load/refresh temizlemez) + generic-catch'ler epoch-fence'siz → switch
  SONRASI çözülen A hatası B'ye yazılırdı. Fix: reset ikisini temizler + iki generic-catch'e epoch guard.
- **App gözlemci nil-userID ARA-DURUM switch kaçağı (MEDIUM, paywall bypass):** Home+Rewards gözlemcileri
  lastUserID'yi koşulsuz güncelliyordu → loggedOut'ta nil'e set ediyor, sonraki farklı-hesap re-auth'u
  (u1→loggedOut→u2) switch sanmıyordu → A'nın .unlocked feedState'i B'ye sızardı. Fix: lastUserID yalnız
  non-nil'de güncellenir (her iki koordinatörde simetrik).
- **Home reset eksik kapsam + continueEntry cross-account (MEDIUM/LOW):** path/bolumListesiModel/speedMenu/
  subtitle + "devam et" banner'ı (continueEntry) B'ye taşınıyordu. Fix: resetForAccountSwitch hepsini temizler;
  ContinueWatchingEntryModel.reset() + B-reload.
- **(NOT) isClaiming/claimingTaskID:** re-run doğrulayıcısı bunların defer ile kendi-kendine temizlendiğini
  (kalıcı sızmaz) belirledi → ayrıca reset edilmedi (asıl sızıntı claimFailure/taskClaimFailure idi).

---

## Kod-içsel (prep gerektirmeyen) kalan iş — ayrı izlenir
- SS-050 kilit-sınırı reactivation (varsa gap), LibraryCatalog offline cache, WP-F1-G
  review'unda ertelenen küçük optimizasyonlar (CatalogCache `lastAccessAt`/tahliye-bütçe,
  ListemModel batch-delete). Bunlar prep GEREKTİRMEZ; sürekli döngüde ele alınır.
