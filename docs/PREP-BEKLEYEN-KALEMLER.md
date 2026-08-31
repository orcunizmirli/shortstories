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
- **linkSession snapshot/token ayrışması (MEDIUM) → DÜZELTİLDİ (ada4b69):** 3 Keychain yazması ayrı best-effort'tu;
  snapshot-torn → "guest snapshot + linked token" ayrışması. **Fix:** `SecureStoring.setAtomically` primitifi
  (protocol extension → conformer/okuyucu değişmez): yedekle→tümünü-yaz→koparsa-geri-al (torn kalmaz, ya hepsi-yeni
  ya hepsi-eski); linkSession bunu kullanır. Native transaction yok → rollback da koparsa nadir tam garanti değil
  ama yaygın torn engellenir. TDD: SecureStoringAtomicTests + linkSession torn testi (revert-verify). 317 test yeşil.
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
- **FavoritesService kalıcı-red rollback yok (LOW) → DÜZELTİLDİ (98c9647, ürün kararı: ROLLBACK):** syncAdd/
  syncRemove offline-dışı tüm hataları `.skipped` sayıp süresiz retry ediyordu → kalıcı 4xx redde iyimser
  favori geri alınmıyordu (kendini düzeltmeyen local/server ayrışması). Fix: rollbackAdd/rollbackRemoval repo
  metodları + DAR sınıflandırma (isPermanentRejection = yalnız 4xx-non-429 içerik; 5xx/timeout/`.unexpected`/
  `.decoding` GEÇİCİ → pending kalır); PUT-kalıcı → rollback, DELETE 404 → idempotent-confirmed, DELETE-kalıcı
  → favori korunur. TDD: FavoritesRollbackTests 4 test (revert-verify). 68 LibraryKit + 314 AppFoundation yeşil.

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
- **applyBalance version-monotonic (donma fix) — TAMAMLANDI (2026-08-31, commit'ler 5e3395e + a072bb4).**
  value-heuristic (`>= awaited`) yerine WalletStore monoton `version`'ı (05 §2.5) tüketiciye taşındı;
  OdulMerkezi yalnız STRICTLY-NEWER version uygular (bayat replay düşer, meşru spend uygulanır → DONMA yok).
  WalletKit: `VersionedCoinBalance` + `WalletGateway.versionedBalanceUpdates()` (additive; `broadcastBalance(from:)`
  iki multicast'i aynı snapshot'tan besler). RewardsKit: `currentBalance() -> RewardsBalanceUpdate`, awaitedBalance
  kaldırıldı. App adapter versioned akış + `currentSnapshot().version`. **Self-review (2. görüş agent) cross-account
  poison regresyonu buldu → `guard hasLoaded` ile kapatıldı (version'lar hesaba özel; canlı stream yalnız otoriter
  baseline sonrası uygulanır).** TDD revert-verify (freeze + poison testleri). Residual accepted-LOW'lar:
  - **BULGU 2 (LOW, accepted):** 409 kolları (claimToday/claimTask) `applyAuthoritativeBalance`'ı `lastApplied`'ı
    bump ETMEZ → araya giren ara-version stream emisyonu 1-frame eski değere döndürüp düzelebilir (transient
    flicker). Eventual-consistency ile uyumlu. Fix (409'da `applyBalance(update)` kullan) applyBalance'ı `internal`
    yapmayı gerektirir (+Tasks ayrı dosya) → görünürlük genişletme + over-engineering riski; ertelendi.
  - **BULGU 3 (not, fragility):** WalletStore.applyWallet `>=` (eşit-version yeniden yayınlar) vs OdulMerkezi `>`
    (eşit düşürür). Monoton-version sözleşmesi altında eşit version ⇒ eşit bakiye → kayıp yok. Sunucu sözleşme
    ihlaliyle (aynı version farklı bakiye) OdulMerkezi ilkini, versiyonsuz ProfilKit ikincisini gösterirdi — istemci
    regresyonu değil, kırılganlık notu.
  - **BULGU 4 (test-fake fidelity, LOW):** `FakeWalletGateway.currentSnapshot()` sabit fixture version'ı döner,
    `pushBalance` ayrı `_version` (0,1,2…) yayar → App-adapter testinde currentBalance vs stream version'ları
    ayrık olabilir. Üretim hatası değil (OdulMerkezi FakeRewardsWallet ile koşar, o tutarlı). Şu an version'a
    dayanan App-adapter testi yok → latent; ileride adapter version testi eklenirse fake hizalanmalı.
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
- **200 + boş gövde → sessiz boş son-sayfa (LOW) → DÜZELTİLDİ (df45ed3):** PageWire/DiscoverWire tüm-opsiyonel
  olduğundan `{}` ve BOŞ gövdeden başarıyla decode oluyordu; decodeEmptyBody `{}` fallback'i 204 uçları için
  tasarlanmıştı ama içerik uçlarını da yakalıyordu → CDN/proxy 200 + 0-bayt (truncation) dönerse Page(items:[],
  nextCursor:nil) → isLastPage=true → sayfalama sessizce durur / Keşfet boşalır. **Fix:** decodeEmptyBody
  YALNIZ EmptyResponse için boş-gövde başarısı döner; içerik tipleri (tüm-opsiyonel olsa bile) nil → APIClient
  zaten `throw .decoding` (retry/hata yüzeyi). EmptyResponse-typealias 204 uçları DEĞİŞMEZ. TDD:
  bosGovdeTumAlanlariOpsiyonelIcerikTipiDecodingHatasiVerir (RED→GREEN). 314 AppFoundation testi yeşil.

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
- **Deep-link `search?q=` Arama açıkken query düşürülür (LOW) → DÜZELTİLDİ (f47d199):** showSearch Arama açık+query
  doluysa pop(Arama+üstündeki DiziDetay)+repush(query) ile ön-doldurma uygular (query yoksa no-op, çift-Arama önleme korunur).
- **`.series` deep-link idempotent değil (LOW) → DÜZELTİLDİ (f47d199):** showDetail `detailMarker (seriesID, depth)` →
  aynı dizi hâlâ tepedeyken (marker.depth == path.count) push bastırılır (deep-link/çift-tap özdeş DiziDetay çoğaltmaz).
  TDD: DiscoverNavigationTests 4 test (revert-verify RED→GREEN), 232 App testi yeşil.
- **Standalone VIP aktivasyonu feed'i reaktive etmez (LOW) → DÜZELTİLDİ (68492ef):** vipSubscriptionDidActivate
  yalnız vipModel=nil yapıyordu; standalone VIP (Profil/deep-link) feed'i açmıyordu → VIP tüm erişim verdiği halde
  kilitli bölümler `.locked` kalıyordu. **Fix:** FeedUnlockReducer.applyingVIPUnlock (tüm kilitli → .unlocked,
  idempotent) + HomeCoordinator.applyVIPUnlock + WalletFlowCoordinator.onVIPActivated callback (onEpisodeUnlocked
  deseniyle simetrik; diff'li apply, remount yok). TDD: FeedUnlockReducerTests +3, 235 App testi yeşil.

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

### Oturum-değişikliği self-review-3 — en yeni 5 fix (2026-08-30, HEPSİ DÜZELTİLDİ)
self-review2 SONRASI eklenen 5 deferred-backlog fix'inin (AnalyticsKit persist / PlayerKit warm→Bool /
empty-body / nav markers / VIP) 3. adversarial self-review'ı 4 CONFIRMED regresyon buldu — **ÜÇÜ benim
YENİ fix'lerimin regresyonu** (desen 3. kez kanıtlandı). TAMAMI TDD ile düzeltildi:
- **Keşfet nav marker/derinlik KIRILGAN (nav fix f47d199 regresyonu; MEDIUM+LOW) → DÜZELTİLDİ (3f2dd2a):**
  NavigationPath element-peek edilemez, sistem-geri path'i coordinator kodu koşmadan dışarıdan mutate eder →
  detailMarker bayat + marker.depth==path.count SPOOF'lanabilir → (MEDIUM) dead-tap + DiziDetay çoğaltma;
  (LOW) query-forward removeLast kullanıcının DiziDetay'ını yıkıcı poplar. **Kök fix:** path NavigationPath→
  `[AppRoute]` (ProfileCoordinator deseni) → gerçek `path.last`/lastIndex peek; searchStackDepth+detailMarker
  KALKTI. +3 regresyon testi (sistem-geri simüle).
- **VIP çift-reaktivasyon (VIP fix 68492ef regresyonu; MEDIUM) → DÜZELTİLDİ (da10d67):** UnlockSheet-çocuğu
  VIP'te onVIPActivated (tümü) + unlockSheetDidUnlock (tek) aktif kart N'yi İKİ feedState yazımıyla reaktive
  edebilir. **Kök fix (PlayerKit):** reactivatableUnlockIndex saf+static + TRANSITION korkuluğu (yalnız
  kilit→açık geçişinde reactivate; previousItems'da zaten playable ise nil) → tüm çift-write'ları savunur.
- **prepareNext kalıcı-hata her-swipe re-warm (warm→Bool fix e8d9ec7 regresyonu; LOW) → DÜZELTİLDİ (49a504a):**
  kalıcı hata (4xx/içerik-kaldırıldı) geçiciyle aynı kefede → false → completedWarmups'a girmez → her swipe
  boşa authorize. **Fix:** catch'te AppError.isRetryable ile ayır (kalıcı→true, geçici→false).
- **DERS:** self-review'ı kompleks fix'lerin ÜSTÜNE tekrar tekrar koş — her geçiş (2 ve 3) benim ÖNCEKİ
  fix'imde yeni regresyon buldu. Nav marker/derinlik heuristiği (NavigationPath) temelde kırılgan → `[AppRoute]`
  peek doğru altitude.

### Oturum-değişikliği self-review-4 — self-review3 fix'leri (2026-08-30, HEPSİ DÜZELTİLDİ)
self-review3'ün DÜZELTTİĞİ fix'lerin 4. review'ı 2 CONFIRMED MEDIUM buldu (ikisi de self-review3 fix'lerimin
KENDİ kenar-değiş-tokuşu; nav [AppRoute] TEMİZ çıktı). DÜZELTİLDİ (476b8b5):
- **TRANSITION-check (da10d67) başarısız-reaktivasyon retry'ını bastırıyordu (MEDIUM):** `.failed` (transient)
  reaktivasyon sonrası lockedIndex=N kalır + kart playable → sonraki apply'da previousItems[N] zaten playable →
  transition yok → nil → kart oynatmaz. **Fix:** transition heuristiği yerine UÇUŞ-guard'ı (reactivatingIndex;
  dispatch'te set, settle'da temizlenir) → çift-apply bastırılır AMA başarısızlık retry'ı korunur.
- **prepareNext isRetryable (49a504a) `.unexpected` slot-çekişmesini kalıcı sanıyordu (MEDIUM):** geçici
  slot-çekişme → completedWarmups → sticky-cold. **Fix:** `.unexpected`'i kalıcıdan hariç tut → re-warm.
- **META-DERS:** "akıllı heuristik" fix'ler (transition/isRetryable-broad) art arda kenar-değiş-tokuşu yaptı;
  yapısal/gerçek-durum çözümler (nav [AppRoute] peek, in-flight guard, narrow-exclude) sağlam. Heuristik yerine
  gerçek-durumu izle. self-review zincirini fix temizlenene dek sürdür (4 geçiş: her biri bir öncekini düzeltti).

### Oturum-değişikliği self-review-5 — CONVERGENCE + 1 KABUL-EDİLEN LOW (2026-08-30)
self-review4 fix'lerinin 5. review'ı YALNIZ 1 bulgu buldu (MEDIUM→LOW düşürüldü, bağımsız verifier "tradeoff
SAVUNULABİLİR" dedi) → self-review zinciri CONVERGE etti (MEDIUM'lar → savunulabilir LOW).
- **prepareNext `.unexpected`-exclude de kenar-değiş-tokuşu (LOW, KABUL EDİLDİ):** `.unexpected` yalnız slot-çekişme
  DEĞİL — APIClient KALICI transport/config hatalarını (TLS/cert/redirect/ATS/interceptor) da `.unexpected`'e map
  eder (appError(from:) default kovası). Bu yüzden `.unexpected→false (re-warm)` config-outage'da "her-swipe boşa
  authorize"ı geri getirir. **NEDEN KABUL:** (1) authorize `.unexpected` ENDPOINT-seviyesi/all-or-nothing (per-bölüm
  404/403/5xx → `.network(.server)`/`.content`, ASLA `.unexpected`) → yalnız TLS/config-outage'da ateşlenir, o durumda
  aktif kart da oynamaz (app zaten bozuk) + feed'den çıkınca cancelAll temizler; (2) israf per-swipe sınırlı, görünmez
  arka-plan pil/bant, correctness/UX/crash yok; (3) tradeoff sık+kritik slot-çekişmeyi (sticky-cold spinner) DOĞRU
  çözer, ender config-outage'da minör israf yapar — verifier "gerçek ama düşük etkili, savunulabilir" dedi; (4)
  `.unexpected` type-erased catch-all olduğundan HER sınıflandırma kenar-değiş-tokuşu yapar (5. kez) → belirsizliğin
  savunulabilir dengesi. **YAPISAL SEÇENEK (gelecek):** slot-çekişme `.unexpected` yerine DİSTİNKT retryable hata
  (yeni `PlaybackError.temporarilyUnavailable`, isRetryable=true) fırlatsın → prepareNext plain isRetryable kullanır,
  `.unexpected`-exclude kalkar, ambiguity kökten çözülür (slot→retryable→re-warm; config-outage `.unexpected`→
  not-retryable→re-warm-yok). AppError paylaşılan-infra dokunuşu + slot≠playback semantik pürüzü → LOW için ertelendi.

### PlayerKit adversarial bug-hunt — ertelenen kalem (2026-08-31)
PlayerKit bug-hunt (16 agent → 6 doğrulanmış); 5 CI-testli fix DÜZELTİLDİ (commit 6aa2919: #1 pool reclaim
isAuthorizing, #2 reaktivasyon `.none` guard, #3 reorder kimlik-tabanlı, #5 auto-advance suppress sızıntısı,
#6 aktif-slot idle-restart). 1 App-katmanı kalem ertelendi:
- **VIP-expiry/iade IN-SESSION re-lock YOK (HomeCoordinator, MEDIUM CONFIRMED):** WalletFlowCoordinator yalnız
  AÇMA-yönü callback'i taşır (onEpisodeUnlocked/onVIPActivated); onVIPExpired/onEpisodeRevoked YOK. Kullanıcı VIP
  bölüm izlerken abonelik iade/expire olursa WalletStore.hasAccess false'a döner ama feed HABERDAR EDİLMEZ →
  açık bölüm oynamaya devam eder + komşu `.unlocked` kartlar app-restart/server-feed-reload'a dek oynatılabilir
  kalır (iade in-session erişimi geri almaz). **Fix:** WalletFlowCoordinator'a downgrade callback + FeedPlayback
  Director'a entitlement-düşüş gözlemcisi (aktif handle'ı re-lock / `.unlocked` işaretleri temizle) — App-wiring +
  WalletStore→feed downgrade yolu gerektirir (App CI-dışı → odaklı pass). Nadir senaryo (aktif izlerken iade) → MEDIUM.

### AppFoundation adversarial bug-hunt — ertelenen 2 kalem (2026-08-31)
AppFoundation bug-hunt (9 agent → 5 doğrulanmış). Ortak tema: `try?` geçici keychain hatasını yıkıcıya
çevirir. 3 CI-testli fix DÜZELTİLDİ (commit 829fc6f: #1 handleRefreshFailure linked-demotion, #4
setAtomically yedek-oku, #3 APIClient taze-token override). 2 kalem ertelendi:
- **#2 TokenRefreshCoordinator iki-yazım cross-thread yarışı (MEDIUM PLAUSIBLE, mimari):** performRefresh
  rotasyonlanmış çifti İKİ AYRI senkron yazımla (refresh @137, access @141) yazar; rotation guard yalnız
  yazımlardan ÖNCE (@128) örnekler. Eşzamanlı `linkSession` (MainActor, setAtomically) iki yazım ARASINA
  (137↔141) girerse (linked refresh + guest access) uyumsuz çift kalır → AuthInterceptor guest access
  gönderir (cross-identity), sonraki 401'de self-heal. KÖK: KeychainSecureStore lock'suz non-isolated
  struct → cross-domain yazımlar serileşmez; setAtomically CRASH-torn'u önler ama concurrent-thread'i DEĞİL.
  **Fix:** keychain yazımlarını tek serileştirme noktasına al (KeychainSecureStore'a lock, ya da tüm token
  yazımlarını tek actor'den geçir). OS-preemption'lı sub-mikrosaniye pencere + eşzamanlı link + self-heal →
  mimari, LOW-öncelik ertelendi.
- **#5 resetLocalUserData deleteAll `try?` cross-account sızıntı (LOW PLAUSIBLE, App-katmanı):**
  `LiveAccountSwitchDataCoordinator.resetLocalUserData` (AccountServiceAdapters.swift:74-75) watchHistory/
  favorites `deleteAll()`'ı `try?` ile yutar. deleteAll LOKAL güvenlik-kritik silme (AĞ DEĞİL — comment'in
  "ağ hatası bloklamamalı" gerekçesi burada geçersiz); SwiftData `save()` disk-pressure'da throw ederse guest
  satırları KALIR → refetchForNewAccount().synchronize() yeni-hesap sunucu geçmişini bunlarla MERGE eder →
  yeni hesabın Devam-Et/Listem'inde önceki GUEST'in özel izleme geçmişi/favorileri görünür (cross-account
  privacy leak). deleteAll impl'leri atomik+doğru; kusur orkestratörün wipe'ı best-effort saymasında.
  **Fix:** lokal-wipe'ı ağ-sync'ten AYIR — wipe başarısızsa refetch/merge'i ATLA (yeni hesap boş kalır,
  sonraki açılışta taze reset+sync temizler) ya da wipe'ı retry et. Protokol dönüş-tipi + switch-flow
  merge-gate değişikliği; App CI-dışı, tetik nadir (disk-fail) → odaklı pass.

### ContentKit adversarial bug-hunt — ertelenen 1 kalem (2026-08-31)
ContentKit bug-hunt (9 agent → 6 doğrulanmış). 5 CI-testli fix DÜZELTİLDİ (commit af8c951: decode-aşaması
droppedItemCount, non-core tarih toleransı, yanlış-tip array alanı). 1 kalem ertelendi:
- **unlockPrice == 0 istemci-tarafı 0-coin unlock (MEDIUM PLAUSIBLE, defensive/cross-package):** Sunucu
  `access = {kind: locked, unlockPrice: 0}` dönerse (backend misconfig/promo bug — kanon 50-100 coin) istemci
  0'ı reddetmez: UnlockSheetViewState.resolveCoinState `.sufficient(price: 0)` → aktif "0 coin'e aç" butonu +
  SpendPlanner 0-coin plan + PlayerCell "0 coin" rozeti; performUnlock 0-fiyatlı unlock'ı otomatik ateşleyebilir.
  Not: bulgunun işaret ettiği `EpisodeAccess.isCoinUnlockAvailable` ÖLÜ kod (yalnız testte); gerçek yol
  `episode.access.unlockPrice`'ı doğrudan WalletKit'e taşır. **Fix:** istemci `unlockPrice <= 0`'ı "coin yolu
  kapalı" (isCoinPathClosedLock gibi) say — bedava-unlock DEĞİL. Server-contract-ihlaline karşı savunmacı
  clamp; WalletKit/UnlockSheet (App-katmanı) dokunuşu + "0-fiyat nasıl yorumlanmalı" ürün kararı → ertelendi.

### DiscoverKit adversarial bug-hunt — ertelenen 2 kalem (2026-08-31)
DiscoverKit bug-hunt (14 agent → 9 doğrulanmış). 6 CI-testli fix DÜZELTİLDİ (commit 3854329 + self-review
f327339: recent-search newline, loadMore sonsuz-sayfalama, öneri bayat/boş/ağ-hatası, CTA kilit-etiketi, load
guard). **#2 (entitlement-gözlem) sonradan DÜZELTİLDİ (2026-08-31, aşağıda ✅).** Kalan 2 ertelenen kalem:
- **#3 DiziDetay ilerleme-hedefi derin-sayfa GEÇİCİ hatasında yanlış .start CTA (LOW, izleme-yeri kaybı):**
  ensureProgressEpisodeLoaded ilerleme bölümünün derin sayfasını çekerken GEÇİCİ hata alırsa (`try?` yutar) CTA
  sessizce .start'a (Bölüm 1) düşer → kullanıcı kaldığı yeri kaybeder. **İLK fix'im (recompute-throws → hata
  yüzdür) SELF-REVIEW'da REGRESYON çıktı** (`.content(.notFound)` → handleLoadError → `.removed` dead-end; canlı
  dizi "yayında değil" + retry yok) → best-effort `try?`e geri alındı (regresyon-guard testi eklendi). **Doğru
  fix:** progress'i `episodeId`+`positionSec` ile RESUME et (WatchProgress'te var) — ekranı BOZMADAN doğru
  bölüme git; delegate `diziDetayStartWatching` episodeNumber yerine episodeId kabul etmeli (cross-package,
  ContinueWatchingTarget + PlayerFeed sözleşmesi). Ekranı-bozan yerine izleme-yeri-koruyan çözüm.
- **#2 DiziDetay CTA/entitlement unlock/VIP SONRASI bayat (MEDIUM CONFIRMED — ✅ DÜZELTİLDİ 2026-08-31):**
  `accessibleEpisodeIDs`/`ctaLocked` yalnız load()/loadMoreEpisodes()'te hesaplanıyordu → kullanıcı Bölüm 6'yı
  açtıktan sonra AYNI DiziDetayModel'e dönünce CTA 🔒 kalıp zaten sahip olunan bölüm için UnlockSheet'i yeniden
  açıyordu (ödediği içeriği oynatamıyordu); ekran açıkken VIP olan kullanıcıya da kilitli hücreler kilitli
  kalıyordu. **Çözüm (REAKTİF self-gözlem, coordinator wiring gerekmez):** DiscoverKit'e `EntitlementChangeObserving`
  portu + DiziDetayModel'de `startObservingEntitlementChanges` → `recomputeAccess` (recompute'tan ayıklandı; hafif
  re-derive, progress ağ-fetch'i yok); `nonisolated(unsafe)` gözlem task'ı + deinit iptali. App-wiring:
  `WalletGatewayEntitlementChangeObserving` adaptörü (`WalletStore.entitlementUpdates` → `AsyncStream<Void>`,
  `AsyncStream.mapping` köprüsü) `makeDiziDetayModel`'e bağlandı. **Self-review yarış-fix'i (H3 CONFIRMED):**
  gözlemci guard'ı `loadState == .loaded` → `ctaTarget != nil` (load recompute'u ile loadState=.loaded arası
  favorites-await penceresinde gelen cold-start/deep-link broadcast'ı YUTULMASIN). 2 TDD testi (post-load
  re-derive + yükleme-penceresi yarışı, ikisi de revert-verify RED-doğrulandı). DiscoverKit 151 test yeşil,
  App lokal derlendi, tam-repo lint temiz. Diğer teardown/lifecycle/paywall-bypass hipotezleri REFUTED.
- **#9 DiscoverSessionStore cross-account (LOW CONFIRMED, App coordinator reset):** `DiscoverSessionStore.cached`
  `public private(set)` ama reset/clear API'si YOK (yalnız save/init); DiscoverCoordinator'da uzun-ömürlü `let`
  olarak tutulur, hesap/session gözlemcisi YOK — oysa uzun-ömürlü coordinator'lar hesap-değişiminde reset
  edilmeli (RewardsCoordinator/HomeCoordinator deseni). A kullanıcısı tür filtresi seçip Kesfet yükler →
  B'ye switch (aynı process, DiscoverCoordinator yeniden yaratılmaz) → B Kesfet açar, KesfetModel.init A'nın
  selectedGenreID'sini okur → A'nın filtresiyle yükler (cross-account state sızıntısı). **Fix:** DiscoverSession
  Store.reset() + DiscoverCoordinator'a session.stateUpdates gözlemcisi (userID-change → reset), cross-account
  UI-state cluster deseniyle simetrik. App-wiring → odaklı pass.

---

## Kod-içsel (prep gerektirmeyen) kalan iş — ayrı izlenir
- SS-050 kilit-sınırı reactivation (varsa gap), LibraryCatalog offline cache, WP-F1-G
  review'unda ertelenen küçük optimizasyonlar (CatalogCache `lastAccessAt`/tahliye-bütçe,
  ListemModel batch-delete). Bunlar prep GEREKTİRMEZ; sürekli döngüde ele alınır.
