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
- **OdulMerkeziModel hesap-değişiminde reset yok (OdulMerkeziModel.swift:79, MEDIUM CONFIRMED — ✅ DÜZELTİLDİ):**
  `OdulMerkeziModel.resetForAccountSwitch()` (claimedTaskIDs/checkInState/hasLoaded temizler + accountEpoch bump)
  + `RewardsCoordinator` account-switch gözlemcisi wiring'i (odulMerkeziModel + referralModel reset) mevcut. model
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
- **claim/applyAuthoritativeBalance epoch guard yok (OdulMerkeziModel.swift:267/289, MEDIUM/LOW PLAUSIBLE — ✅ DÜZELTİLDİ):**
  `accountEpoch` + TÜM apply-after-await yolları (claimToday/claimTask/+Tasks/load/runRefresh) await-öncesi `let epoch =
  accountEpoch` + apply-öncesi `guard epoch == accountEpoch` (OdulMerkeziModel+Tasks.swift) uygulanmış.
  claimToday/claimTask `await claim()` ÖNCESİ epoch yakalamaz, SONRASINDA apply-öncesi doğrulamaz →
  uçuştaki claim yanıtı bir bağlam/hesap değişiminden sonra uygulanınca cross-account/bayat kredi; ayrıca
  eşzamanlı iki claim'de geç dönen DAHA ESKİ bakiye anlık-görüntüsü yeniyi ezebilir. Yukarıdaki reset
  (§hesap-değişimi) + akış-versiyonlama ile AYNI altyapıyı paylaşır → o iki fix'le birlikte ele alınacak.
  (Not: todayReward computed var'ının schedule fallback'i [OdulMerkeziModel.swift:159, LOW] → **DÜZELTİLDİ
  (b523b27):** paylaşılan CheckInCycle.todayReward(for:) — buton etiketi + takvim bugün hücresi tek kaynak.)

### ProfileKit hesap-yaşam-döngüsü adversarial bug-hunt (2026-09-01)
ProfileKit (HesapSilme/HesapBaglama/BildirimMerkezi/Profil/Ayarlar) hunt: HIGH/MEDIUM yok (F1–F6 concurrency
testleri sıkı; double-confirm silme gate'i airtight). 1 LOW düzeltildi + 1 accepted-contract:
- **NotificationCenterModel.delete telafisi araya giren load-FAILURE'ı düşürüyordu (LOW — ✅ DÜZELTİLDİ):** delete
  `await`'i sırasında retry-load OFFLINE hata verirse `.errorWithCache` set edilir ama `listEpoch` yalnız load-
  BAŞARISINDA bump'lanır → delete-catch epoch fence'i (guard epoch==listEpoch) yakalamaz → bayat `.loaded`
  snapshot `.errorWithCache`'i ezerdi (offline hata "loaded/boş inbox" yanlış etiketlenir). **Fix:** telafi
  `if loadState != .errorWithCache { loadState = previousLoadState }` — araya giren hata durumu KORUNUR. TDD:
  deleteCompensationPreservesInterleavedLoadFailureState (RED→GREEN); 166 ProfileKit testi yeşil.
- **ProfilModel same-provider A→B switch iç wallet-reset yok (LOW, ACCEPTED-contract):** `AccountSummary.make`
  userID'yi düşürür → observeSession same-provider switch'i algılayamaz; wallet reset'i dış `WalletStore.reset`
  broadcast'ine (observeWallet) dayanır. Server-otoriter-para ile tutarlı (dış broadcast otoriter reset; session-
  death sticky-clear zaten var). ProfileKit'ten exploit edilemez → iç redundant defense EKLENMEDİ (accepted).

### Coin-ekonomisi END-TO-END entegrasyon adversarial bug-hunt (2026-09-01)
Unlock (coin/ad/VIP) → WalletStore → entitlement broadcast → feed re-lock → OdulMerkezi/Profil/CoinShop bakiye
entegrasyonu hunt'ı: 3 gerçek cross-component bug (coin-unlock tutarlılığı, VIP re-lock, version-monotonic bakiye,
account-fence'ler SAĞLAM doğrulandı):
- **#1 AD-unlock DiziDetay/BolumListesi'ye görünmez (MEDIUM — ✅ DÜZELTİLDİ):** ad-unlock (network-only) WalletStore'a
  dokunmaz + entitlement broadcast etmez; DiziDetay/BolumListesi yalnız `hasAccess`'e dayanır → ad ile açılan bölüm 🔒
  kalır, tekrar tıklanınca sahip-olunan içeriğe paywall açılır (DiziDetay'dan oynatılamaz). **Fix:** `WalletGateway.
  confirmAdUnlock(episodeID:)` (WalletStore: `confirmUnlocked` — bölüm açık işaretle + `lastUnlocked` broadcast, bakiye
  DEĞİŞMEZ); `UnlockSheetModel.watchAd` `.unlocked`'ta çağrılır → coin `unlock` ile simetrik, tüm `hasAccess`-tüketiciler
  tutarlı. TDD: reklamUnlockCuzdanEntitlementineYansir + confirmAdUnlockBolumuAcarBakiyeyeDokunmaz (RED→GREEN); 305 WalletKit yeşil.
- **#2 Check-in/görev claim'i WalletStore'a ulaşmaz → OdulMerkezi vs Profil/CoinShop ıraksak bakiye (MEDIUM — ✅
  DÜZELTİLDİ):** claim doğrudan API'ye gider, WalletStore'a yansımazdı; refresh yalnız cold-start/switch/purchase'ta
  → oturum-içi ıraksama (finansal kayıp yok — server otoriter; app-restart'ta düzelirdi). **Fix:** `RewardsDelegate.
  rewardsDidCreditBalance()` (default empty) → claimToday + claimTask BAŞARISINDA fire → `RewardsCoordinator` bunu
  alıp `composition.walletStore.refresh()` tetikler → tüm cüzdan-tüketiciler yakınsar. TDD: successfulCheckInClaim/
  successfulTaskClaim CreditsBalanceForWalletRefresh (RED→GREEN); 158 RewardsKit yeşil, App build + lint temiz.
- **#3 AD-unlock account-epoch fence yok + WalletFlow sheet switch'te reset olmaz (LOW, ACCEPTED):** tam-ekran modal
  reklam mid-ad hesap-switch'i engeller; post-ad pencere alt-saniye + feed-reset + server-reload mitige → near-unreachable.

### Catalog-cache + playback-authorize hunt (2026-09-01)
En az taranan money-bitişik altyapı. **AREA A (catalog cache): TEMİZ** — HTTP `.cacheFirst`/`.staleWhileRevalidate`
Phase-stub (SS-020, sözleşme-only, canlı DEĞİL) → her katalog fetch taze; canlı CatalogCache (Listem JOIN) yalnız
display-data (title/cover/episode-number, lock-state YOK) → bayat-lock-state trust bug'ı imkansız; TTL/eviction/decode/
cross-account doğru. **AREA B (playback authorize): 1 MEDIUM + 2 LOW (✅ hepsi DÜZELTİLDİ):**
- **MEDIUM — `PlaybackAuthorizationProvider` imzalı-URL cache'i drain/hesap-switch'te tam invalidate edilmiyordu:**
  provider yalnız per-episode `invalidate()` sunuyordu, `invalidateAll` yoktu; `PlayerPool.drain` ona dokunmuyordu;
  provider app-oturumu ömrü (HomeCoordinator) + switch'te yeniden yaratılmaz → cache ÖNCEKİ HESABIN imzalı HLS
  URL'lerini tutuyordu. Birincil gate (isPlayable→hasAccess reset walletStore'u okur) yaygın durumu kapatır AMA
  feedState-B-çizdi/walletStore.reset()-henüz-inmedi penceresinde A'nın URL'iyle authorize'sız yayına izin verebilirdi
  (server URL'i A-session'a bağlarsa CDN 403→re-authorize→locked; bağlamazsa ücretsiz izleme). Kod tabanının "switch'te
  TÜM hesap-state reset" disiplininin tek deliği. **Fix:** `invalidateAll()` + `PlayerPool.drain`'de çağrılır (feed
  teardown→drain hesap-switch remount'unda fire eder; sınırsız cache büyümesini de keser — LOW #3). TDD: invalidateAll
  tüm cache'i temizler (RED no-op → GREEN + revert).
- **LOW — authorize sonucu episodeId doğrulanmadan cache'leniyordu:** server yanlış bölümün yetkisini dönerse istenen
  bölüm altında BAŞKA URL tutulurdu. **Fix:** `guard auth.episodeId == episodeID` (throw); guard **Task İÇİNDE** →
  owner + coalesced-joiner ikisi de doğrulanır (regresyon-verify hunt'ı joiner'ın atlandığını gördü → tamamlandı).
  TDD: owner-mismatch fırlatır + coalesced-joiner da fırlatır (ikisi de RED→GREEN + revert).

### Money-core regresyon-verify (self-review, 2026-09-01)
Bu oturumun sonraki money-core commit'lerinin (4412def double-charge, 8d890c2 viaVIP, eec821d firstTopUp/unlock_ad,
5b432c6 authorize) bağımsız-context adversarial regresyon-doğrulaması: **REGRESYON YOK** (ilk regresyon-hunt check-in
pin'de MEDIUM bulmuştu → bu tur temiz, güçlü yakınsama). viaVIP mis-tag'leri hasAccess semantiğiyle korunur
(coin/ad unlockedEpisodes'ta → re-lock'tan bağışık), applyVIPUnlock idempotent (çift onVIPActivated güvenli),
firstTopUp refresh clobber-etmez, unlock_ad tek-atım. **1 LOW ERTELENDİ (kabul, PREP):** `.pending` sheet-içi
kurtarılabilirlik — Profil-source açık sheet'te pending arka planda çözülünce (parent onayı → bakiye kreditlenir)
banner "Onay bekleniyor" kalıp buton yeniden-etkinleşmez → close+reopen ile kurtarılır (para kaybı yok, pending-sırası
bloklama DOĞRU). Tam fix `Transaction.updates`→phase-transition gözlemi gerektirir (mimari; herhangi-bakiye-kredisinde
temizlemek pending'i-BAŞKA-krediyle-açar double-charge penceresini geri açar → SPESİFİK işlem eşleşmesi şart).
- Phase-2 stub'lar (bug DEĞİL): FairPlay/DRM (`PlaybackAuthorization.drm` opsiyonel, clear-HLS F1); HTTP cache SS-020.
  290 PlayerKit yeşil, lint temiz.

### Money-flow error/offline + analytics-funnel hunt (2026-09-01)
Money/entitlement/reward flow'larının error/offline/retry tutarlılığı + funnel-event bütünlüğü taze hunt'ı.
Money-state + funnel DERİNLEMESİNE SOUND (HIGH yok): iap_credited/unlock_coin/checkin_claim/mission_claim/
referral_redeemed hepsi tek-atım + server-confirm noktasında; optimistik-rollback + stuck-phase + generation/epoch
fence'leri doğru. 2 analytics/display bulgusu (money server-safe) düzeltildi:
- **MEDIUM — CoinShop firstTopUp satın-alma sonrası bayat (✅ DÜZELTİLDİ):** `firstTopUpEligible` server-otoriter +
  katalog-global (canlı bakiye yayını taşımaz), yalnız `load()`'ta set ediliyordu; `purchase().completed` yalnız
  balance tazeliyordu → Profil'den açılıp ekran açık kalınca ikinci satın almada yanıltıcı 2x banner/kart +
  `is_first_purchase_offer:true` (tükenmişken). **Fix:** `.completed` sonrası SESSİZ katalog tazeleme
  (`refreshCatalogAfterPurchase`): items + firstTopUpEligible yeniden kurulur; loadPhase DEĞİŞMEZ (flicker yok);
  hata/boş → mevcut korunur (başarılı satın alma ekranı .failed'e kırılmaz); sheet kapandıysa no-op. TDD: firstTopUp
  tüketilince banner+kart tazelenir (RED→GREEN); 313 WalletKit yeşil. (İlk WalletKit-UI hunt'ında LOW görülmüştü,
  ikinci hunt MEDIUM'a yükseltti → iki-hunt doğrulaması.)
- **LOW — `unlock_ad` funnel epoch-fence ÖNCESİ ateşleniyordu (✅ DÜZELTİLDİ):** reklam-watch uçuştayken hesap
  değişirse `confirmAdUnlock` false döner (unlock düşer) AMA `unlock_ad` zaten atılmıştı → funnel şişer (unlock_coin
  ise fence'ten ÖNCE `.transactionConflict` dönüp `unlock_coin`'i bastırıyor — asimetri). **Fix:** `trackUnlockAd`
  fence-SONRASINA taşındı. TDD: hesap-switch senaryosunda unlock_ad atılMAZ (RED fence-öncesi → GREEN + revert).
- Elenen (SOUND): coin_purchase_success vs iap_credited (tasarımca ayrı, tek-atım), 409'da claim/redeem event yok,
  VIP-activation idempotent, pending double-charge guard (önceki fix), restore try? best-effort, stuck-phase yok.

### Cross-package integration seam hunt (2026-09-01)
Per-package hunt'ların kör-noktası olan uçtan-uca money/unlock yolculukları (paket sınırları). 5 journey tarandı;
paywall bypass hiçbirinde hard-yok (server authorize gate). 1 MEDIUM düzeltildi + 1 LOW ertelendi:
- **MEDIUM — VIP-tetikli UnlockSheet tamamlanması KALICI unlock sanılıp VIP-expiry re-lock'undan kaçıyordu
  (✅ DÜZELTİLDİ):** UnlockSheet açıkken VIP `onVIPActivated` ÇAĞIRMAYAN bir yoldan aktifleşirse (başka-cihaz
  StoreKit sync / transaction-observer / Ask-to-Buy renewal), sheet'in entitlement-gözlemcisi (`snapshot.isVIP`)
  `completeUnlock` → `unlockSheetDidUnlock` → `applyUnlock` → `vipGrantedEpisodes.remove` (KALICI) yapıyordu →
  bölüm revocable-setten çıkıyor → VIP lapse'inde re-lock EDİLMİYOR (feedState `.unlocked` bayat kalıp
  `PlayerPool.isPlayable` paywall'u atlıyor; server authorize backstop). In-app VIP-upsell yolunda RACE olarak da
  tetiklenebiliyordu (subscribe `await subscriptionStatus()`'ta askıdayken gözlemci applyUnlock'u önce koşar).
  **Fix:** `UnlockSheetDelegate.unlockSheetDidUnlock`'a `viaVIP: Bool` eklendi; UnlockSheetModel gözlemcisi VIP
  (viaVIP:true) vs lastUnlocked/coin/ad (false) ayırır; App `WalletFlowCoordinator` viaVIP:true → `onVIPActivated`
  (applyVIPUnlock, TÜM bölümler REVOCABLE) yönlendirir. Ek fayda: VIP-türevli açılış artık tek-E5 yerine TÜM
  bölümleri açar (VIP tüm erişim). TDD: WalletKit (viaVIP=true/false ayrımı) + App (viaVIP:true → revocable →
  expiry re-lock; RED routing'siz e1 kalıcı kalıp re-lock olmaz → GREEN + revert); 312 WalletKit + 6 App yeşil.
  (Ayrıca `applyUnlock` STALE yorumu düzeltildi: ad-unlock artık `confirmAdUnlock`'la unlockedEpisodes'a giriyor.)
- **LOW ERTELENDİ — VIP hiç sheet AÇIK DEĞİLKEN aktifleşirse feed'in mevcut kilitli kartı reaktive olmuyor:**
  kullanıcı kilitli E5'te sheet'i kapatıp kilit-karesinde kalır, sonra VIP transaction-observer'dan aktifleşir →
  `onVIPActivated` çağrılmaz (yalnız `vipSubscriptionDidActivate`'ten gelir), feed gözlemcisi yalnız RE-LOCK eder.
  Kart, kullanıcı tekrar dokunana dek kilitli kalır (sheet re-present → gözlemci isVIP replay → reactivate → SELF-HEAL).
  Küçük, geçici, para etkisi yok. Fix yönü: feed'in entitlement gözlemcisi VIP-YÜKSELİŞinde de reaktive etsin.

### Yakınsama hunt turu — WalletKit-UI + AppFoundation-primitifleri (2026-09-01)
Money-UX + eşzamanlılık-backbone taze hunt'ları. AppFoundation backbone SOUND (AsyncMulticast/SessionBroadcaster
seed-under-lock doğru; consumer'lar doğru). En yüksek para-riski bulundu+düzeltildi:
- **MEDIUM — CoinShop/VIP pending banner tap-dismiss çift-ücret guard'ını açıyor (✅ DÜZELTİLDİ):** `.pending`
  (Ask-to-Buy) `preventsNewPurchase=true` ile ikinci satın almayı bloklar AMA `acknowledgeTransientPhase` `.pending`'i
  `.idle`'a sıfırlıyordu, ve pending banner tap-dismiss'li (`onTapGesture → acknowledgeTransientPhase`) → kullanıcı
  banner'a dokununca guard açılıyor → pending'de ikinci satın alma → parent iki pending'i onaylayınca ÇİFT ÜCRET+KREDİ.
  StorePurchasePhase.swift'in kendi invariantını (pending penceresi bloklamalı) ihlal ediyordu. **Fix:** `.pending`
  `acknowledgeTransientPhase` reset-setinden çıkarıldı (CoinShop+VIP) → banner-tap guard'ı AÇMAZ; pending, işlem arka
  planda çözülene / sheet yeniden açılana (taze model — CoinShop/VIP sheet'tir → kalıcı-blok YOK) dek tutulur. TDD:
  pending→acknowledge→guard korunur, ikinci purchase BLOKLANIR (RED çift-purchase → GREEN + revert); 310 WalletKit yeşil.
- **LOW — `PlayerKit/StateBroadcast.stream()` seed'i lock-DIŞI yield ediyordu (✅ DÜZELTİLDİ):** iki para-kardeşi
  (AsyncMulticast/SessionBroadcaster) seed'i register ile aynı kilit altında yield eder (stale-seed-last yarışı önlemi);
  StateBroadcast etmiyordu. ŞU AN ulaşılamazdı (sahibi PlaybackEngine actor; subscribe+send serileşir) ama savunmacı
  hardening (subscribe ileride `nonisolated` yapılırsa canlı stale-state bug). **Fix:** seed `withLock` içine alındı +
  `onRegisteredForTesting` kancası (sibling simetriği). TDD: concurrentSendNeverLeavesStaleSeedLast (RED last==0 bayat →
  GREEN + revert); 288 PlayerKit yeşil. Artık üç primitif de aynı seed-under-lock invariantına + regresyon testine sahip.
- **LOW ERTELENDİ (WalletKit-UI diğer):** (a) CoinShop `firstTopUpEligible` satın-alma sonrası re-fetch etmiyor →
  Profil kaynağında 2x banner bayat kalır (para kaybı yok, UI over-promise; küçük fix: purchase sonrası catalog
  refresh). (b) win-back indirimli fiyat purchase-offer'dan decoupled — bugün TODO'yla maskeli, "iki TODO'yu birlikte
  wire et" uyarısı (bkz StoreKitProductService). (c) tek-yön `isDisposed` retained-instance'ta recovery engeller —
  mevcut sheet-per-sunum kullanımında güvenli, latent. Optimistik-kredi/double-tap/StoreKit-interruption hepsi SOUND.

### Yakınsama hunt turu — PlayerKit-feed + ProfileKit (2026-09-01)
Loop-until-dry yakınsama kontrolü: iki taze bağımsız-context hunt. Paywall bypass İKİSİNDE DE doğrulandı-yok.
- **MEDIUM — auto-advance uçuştaki manuel swipe'ı ezip yanlış bölüme fırlatıyor (✅ DÜZELTİLDİ):** kullanıcı
  bölüm sonuna yakınken BAŞKA karta (bitişik-olmayan/geri) flick attığında, deceleration sırasında aktif bölüm
  sonuna ulaşırsa `handlePlaybackEnded` bayat `activeIndex`'ten `.advance(active+1)` üretiyor, VC `execute` bunu
  guard'sız `scrollToItem(animated:)` ile uygulayıp kullanıcının kaydırmasını EZİYORDU → kullanıcı hedef yerine
  active+1'e düşüyor (bölüm-sonu-swipe short-drama'da çok yaygın). **Fix:** `performRecordSwipeIntent`'te gerçek
  swipe (guard `fromIndex != toIndex`) `suppressNextAutoAdvance = true` set eder (seek-suppress mekanizmasını
  yeniden kullanır); settle yeni bölümde sıfırlar; aynı-yere bounce guard'a takılır → auto-advance korunur. TDD:
  swipe→advance-yayınlanmaz (box boş) + bounce→normal-advance (RED box=[.advance(1)] → GREEN + revert); 286 PlayerKit yeşil.
- **LOW ERTELENDİ — `updateItems` handle-nil'de (kilitli/promo/failed) activeIndex re-derive etmiyor:** aktif kart
  handle taşımıyorsa (`activeHandle==nil`) feed reorder'ında hem `activeIndex` hem konumsal `notifiedLockedIndex`
  bayat kalır → nadir mid-feed reorder'da yanlış idempotent-skip/prefetch-yön/from_episode_id. NADİR (server
  append-only sayfalama) + self-healing (sonraki settle re-derive eder). Tam fix, handle'dan bağımsız active-episode-id
  saklamayı + `notifiedLockedIndex`'i id-tabanlı yapmayı gerektirir (paywall-bitişik idempotency guard'ına dokunur)
  → LOW+self-healing+nadir için o riske değmez; ertelendi (F2 feed-reorder gelirse revize).
- **LOW KABUL (ProfileKit, ulaşılamaz) — markRead telafisi eşzamanlı-başarılı markAllRead'i ezebilir:** yalnız
  TEORİK interleaving — `handleTap` markRead'i başlatıp HEMEN `model.open` ile navigate eder → notification center
  kapanır, "tümünü okundu say" barı erişilemez olur → gerçek UI'dan tetiklenemez. Ayrıca display-only + self-healing
  (sonraki load düzeltir) + tam-doğru fix orantısız (çift-fail ters drift). Kabul; gerçek risk yok. ProfileKit aksi
  halde reachable-bug'sız (wallet-display, hesap-akışları, notification fence'leri, ayarlar hepsi sağlam doğrulandı).

### App-integration adversarial bug-hunt (2026-09-01)
App/ katman glue'su (coordinators/DI/composition/playback-seed/account-switch) hunt: çekirdek çok iyi
korunmuş (VIP re-lock, account-switch fence'leri, deep-link doğrulama, seed generation-guard). 1 MEDIUM
düzeltildi + 1 LOW beklemede:
- **MEDIUM — cross-account continue-watching leak (eager reload, ✅ DÜZELTİLDİ):** `HomeCoordinator.resetForAccountSwitch`
  `continueEntry.reset()` sonrası EAGER `Task { continueEntry.load() }` yapıyordu. Reset, switch'in `linkSession`
  yayınında (deleteAll+refetch'ten ÖNCE) tetiklendiğinden, yerel-first load A'nın HENÜZ SİLİNMEMİŞ kaydını okuyup
  B'nin Ana Sayfa banner'ına A'nın dizisini basıyordu (tıklayınca A'nın bölümüne gider). ListemModel/KesfetModel'in
  "reset'te reload YAPMA — A'nın verisini diriltir" kuralının tam ihlali. **Fix:** eager load kaldırıldı; B'nin
  devam-kaydı refetch sonrası doğal view `.task`'ıyla yüklenir. TDD (App): A kaydını seed → switch → banner A'yı
  GERİ OKUMAZ (RED→GREEN + revert doğrulandı — leak reprodüksiyonu). 5 AccountSwitchFeedResetTests yeşil, App derleme OK.
- **LOW — resolver `intent.episodeID`'yi üyelik doğrulamadan güveniyordu (✅ DÜZELTİLDİ):** `targetEpisodeID`
  (`PlaybackFeedSeed.swift`) `intent.episodeID`'yi yüklü `episodes`'ta olup olmadığını KONTROL ETMEDEN dönüyordu.
  Bölüm kaldırılmış / `maxEpisodePages`(8) ötesindeyse var-olmayan bölüme işaret eden `FeedEntry` üretiyordu →
  PlayerKit episode 1'e düşüyor AMA kaldırılan bölümün resume pozisyonuyla. `episodeNumber` yolu zaten
  `firstPlayable`'a düşüyordu (asimetri). **Fix:** episodeID üyelik doğrulaması (simetrik) + fallback'te (hedef
  çözülemedi) `makeEntry`'ye pozisyon 0 override → yanlış bölümde ortadan başlama yok. TDD (App): absent-ID→nil +
  removed-ID→firstPlayable@0 (RED 3 hata → GREEN + revert). 20 PlaybackFeedSeedTests yeşil. Paywall etkisi yoktu.

### RewardsKit adversarial bug-hunt (2026-09-01)
OdulMerkezi/Referral/ad-reward hunt: çekirdek olağanüstü sertleştirilmiş (in-flight claim guard, accountEpoch fence,
checkInGeneration fence, version-monotonic bakiye guard, task eventual-consistency reconcile). 1 MEDIUM düzeltildi:
- **MEDIUM — check-in claim post-claim pin eksik (✅ DÜZELTİLDİ):** generation-guard YALNIZ claim-anında UÇUŞTA
  olan status()'ü düşürür. Claim-SONRASI başlayan warm `refreshCheckIn` post-claim generation'ı yakalar → fence
  GEÇER; server read-replica bayat pre-claim status (todayClaimed=false, düşük streak) dönerse buton geri açılır +
  sahte `checkin_streak_break` + `lastSeenStreak` bozulur. Task-tarafı `reconcileClaimed` (Fix 4) pini vardı,
  check-in'de yoktu. **Fix:** `checkInClaimedPin` — claim'de set, `applyLoadedState`'te bayat pre-claim downgrade'i
  düşür, server `todayClaimed=true` onaylayınca düş (monoton; günlük-reset korunur), account-switch'te temizle.
  TDD: claim → warm refresh bayat pre-claim → streak/buton/lastSeenStreak/streak_break korunur (RED→GREEN + revert).
  - **REGRESYON DÜZELTMESİ (money-core regresyon hunt, MEDIUM):** ilk pin GÜN-KÖR Bool'du → uygulama gece-yarısını
    warm geçerse gün-2'nin MEŞRU pre-claim state'i (todayClaimed=false) "bayat downgrade" sanılıp düşürülüyor,
    gün-2 claim butonu cold-launch'a dek kilitleniyordu (kayıp coin). İlk test hep-bayat gate kullandığından bu
    gün-kör davranışı doğru sanıp kilitliyordu. **Fix:** pin `Bool` → `Int?` (claim-anı streakDays); reconcile
    GÜN-FARKINDALIKLI — yalnız `state.streakDays < claimedStreak` (bayat=DÜŞÜK streak) düşürülür; yeni gün
    (streak korunur, todayClaimed=false) VEYA server onayı → pin düşer, gün-2 açık. cycleDay=((streak-1)%7)+1 olduğundan
    streakDays doğru diskriminatör. TDD: gün-2 claim bloklanmaz (RED gün-kör → GREEN + revert) + orijinal same-day-stale
    testi korunur. **Meta-ders TEKRAR: money/entitlement fix'lerinde bağımsız-context adversarial pass ŞART** — bu
    regresyonu self-review + per-fix test kaçırdı, bağımsız hunt yakaladı (kaydedildi [[autonomous-dev-plan]]).
    - **KABUL EDİLEN KALINTI (KIRIK-STREAK gün-2):** streakDays diskriminatörü, gün-2'de streak KIRILMIŞSA (server
      streak'i 0/1'e resetler < claimedStreak) meşru yeni-döngü claim'ini de düşürür. Ama konjonktür aşırı nadir:
      gün-1'de claim + o gün Ödüller'e HİÇ dönmeme (yoksa todayClaimed=true refresh pini düşürür) + uygulamayı gece-
      yarısı boyunca warm tutma + gün-2 claim penceresini kaçırma; cold-launch'ta kendini iyileştirir. Tam çözüm
      CheckInState'te tarih alanı (veya kaçınılan cihaz-saati) gerektirir → kabul, F2 backend'de tarih alanı gelirse
      revize edilir. Gün-kör Bool bu durumu ZATEN bloklıyordu → fix onu KÖTÜLEŞTİRMEZ (yalnız yaygın-durumu düzeltir).
- **LOW REDDEDİLDİ (naif fix regresyon) — resetForAccountSwitch isClaiming/claimingTaskID temizlemiyor:** hunt
  "reset'te temizle" önerdi AMA `claimTask`/`claimToday` defer'leri GUARD'SIZ (`defer { claimingTaskID = nil }`).
  Naif temizleme → A'nın uçuştaki claim'i, switch sonrası B'nin YENİ claim marker'ını mid-flight ezip çift-claim
  guard'ını bypass ettirir (regresyon). Mevcut davranış FAIL-CLOSED + self-healing (leaked marker B'yi geçici
  bloklar, defer saniyeler içinde temizler — hunt de LOW/kozmetik dedi). Doğru fix epoch-guard'lı defer gerektirir
  (para-claim koduna orantısız risk) → bilinçli no-op, mevcut fail-closed davranış kabul.
- **LOW — Referral redeem WalletStore refresh sinyali yok (✅ DÜZELTİLDİ):** `ReferralModel.redeem` `.credited` kolu
  cüzdanı server'da kreditler ama OdulMerkezi kalıbındaki (`delegate.rewardsDidCreditBalance()`) sinyali GÖNDERMİYORDU
  → redeem sonrası Profil/CoinShop başlığı bayat (DÜŞÜK) bakiye gösteriyordu. Yön zaten GÜVENLİ (optimistik kredi
  DEĞİL). **Fix:** `ReferralDelegate.referralDidCreditBalance()` eklendi, `.credited`'te çağrılır (conflict/hatada
  DEĞİL), App `RewardsCoordinator` `walletStore.refresh()`'e bağlar. TDD: credited→sinyal 1 / conflict→0 (RED→GREEN
  + revert); 161 RewardsKit yeşil, App derleme OK. Elenen: çift-claim/optimistik-kredi/ad-reward/account-leak hepsi
  kodda doğrulanıp güvenli bulundu.

### LibraryKit/App favori-dokunuş resume (LATENT — progress-sync canlıya alınınca düzelt)
LibraryKit adversarial hunt bulgusu (MEDIUM ama F1'de ulaşılamaz → düzeltme progress-write/sync bağlanınca):
- **App/Coordinators/LibraryCoordinator.swift `listemPlaySeries` (satır 85-98):** favori-dokunuş, `latestProgress
  (forSeries:)`'in HAM kaydını kullanıp `record.completed`'ı YOK SAYIYOR → son izlenen bölüm tamamlanmışsa o bölümü
  bitiş konumundan seed ediyor. Kanonik davranış (DiziDetay `ContinueWatchingTarget.resolve`) completed → SONRAKİ
  bölüm (konum 0; yayınlanmış son bölümse aynı bölümde kalır). Favori-dokunuş yolu bu dalı uygulamıyor.
- **Neden latent:** yerel `recordProgress` yazma yolunun üretimde HİÇ çağrısı yok (player progress yazmıyor) +
  sunucu-merge (`mergeServerProgress`) prep-bekleyen backend'e bağlı → completed kayıt şu an `latestProgress`'e
  ulaşamaz. Bug ancak progress-write/sync canlıya alınınca tetiklenir.
- **Doğru fix (o zaman):** koordinatör `WatchProgressRecord` episode-index TAŞIMADIĞINDAN "sonraki bölüm"ü tek
  başına türetemez → dizi bölüm listesini çekip kanonik `ContinueWatchingTarget.resolve`'u kullanmalı (veya en az
  completed iken bitmiş bölümü seed etmemeli). DiziDetay `ensureProgressEpisodeLoaded` "episodeId-resume" prep
  notuyla (satır 188) aynı dilimde ele alınmalı.

### DiscoverKit adversarial bug-hunt (2026-09-01)
DiziDetay/Arama/Kesfet hunt: çekirdek olağanüstü sertleştirilmiş (unlock server-otoriter — DiscoverKit optimistik
bakiye/erişim YAZMAZ; arama/revalidate/recomputeAccess generation-fence'li; sayfalama dedup/empty-cursor guard'lı).
1 MEDIUM düzeltildi:
- **MEDIUM — `ensureEpisodeLoaded` boş-sayfa cursor guard'ı eksik (✅ DÜZELTİLDİ):** `recompute()` CTA hedef
  bölümünü ileri sayfalarken sunucu `Page(items:[], nextCursor:"pN")` dönerse cursor nil'lenmez → döngü sınırsız
  fetch + `load()` kalıcı `.loading`. Kardeşleri (load:136/ensureProgress:191/loadMore:339) `items.isEmpty ? nil`
  guard'ına sahipti, `ensureEpisodeLoaded:204` değildi. **Fix:** simetrik `page.items.isEmpty ? nil : page.nextCursor`.
  TDD: completed-progress → hedef sonraki-sayfada + boş-sayfa dönen-cursor → "p3" HİÇ istenmez (RED→GREEN + revert).
- Elenen adaylar (gerçek bug değil): AramaModel.performSearch empty-guard asimetrisi (`.noResult` fazında
  cursor/loadMore kullanılmaz), isLoadingResults sızıntısı (yalnız non-.results fazında, görünmez), DiziDetay/Arama
  resetForAccountSwitch yokluğu (push-scope modeller, App teardown eder), çift-tap unlock intent (DiscoverKit'te
  harcama yok — WalletKit/coordinator sahibi). Hepsi kodda doğrulanıp elendi.

### WalletKit ad-unlock §575 epoch-fence (self-review, 2026-09-01)
Kendi eklediğim para-çekirdeği kodunun (reklam-unlock entegrasyonu, 1177899/11f8314) adversarial öz-incelemesi
— meta-ders: money-core eklemeleri epoch-fence'i atlayabilir. Bulunan + düzeltilen:
- **MEDIUM — ad-unlock confirm epoch-fence'siz (cross-account leak, ✅ DÜZELTİLDİ):** `WalletStore.confirmAdUnlock`
  senkron + epoch-guard YOK. Reklam-watch (≈30 sn + SSV) uçuştayken hesap değişirse (session-death → `reset()`,
  epoch++, `unlockedEpisodes` temizlenir), reklam biter bitmez onay ÖNCEKİ hesabın bölümünü yeni epoch'a yazar +
  entitlement yayınlar. Coin `unlock()` yolu bu fence'e sahipti (satır 192/201), ad-unlock yolu değildi — §575
  sınıfının tek deliği. PurchaseCoordinator precedent'i (`currentEpoch()` await-öncesi + `applyIfCurrentEpoch`)
  ile simetrik **Fix:** `confirmAdUnlock(episodeID:ifCurrentEpoch:) -> Bool` (epoch uyuşmazsa DÜŞ + false),
  `WalletGateway.currentEpoch()` eklendi, `UnlockSheetModel.watchAd` reklam ÖNCESİ epoch yakalar + onay düşerse
  `completeUnlock` ETMEZ (coin-path simetrisi). TDD: WalletStore-seviye (2 test, revert-verify RED) + UI-seviye
  (watchGate ile hesap-switch simülasyonu, revert-verify RED); 308 WalletKit yeşil.

### PlayerKit engine/pool adversarial bug-hunt (2026-09-01)
Playback engine + PlayerPool internals hunt: çoğu clean (activeIndex id-re-derive, KVO removal, generation-guard,
dedup/claim-before-await SAĞLAM). 2 slot-koruma bulgusu düzeltildi + 2 LOW accepted:
- **#1 activate demote await'inde slot korumasız (MEDIUM — ✅ DÜZELTİLDİ):** `acquire` defer'i lease slotunun
  `isAuthorizing`'ini temizler + slot henüz `activeSlot` değil → `demotePreviousActive` await'inde eşzamanlı warm
  `reclaimableSlot` onu geri alıp BAŞKA bölüm yükleyebilir (aktif kart yanlış video). **Fix:** demote boyunca
  `isAuthorizing=true` (dosyanın acquire/reuseWarmSlot deseniyle birebir), `activeSlot` yazılınca aç.
- **#2 recycle isAuthorizing slotları hariç tutmuyordu (LOW — ✅ DÜZELTİLDİ):** `recycle` yalnız `activeSlot`'u
  atlıyordu (`reclaimableSlot` isAuthorizing'i de hariç tutar) → uçuştaki warm'ın claim'i prepare ortasında
  temizlenip öksüz buffering. **Fix:** `where index != activeSlot && !isAuthorizing`. TDD: recycleUcustakiWarm
  SlotunuTemizlemez (gated warm + recycle → slot korunur) RED→GREEN + revert-verify; 284 PlayerKit yeşil.
  (#1 2-satırlık invariant-match: no-regression + #2'nin isAuthorizing-exclusion kanıtıyla doğrulandı; deterministik
  demote-race testi full-pool+gated-pause gerektirir → dar yarış için orantısız.)
- **#3 mid-playback `.failed` yüzeylenmiyor (LOW, ACCEPTED):** `statusUpdates()` tüketicisi yok → aktivasyon-sonrası
  hata sessiz donuk kare. Sınıflı hata-UI SS-051 (belgeli gelecek dilim) → accepted.
- **#4 entitled/VIP premium bölümlerde prefetch yok (LOW, ACCEPTED):** `lockedIndexes` yalnız access-kind'dan (sync
  policy entitlement await edemez) → VIP-owned kilitli bölüm cold-start. Bilinçli sadeleştirme (403 gürültüsü) → accepted.

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
- **VIP-expiry/iade IN-SESSION re-lock (HomeCoordinator, MEDIUM CONFIRMED — ✅ DÜZELTİLDİ 2026-08-31):**
  Kullanıcı VIP/coin bölüm izlerken abonelik iade/expire olursa `WalletStore.hasAccess` false'a döner ama feed
  client-optimistik `.unlocked` işaretini (FeedUnlockReducer `episode.unlocked()`) KORUYORDU → `PlayerPool.isPlayable`
  `.unlocked`'a (`isPlayableWithoutUnlock`) güvenip hasAccess'i SORMAYIP paywall'u bypass ediyordu → komşu kartlar
  feed-reload'a dek oynatılabilir kalırdı (gelir sızıntısı). **Kök (derin araştırma):** `WalletStore.unlockedEpisodes`
  OTURUM-YEREL (applyWallet sunucudan doldurmaz; geçmiş ownership CATALOG `.unlocked` access'inde) → naif "isPlayable
  `.unlocked` için hasAccess sorsun" fix'i geçmiş-oturum satın-almasını FALSE-LOCK ederdi. **Fix (829f... sınıfı):**
  HomeCoordinator client-optimistik unlock'ları izler (`clientOptimisticUnlocks`; applyUnlock/applyVIPUnlock ekler) +
  entitlement-DÜŞÜŞÜ gözlemcisi (`WalletGatewayEntitlementChangeObserving`) → izlenenlerden `hasAccess`=false olanları
  `FeedUnlockReducer.revertingRevokedUnlocks` ile `.locked`'a döndürür. Katalog-historik `.unlocked` İZLENMEZ →
  false-lock yok. Cross-account fence (revoked ∩ güncel izleme). Aktif oynayan video KESİLMEZ (updateItems handle'ı
  korur; yalnız görsel overlay + re-aktivasyon gate'lenir → north-star korunur; "iade in-session erişimi geri almaz"
  ile uyumlu). TDD: FeedUnlockReducerTests (revert reducer, 7 test) + HomeFeedRevokeRelockTests (wiring, 3 test) —
  RED→GREEN + 2 revert-verify (revert-apply + false-lock gate); 256 App testi yeşil. App CI-dışı → yerel doğrulandı.
  - **REGRESYON DÜZELTMESİ (adversaryal-hunt yakaladı, self-review KAÇIRDI):** ilk fix `applyUnlock` (bireysel coin/
    reklam unlock) bölümlerini de izliyordu; reklam-unlock `WalletStore.unlockedEpisodes`'a girmez (oturum-yerel,
    yalnız coin path) → `hasAccess`=false → re-verify onları YANLIŞ re-lock ediyordu (hak edilmiş reklam-kilidi paywall'a
    döner). Kök: bireysel unlock KALICI (server-kayıtlı), yalnız VIP-grant REVOCABLE. **Fix:** izleme kümesi
    `clientOptimisticUnlocks`→`vipGrantedEpisodes` (yalnız applyVIPUnlock izler; applyUnlock KÜMEDEN ÇIKARIR). TDD:
    testIndividuallyUnlockedEpisodeIsNotRelocked (RED→GREEN + revert-verify); 265 App testi yeşil.

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

### DiscoverKit adversarial bug-hunt — ertelenen 1 kalem (2026-08-31)
DiscoverKit bug-hunt (14 agent → 9 doğrulanmış). 6 CI-testli fix DÜZELTİLDİ (commit 3854329 + self-review
f327339: recent-search newline, loadMore sonsuz-sayfalama, öneri bayat/boş/ağ-hatası, CTA kilit-etiketi, load
guard). **#2 (entitlement-gözlem) + #9 (DiscoverSessionStore cross-account) sonradan DÜZELTİLDİ (2026-08-31, ✅).**
Kalan 1 ertelenen kalem (#3 episodeId-resume, aşağıda):
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
  **Follow-up (LOW latent, holistik self-review) → ✅ DÜZELTİLDİ:** `recomputeAccess()` fence'siz + H3 fix'inin
  `ctaTarget!=nil` guard'ının yan-sonucu olarak 2 eşzamanlı çağıranı vardı (load'un recompute'u + entitlement
  gözlemcisi). Out-of-band entitlement değişimi sub-saniye İLK-load sırasında (ctaTarget kurulduktan sonra) gelirse
  iki recomputeAccess per-episode `hasAccess` loop'unda interleave eder; load'un BAYAT (pre-unlock) yazımı SON
  inerse açılmış hedef CTA 🔒 kalırdı (#2'nin kapattığı bug'ın çok-dar kalıntısı). Fix: `accessRecomputeGeneration`
  (recomputeAccess başında bump/capture, final atamalardan ÖNCE guard → son-BAŞLAYAN kazanır; loadFavorites/
  revalidateGeneration deseni). Deterministik interleave testi (per-call-gated `GatedEntitlements`: ep4 hasAccess
  1. çağrısı bloklu → A ve B'yi interleave ettirir; B'nin ep3→.current commit'i beklenir, A serbest bırakılınca
  bayat yazımı fence'le düşer) revert-verify RED-doğrulandı. DiscoverKit 154 test yeşil; file_length ≤400 (yorum
  kırpma). NOT: ilk poll `ctaLocked`'a bakıyordu (default false → A/B senkronize etmiyordu) → `cellState==.current`e
  düzeltildi (B'nin gözlemlenebilir etkisi).
- **#9 DiscoverSessionStore cross-account (LOW CONFIRMED, App coordinator reset) → ✅ DÜZELTİLDİ:** Discover
  SessionStore + KesfetModel sekme ömrü boyu yaşar, DiscoverCoordinator (Home/Rewards/Library'nin AKSİNE)
  hesap-switch gözlemcisi YOKTU → A'nın per-user `/discover` layout'u (`private, max-age=600` cache) + seçili tür
  filtresi B'ye sızıyordu. Fix: DiscoverSessionStore.reset() + KesfetModel.resetForAccountSwitch() (content/
  selectedGenreID/session temizler, revalidateGeneration bump ile uçuştaki discover() commit'ini fence eder,
  loadState=.idle → onAppear guard'sız reload) + DiscoverCoordinator.startObservingAccountSwitch (4. tab-coordinator,
  pattern tamamlandı). 3 test (state-clear + uçuştaki-revalidate fence — bağımsız revert-verify RED + App-wiring
  loggedOut-ara-durum). DiscoverKit 153 test + App 2 test yeşil. Reload BURADA yapılmaz (reset stateUpdates'te
  switch-token rotasyonundan önce → A layout'u dirilmesin; onAppear post-switch reload eder).

### WalletKit (para-çekirdeği) adversarial bug-hunt — ertelenen 1 kalem (2026-08-31)
Para-DURUMU sağlam savunulmuş (version-monotonic SET, account-epoch fence, iki-katman IAP idempotency,
authoritative re-read, decode fail-safe) → HIGH para-bozulması YOK. 2 kusur DÜZELTİLDİ, 1 ertelendi:
- **#1 AsyncMulticast seed sıra-bozması (MEDIUM CONFIRMED) → ✅ DÜZELTİLDİ (commit 0818438):** seed kilit
  DIŞINDA yield ediliyordu → eşzamanlı send() araya girip aboneyi [V_yeni, V_eski] besliyor, bayat kalıyordu
  (versiyonsuz display: profil özeti, CoinShop/UnlockSheet bakiye, VIP bayrağı). Seed kilit altına alındı;
  çok-abone×burst yarış testi (RED→GREEN).
- **#2 unlock() defer başka hesabın pendingUnlock marker'ını siler (LOW CONFIRMED) → ✅ DÜZELTİLDİ:** mid-flight
  reset + reentrant unlock'ta koşulsuz `defer { pendingUnlock = nil }` başka bölümün marker'ını siliyordu (≤1
  bekleyen unlock invariantı düşer; RED'de 3. unlock diğerinin uçuştaki sonucunu bile çaldı). defer artık yalnız
  kendi episodeID'sini temizler; deterministik iki-gate reentrancy testi (RED→GREEN).
- **#3 subscription monotonluğu opsiyonel `updatedAt`'e bağlı (LOW PLAUSIBLE, server-sözleşmesi):** wallet
  snapshot'ı her zaman `version` (Int) taşırken subscription yalnız HEM mevcut HEM gelen `updatedAt` varsa
  bayat-drop yapar; server `updatedAt` göndermezse son-yazan-kazanır → iki eşzamanlı refresh out-of-order
  dönerse bayat non-VIP taze VIP'i geçici EZER (erişim server-otoritatif → UI flicker, kayıp entitlement yok).
  **Fix server-garantili monoton alan gerektirir** (subscription için `version` paritesi) → server-sözleşmesi
  ertelenen; kod-tarafı guard zaten mevcut fallback'i belgeliyor.

### RewardsKit (para-bitişik) adversarial bug-hunt — ertelenen 2 kalem (2026-08-31)
Para-korrektlik her yerde sağlam (version-monotonic balance guard, account-epoch fence, server-otoriter claim/
redeem, rewarded-ad nonce/SSV → istemci ASLA kredi vermez) → HIGH/MEDIUM para bug'ı YOK. 1 cross-account kusur
DÜZELTİLDİ, 2 LOW ertelendi:
- **#1 ReferralModel hesap-değişiminde reset edilmiyor (MEDIUM CONFIRMED, cross-account) → ✅ DÜZELTİLDİ:**
  RewardsCoordinator yalnız odulMerkeziModel'i reset ediyordu; sibling referralModel (coordinator ömrü boyu
  yaşar) reset+epoch-fence'siz → A'nın davet kodu/sayaçları + "+50 coin kazandın" redeem-başarı mesajı hesap-
  switch sonrası B'ye sızıyordu (para etkisi YOK — redeem server-otoriter). Fix: ReferralModel'e accountEpoch
  fence (load/redeem await-öncesi yakala, apply-öncesi guard) + resetForAccountSwitch() (odulMerkezi mirror);
  RewardsCoordinator switch'te ikisini de reset eder. 2 TDD testi (reset-clear + uçuştaki-load fence), her ikisi
  bağımsız revert-verify RED-doğrulandı. RewardsKit 156 test yeşil, App derlendi.
- **#2 OdulMerkeziModel reset sonrası .loading'de takılabilir (LOW PLAUSIBLE, savunmacı):** resetForAccountSwitch
  loadState=.loading yapar ama reload BAŞLATMAZ — reload onAppear'a bağlı. Rewards sekmesi switch sırasında
  sürekli görünür kalırsa (view disappear/reappear yok) sonsuz spinner. Pratikte switch login/Profil'den geçer →
  view re-appear → onAppear reload; bu yüzden LOW. **Fix (opsiyonel):** resetForAccountSwitch sonunda
  startRefreshIfIdle() tetikle (view-lifecycle'a bağımlılığı kaldır). Aynı desen ReferralModel'de de var (onAppear
  reload; referral pushed sub-screen olduğundan switch'te görünür olması daha da olası değil).
- **#3 RewardedAdService.watchAdToUnlock single-flight guard yok (LOW PLAUSIBLE, server-mitigated):** çift-dokunuş
  iki showAd→requestAdUnlock sürebilir; ASLA istemci-kredi vermez (server-side), her proof ayrı one-time nonce
  taşır → server SSV çift-krediyi engeller. Serileştirme UI'a (UnlockSheet butonu isLoading disable) bağlı. **Fix
  (opsiyonel):** service'e in-flight bayrağı.

### LibraryKit (izleme-geçmişi/favoriler) adversarial bug-hunt — ertelenen 2 kalem (2026-08-31)
FavoritesService reentrancy/optimistik-toggle/telafi-DELETE + ListemModel generation-guard'ları sağlam ve
testli. 1 HIGH cross-account + 1 MEDIUM lossy-decode DÜZELTİLDİ, 2 LOW ertelendi:
- **#1 ListemModel hesap-değişiminde reset edilmiyor (HIGH CONFIRMED, cross-account) → ✅ DÜZELTİLDİ:**
  LibraryCoordinator'da (Home/Rewards'ın aksine) HİÇ account-switch observer'ı yoktu; ListemModel (coordinator
  ömrü boyu yaşar) reset+epoch-fence'siz → A'nın favorileri/"devam et"/gizli-öğeleri hesap-switch sonrası B'ye
  SIZIYORDU (kullanıcının ÖZEL izleme verisi). Fix: ListemModel.resetForAccountSwitch() (favorites/continueItems/
  hiddenEpisodeIDs/loadedSegments temizler, state=.loading, favorites/continue generation bump ile uçuştaki
  load'u fence eder, appeared=false → reload onAppear/.task ile); reload BURADA yapılMAZ (reset stateUpdates'te
  repo refetch'inden ÖNCE tetiklenir — b<c<d — yüklersek A'yı diriltirdik). LibraryCoordinator.startObserving
  AccountSwitch (Home/Rewards mirror) switch'te reset eder. 3 test (state-clear + uçuştaki-load fence + App-wiring),
  paket testleri bağımsız revert-verify RED-doğrulandı. LibraryKit 70 + App 2 test yeşil.
- **#2 History wire STRICT array decode: tek bozuk eleman tüm cross-device geçmiş merge'ini düşürür (MEDIUM
  PLAUSIBLE) → ✅ DÜZELTİLDİ:** `HistoryListWire.items` strict idi → tek bozuk kayıt tüm sayfa decode'unu fail
  ediyordu → `synchronize()` `.decoding`'i yüzdürür → caller'ların `try?`'ı yutar → cross-device "devam et"
  sessizce hiç güncellenmezdi (all-or-nothing). ContentKit lossy-decode (commit 7b3bac9) ile AYNI sınıf. Fix:
  `HistoryListWire`'a custom `init(from:)` + self-contained `SkippableProgress` (eleman-bazlı lossy: bozuk kayıt
  atlanır, kalanı akar; array-değil/eksik → []). ContentKit LossyArray App'ten import edilmediğinden yerel.
  App TDD testi (bozuk durationSec atlanır, 2 geçerli kalır) revert-verify RED-doğrulandı.
- **#3 fetchServerProgress pagination stuck-cursor yok (LOW — ✅ DÜZELTİLDİ 2026-08-31):** değişmeyen non-empty
  cursor 50 kez aynı sayfayı çekiyordu (maxHistoryPages cap infinite-loop'u önler; mergeServerProgress episodeID
  upsert dedup'lar → boşa round-trip, bozulma değil). **Fix (uygulandı):** loop'a `if next == cursor { break }` —
  cursor İLERLEMEDİYSE dur (normal advance/nil-terminate bozulmaz: nil != son non-nil cursor). TDD:
  WatchProgressPaginationTests (stuck→2 istek [fix'siz 50], single-page→1 istek) RED→GREEN (RED=pre-fix 50 = revert-
  verify); 262 App testi yeşil. episodeID dedup zaten mergeServerProgress'te (downstream) → ayrıca gerekmedi.
- **#4 ContinueWatchingService.synchronize coalescing guard yok (LOW — ✅ DÜZELTİLDİ 2026-08-31):** `guard !isSyncing`
  örtüşen çağrıyı DÜŞÜRÜYORDU → switch refetch'i görünür Listem sync'iyle çakışırsa B'nin pull'u atlanabilir (bayat
  veri; switch sıralı → pencere dar). **Fix (uygulandı):** FavoritesService `needsResync` coalescing deseni mirror'landı
  (`guard !isSyncing { needsResync=true; return }` + `repeat { needsResync=false; sync } while needsResync`). TDD:
  ContinueWatchingServiceTests.synchronizeCoalescesOverlappingCallInsteadOfDropping (upload-await'inde reentrant
  synchronize → fetch 2 kez [fix'siz 1]) RED→GREEN; 71 LibraryKit testi yeşil (reentrant-write testi korunur:
  recordProgress needsResync set etmez).

### ProfileKit adversarial bug-hunt — ertelenen 1 kalem (2026-08-31)
ProfilModel switch-anı account/wallet stream-türetimi + HesapBaglama state-machine + NotificationCenter
optimistik/tombstone/fence sağlam ve testli. 1 MEDIUM load-path + 1 MEDIUM sheet-dismiss DÜZELTİLDİ, 1 LOW ertelendi:
- **#1 ProfilModel.load() sessionExpired cüzdan-clear guard'ını kaçırıyor (MEDIUM CONFIRMED) → ✅ DÜZELTİLDİ:**
  SS-132 fix'i `if account.isSessionExpired { wallet = .empty }` guard'ını observeSession/observeWallet'e ekledi ama
  load()'a EKLEMEDİ → session-death sonrası Profil İLK açılışında load() `account=sessionExpired` ama koşulsuz
  `wallet=currentSummary()` (WalletStore session-death'te reset edilmez → A'nın 500 coin+VIP'i) yazıp `.loaded`
  render ediyordu → "yeniden giriş" ekranında bayat cüzdan bir frame görünürdü (stream'ler birkaç async-hop sonra
  temizler). Fix: load() da `account.isSessionExpired ? .empty : currentSummary()` (stream guard'larıyla simetrik).
  TDD testi (load-into-loggedOut → wallet boş, izole) revert-verify RED-doğrulandı; ProfileKit 165 test yeşil.
- **#2 Yıkıcı/uçuştaki hesap sheet'lerinde interactiveDismissDisabled yok (MEDIUM CONFIRMED) → ✅ DÜZELTİLDİ:**
  HesapSilme `.deleting` / HesapBaglama `.linking|.switching` sırasında "Vazgeç" `.disabled(isBusy)` + `dismiss()`
  guard'ı vardı AMA swipe-to-dismiss coordinator binding'i üzerinden ikisini de baypas edip modeli nil'liyordu
  (App Store 5.1.1(v) koruması: geri-alınamaz silme/switch arka planda tamamlanırken sheet sessizce kapanmasın).
  Fix: iki ProfileKit view'una `.interactiveDismissDisabled(model...isBusy)` (view internal isBusy'ye erişir; yeni
  public API yok). View-katmanı (unit-test edilemez — swipe modeli baypas eder), App derleme + ProfileKit build ile
  doğrulandı.
- **#3 AccountServiceAdapters.link() userID-koruma guard'ı yok (LOW PLAUSIBLE, defense-in-depth — ✅ DÜZELTİLDİ
  2026-08-31):** link() `.linked`i sıfır-kayıp kabul edip userID korunduğuna GÜVENİYORDU; uyumsuz `/auth/link`
  farklı userID'li `.linked` dönerse coordinator'lar modelleri reset eder ama WalletStore + repo'lar YIKILMAZ →
  cross-account bakiye/entitlement sızıntısı (uyumlu backend'de erişilemez). **Fix (uygulandı):** link() `.linked`
  dalında pre-link `session.state.userID` yakalanır; dönen `credentials.userId` farklıysa plain activate yerine tam
  switch-lifecycle (flush→activate→reset→refetch + WalletStore reset). Happy-path (aynı userID → else = orijinal
  activate) değişmez. TDD: AccountSwitchDataFlowTests (mismatch→[flush,reset,refetch]; same-id→[] happy-path korunur)
  RED→GREEN; 264 App testi yeşil, full-repo lint temiz. App CI-dışı → yerel doğrulandı.

### App-integration (routing/coordinator) adversarial bug-hunt — ertelenen 2 kalem (2026-08-31)
Session-stream fan-out, lazy-model force-init, contextual-playback seed ordering, universal-link/cold-start
routing sağlam. 1 MEDIUM nav-leak + 1 LOW seed-cancel DÜZELTİLDİ, 2 LOW ertelendi:
- **#1 Hesap-switch model'leri reset ediyor ama koordinatör nav-PATH'ini temizlemiyor (MEDIUM CONFIRMED) →
  ✅ DÜZELTİLDİ:** HomeCoordinator switch'te `path = NavigationPath()` yapar ama bu seansda eklenen Discover/
  Library observer'ları YALNIZ model reset ediyordu; Profile'ın observer'ı hiç yoktu → A'nın pushed DiziDetay'ı
  (Discover/Library) / Ayarlar-BildirimMerkezi'si (Profile) hesap-switch sonrası B'ye taşınıyordu (B, A'nın
  ekranında açılıp Geri'ye basmak zorunda; nav-pozisyon + BildirimMerkezi hesap-özel). Fix: Discover/Library
  observer'larına path-reset + ProfileCoordinator'a observer (resetToRoot; ProfilModel stream-türetimli, model-
  reset gerekmez). 3 App-wiring testi genişletildi/eklendi (push-then-switch → path boş), 3'ü de revert-verify
  RED-doğrulandı.
- **#2 `.home` deep-link'i uçuştaki contextual playback seed'ini iptal etmiyor (LOW CONFIRMED) → ✅ DÜZELTİLDİ:**
  `.play`→`.home` ardışığında resetToRoot() yalnız path'i temizliyordu; pendingPlayback/seedGeneration'a
  dokunmuyordu → uçuştaki `srs_x` seed'i çözülüp feed'i srs_x'e remount ediyor, SON niyet (.home kök) erken
  .play'e kaybediyordu. Fix: resetToRoot()'a `pendingPlayback = nil` + `seedGeneration &+= 1` (uçuştaki seed-
  resolution düşürülür; tüketilmemiş intent temizlenir). App testi (requestPlayback→handle(.home)→pendingPlayback
  nil) revert-verify RED-doğrulandı; PlaybackFeedSeed/AccountSwitchFeedReset regresyon yok. NOT: `.home`'un feed'i
  "For You"a re-seed edip etmemesi ayrı ürün-kararı (bu fix yalnız yanlış-seed yarışını kapatır).
- **#3 Home & Library detay push'u idempotent değil (LOW CONFIRMED — ✅ DÜZELTİLDİ 2026-08-31):** ikisi de hâlâ `NavigationPath` (element-peek
  edilemez, dedup yok) → player-feed rail / favori "Detaya Git" çift-tap'te iki özdeş `.diziDetay` → yığılmış çift
  ekran + çift Geri. Discover (showDetail) + Profile (appendIfNotTop) zaten guard'lı. **Fix (uygulandı):** Home/Library
  `path` `NavigationPath` → `[AppRoute]`e çevrildi + push'lar `appendIfNotTop` (Discover/Profile deseni; RootTabView
  zaten `.navigationDestination(for: AppRoute.self)` — binding değişmedi). TDD: HomeLibraryNavigationIdempotencyTests
  (coordinator-seviyesi: çift-tap→tek push, distinct→yığılır) RED→GREEN + revert-verify (guard izole); 260 App testi
  yeşil, full-repo lint temiz. App CI-dışı → yerel doğrulandı.
- **#4 LibraryCoordinator.listemPlaySeries fence'siz Task (LOW PLAUSIBLE):** `latestProgress` await'i sırasında
  A→B switch olursa Task A'nın record'unu (episode/pozisyon) B'nin feed'ine `requestPlayback` eder (dizi public
  ama izleme-pozisyonu B'ye seed'lenir; çok dar — switch tek await'e denk gelmeli). **Fix:** await öncesi userID/
  epoch yakala, değiştiyse requestPlayback'i düşür (RewardsKit epoch-fence deseni).

### AnalyticsKit adversarial bug-hunt — HEPSİ DÜZELTİLDİ (2026-08-31)
AnalyticsKit paketi küçük+saf+sağlam (batching/queue/flush YOK; experiment assign/exposure-idempotency/dedup/
format testli, 2026-08-30 ertelenenler zaten fixli). 1 HIGH App-wiring + 2 LOW paket-hardening DÜZELTİLDİ:
- **#1 Player-feed engagement event'leri ab_variants decorator'ını atlıyor (HIGH CONFIRMED, funnel-attribution) →
  ✅ DÜZELTİLDİ:** `HomeCoordinator.makePlayerFeedView()` player-feed'e BASE `dependencies.analytics` geçiyordu
  (decoratedAnalytics değil) → en yüksek-trafikli tüketim event'leri (video_start/swipe_next/swipe_prev/
  video_stall) `ab_variants` boyutu OLMADAN yayılıyordu → A/B deneyleri birincil engagement/retention metriğini
  varyanta göre kıramıyordu. Bir önceki audit "5 fabrikayı" düzeltmişti; bu, View'a doğrudan (model-fabrikası
  değil) wire edildiği için kaçan TEK kalan BASE-wiring'di. Fix: satır 160 `dependencies.analytics` →
  `decoratedAnalytics` (diğer TÜM feature wiring'i gibi; exposure ayrı ExperimentClient→BASE yolunda kalır §7.3).
  App derlendi + lint temiz. NOT: PlayerFeedView.analytics `private` + App target CI-dışı → orantılı unit-test yok
  (View'ı public yapmak üretim-API'sini test için açardı); build + pattern-tutarlılığı + reviewer-onayıyla doğrulandı.
- **#2 Ağırlıklı varyant ölçeklemede Int overflow (LOW, latent crash-safety) → ✅ DÜZELTİLDİ:** `ExperimentAssigning`
  `variantBucket * totalWeight` — `totalWeight` üst-sınırsız remote-config toplamı; ≳9.2e14 ile Int64 overflow →
  TRAP (crash). Üretimde şu an erişilemez (canlı bridge yalnız weight=1 sentezler) ama tam remote-katalog bağlanırsa
  latent. Fix: point-of-use `multipliedReportingOverflow` — taşmada Double fallback (bucketing için hassasiyet
  yeterli, crash yerine geçerli dağılım), normal durumda exact integer korunur. TDD testi (Int.max/2 weight'ler →
  crash yok, geçerli varyant) revert-verify RED (overflow trap → "unexpected exit").
- **#3 ABVariants.format delimiter injection (LOW defensive) → ✅ DÜZELTİLDİ:** `key:value` `,`-join'de key/variant-id
  `:`/`,` içerirse ambiguous `ab_variants` (backend yanlış pair'lere böler). Fix: format'ta `:`/`,` içeren key/value'lu
  girdiyi ATLA (diğer deneylerin pair'lerini bozmasın). TDD testi (bozuk key/value atlanır, temizler korunur)
  revert-verify RED (guard'sız `out` bozuk delimiterlı string).
### Launch/Onboarding/ATT/Push/NSE adversarial bug-hunt — TEMİZ + 1 LOW DÜZELTİLDİ (2026-09-01)
Bu, kalan tek hunt-edilmemiş kullanıcı-yüzeyiydi (LaunchCoordinator/SplashView, SS-060/064 onboarding+ATT,
SS-140/143 push payload, SS-141 NSE). Uçtan-uca izleme sonrası **HIGH/MEDIUM gerçek bug YOK** — alan iyi
mühendislenmiş + kapsamlı testli (cold-launch push routing tek-drain + splash/onboarding deferral; NSE `deliver()`
tek-choke `NSLock` altında tam-bir-kez + time-expire text-fallback + untrusted-şema reddi; PushPayload unknown→nil;
kilitli-bölüm push'u server-authoritative paywall'dan geçer; ATT `NSUserTrackingUsageDescription` mevcut → flag-flip
crash yok; analytics registry drift yok). NSE + App CI-DIŞI olduğu için bu güvence yerel doğrulamaya dayanır.
- **#1 Onboarding izin butonları re-entrancy guard'sız (LOW CONFIRMED, analytics-only) → ✅ DÜZELTİLDİ:**
  `OnboardingModel.requestNotificationAuthorization()`/`requestAppTracking()` yalnız faz'a guard'lıyor, sonra sistem
  diyaloğunu `await` ediyor — faz ancak await SONRASI ilerliyor. Butona hızlı çift-tap → iki eşzamanlı çağrı da
  faz-guard'ını geçer → `onboarding_push_prompt`/`onboarding_att_prompt` İKİ kez basılır (funnel çift-sayımı;
  `complete()`→`finish()` zaten `completion == nil` guard'lı olduğundan durum bozulması/çift-complete YOK — yalnız
  analitik doğruluğu). **Fix:** paylaşılan `isRequestingPermission` bayrağı (guard'a eklendi + `defer` reset) →
  ikinci çağrı erken döner. TDD: iki çift-tap testi (setDelay ile await penceresi açılıp iki çağrı interleave
  edilir) RED (count 2) → GREEN (count 1); 12 OnboardingPermissions testi yeşil, full-repo lint temiz. App CI-dışı
  → yerel doğrulandı.

### Yaşam-döngüsü/teardown/leak adversarial bug-hunt — TEMİZ (2026-09-01)
Nesne-yaşam-döngüsü açısı (iptal-edilmeyen Task / kapatılmayan continuation / retain-cycle / hesap-geçişinde
yaşayan observer) tüm `Packages/*/Sources/**` + `App/**` genelinde tarandı: 28 `for await`, 48 continuation,
125 `Task {`, 10 `deinit` — hepsinin yaratım+yıkım noktası okundu. **Doğrulanmış HIGH/MEDIUM sızıntı YOK;
SS-132 sınıfının (ölü model canlı yazıyor) başka örneği yok.** Tutarlı teardown desenleri: saklanan Task +
`deinit`/`onDisappear` iptali + `isDisposed`/epoch-fence guard'ı; köprü akışlarında `onTermination { cancel }`;
multicast'lerde `onTermination` ile otomatik abonelik-silme + `finish`; continuation bekleyicileri daima
`defer`+resume. Koordinatör observer'ları (iptal edilmez) app-ömrü tasarımı + `[weak self]` → çürütüldü.
- **AVPlayerBackend deinit item-observer temizliği eksik (LOW, ERTELENDİ — pratikte erişilemez):**
  `installNotificationObservers` (`:213-235`) NotificationCenter blok-observer token'larını `notificationTokens`'a
  ekler; temizlik `removeItemObservers()` (`:248-263`) `@MainActor` + yalnız `load()`/`clearItem()` yolunda. `deinit`
  (`:41-44`) `nonisolated` → `@MainActor removeItemObservers()`'ı çağıramaz; token'lar canlı-item'la dealloc'ta
  NotificationCenter'da kalır. **Neden ertelendi:** (1) havuz player'ları tasarımca ASLA dealloc olmaz
  (`PlayerPool.swift:6-7`; teardown = `drain(keepPlayers: true)`) → backend normal işleyişte hiç dealloc olmaz;
  (2) blok'lar `[weak self]` + ölü `AVPlayerItem`'a object-filtreli → asla anlamlı ateşlenmez, KVO dealloc'ta
  otomatik invalidate; (3) `notificationTokens` `[NSObjectProtocol]` (Sendable DEĞİL) → nonisolated deinit'ten
  okumak Swift 6 strict-concurrency'de sorunlu; düzgün fix `isolated deinit` (SE-0371) gerektirir; (4) bu sınıf
  birim-testi KOŞMAZ (`:10-11`; cihaz/sim perf-koşusu doğrular) → TDD RED yazılamaz. Doğrulanmış-sağlam çekirdeğe
  riskli/test-siz değişiklik yerine belgelendi. Gelecekte `isolated deinit`e geçilirse eksiksizlik için eklenebilir.

### Auth/Session/Networking/Storage güvenlik hunt'ı — HIGH YOK, 2 MEDIUM+LOW düzeltildi (2026-09-01)
Server-authoritative para modeli için erişim-kontrolünün özü olan katman (SessionManager, TokenRefreshCoordinator,
AuthInterceptor, KeychainSecureStore, APIClient auth-recovery) odaklı güvenlik taramasından geçti. **HIGH YOK;
katman büyük ölçüde sağlam** — DOĞRULANAN korumalar: off-domain token sızıntısı YOK (`APIClient.makeRequest` URL'i
her zaman `configuration.baseURL`'den kurar; `Endpoint` yalnız path/query verir; medya ayrı `AssetDownloading`
port'u + imzalı-URL, app bearer'ı taşımaz); refresh single-flight (actor + `singleFlight`; refresh `bareClient`'te
→ 401-on-refresh recovery'ye re-enter etmez → `sessionExpired`); 401-replay tam-bir-kez (`hasRecoveredAuth`) + yeni
token'la yeniden kurulur (`applyingOverrideBearer`); Keychain `...AfterFirstUnlockThisDeviceOnly` (non-syncable/
backup), UserDefaults'ta token yok, plaintext secret loglanmaz; error-body decode hiçbir erişim kapısını açmaz.
- **#1 linkSession Keychain yazımı koparsa bellek-içi kimlik yine de yükseliyordu (MEDIUM CONFIRMED → ✅ DÜZELTİLDİ):**
  `SessionManager.linkSession` `setAtomically` catch'i BOŞtu ve yine `setState(.linked(B))` yapıyordu. AuthInterceptor
  access token'ı HER istekte Keychain'den TAZE okuduğundan (linkSession token'ı bellekte tutmaz), yazım koparsa
  Keychain A'da kalır (rollback) → state B ama sunucu A ile doğrular (SWITCH durumunda çapraz-hesap: "B" A'nın coin/
  geçmiş/profilini görür/harcar). **Fix:** catch'te state'i YÜKSELTMEDEN erken dön → disk (token kaynağı) ile tutarlı
  kal; switch sessizce başarısız olur (kullanıcı eskide kalır, yeniden dener). TDD: `linkSessionKeychainYazimiKoparsa
  KimlikYukseltilmez` (WriteFailingSecureStore) RED→GREEN; eski "yükselt-yine-de" davranışını encode eden 2 test
  (torn-write + refresh-torn) güvenli invaryanta güncellendi (asıl amaçları — atomik rollback / saatli-bomba önleme
  — korundu); 326 AppFoundation testi yeşil.
- **#4 AuthInterceptor host-scope etmiyordu (LOW, defense-in-depth → ✅ DÜZELTİLDİ):** Bearer'ı `requiresAuth` her
  isteğe host kontrolü olmadan ekliyordu (bugün güvenli çünkü APIClient yapıca base-host'u zorluyor). **Fix:** opsiyonel
  `apiHost` param (nil=kısıtsız, yalnız izole test; canlı wiring `configuration.baseURL.host` geçer) + `adapt` host
  guard'ı → gelecekte yabancı-host (CDN/analytics/3P) bir istek zincire girse bile token SIZMAZ. TDD: yabancı-host→
  Bearer yok / eşleşen-host→Bearer var; revert-verify RED (guard'sız evil.cdn'e "Bearer" sızıyor).
- **#2 Çıkışta token-temizliği best-effort (`try?`) → Keychain delete koparsa relaunch'ta oturum dirilir (MEDIUM,
  ERTELENDİ):** `handleRefreshFailure`→`clearStoredTokens` `try?`; delete koparsa token'lar diskte kalır, state
  `.loggedOut` olur, ama relaunch `restoreFromKeychain` snapshot+token görüp `.linked` diriltir. DAR: keychain delete
  transient hata + access token refresh-token ölümünden sonra hâlâ server-geçerli + relaunch penceresi (çoğu vakada
  bir sonraki 401 tekrar loggedOut'a düşürür). Robust fix stored-schema "logout tombstone" (opsiyonel `loggedOut: Bool?`
  ile decode-güvenli migration) veya doğrulamalı-silme gerektirir — doğrulanmış-sağlam session çekirdeğine migration-
  hassas değişiklik; ayrı, dikkatli ele alınacak. Gerekçeyle belgelendi.
- **#3 TokenRefreshCoordinator rotasyon-guard'ında artık TOCTOU (LOW, ERTELENDİ):** post-access oku (:130) ile yaz
  (:139/143) ayrı Keychain op; araya `linkSession` yazımı girerse guard rotasyonu görmez → B token'larını A'nın
  rotasyonuyla ezebilir. Pencere çok dar; guard yaygın durumu kapatıyor → defense-in-depth. Fix: link+refresh yazımını
  ortak kilit/generation ile serialize. Ertelendi (nadir yarış, sağlam çekirdek).
- **#5 Guest `TOKEN_INVALID` kurtarması orijinal (idempotent-olmayan) isteği YENİ guest kimliğiyle replay eder (LOW,
  ERTELENDİ):** guest→guest, düşük etki (linked hesaplar `sessionExpired` fırlatır, replay etmez; ilk deneme 401
  unauth olduğu için çift-execute yok). Fix: idempotent-olmayan isteği kimlik-değişiminde otomatik replay etme.

### Zaman/timezone/DST sınır hunt'ı — HIGH/MEDIUM YOK, 1 LOW düzeltildi (2026-09-01)
Para/streak/erişim zaman-mantığı tutarlı doğru: reward yolları (günlük check-in, streak, "bugün claim edildi mi",
ad-unlock günlük cap, coin expiry) SERVER-authoritative + kullanıcı IANA timezone'u `X-Timezone` header'ıyla sunucuya
gider (`TimezoneInterceptor`) → gün-sınırını sunucu sahiplenir; istemci `Date()`/`Calendar`'dan "bugün"/gün-sayısı
TÜRETMEZ. Daha önce düzeltilen gün-kör check-in pin'i artık gün-duyarlı (`OdulMerkeziModel` `streakDays < claimedStreak`)
→ kardeşi YOK. Token tazeliği (`PlaybackAuthorization.isUsable` `date < expiresAt - leeway`) yön+işaret doğru (REFUTED);
gerçek takvim-günü gösterimi `startOfDay`+`dateComponents([.day])` (RelativeDay) doğru; negatif-elapsed her yerde
`max(0,…)` guard'lı. 6 LOW bulgu HEPSİ cosmetic (DST ±1sa marketing/bildirim/display) — tek anti-pattern `*86400`
raw-saniye takvim-günü yerine geçmesi, ama YALNIZ display/marketing/throttle kodunda, hiçbir reward-kapısında değil.
- **#6 PlayerMetricsCollector negatif latency (LOW, analytics-hijyen → ✅ DÜZELTİLDİ):** `milliseconds(from:to:)`
  alt-clamp'sizdi → oturum ortasında cihaz saati geri alınırsa `ttff_ms`/`swipe_latency_ms` negatif basılıyordu
  (percentile/aggregation zehirlenir). Kod tabanının kendi `max(0,…)` invaryantının (onboarding/unlock/review/discover)
  TEK istisnasıydı. **Fix:** `max(0,…)` clamp (paylaşılan helper → hem ttff hem swipe kapsanır). TDD: geri-saat →
  ttff_ms=0 RED(−500)→GREEN; 16 PlayerMetrics testi yeşil.
- **Ertelenen 5 LOW cosmetic** (Calendar-inject / marginal DST ±1sa gain, hiçbiri money/access): WinBackEligibility
  `formerVIPGraceDays*86400` (marketing banner), EarnedCoinExpiry `daysRemaining` (display; sunucu FEFO sahibi),
  DiziDetay `newEpisodeWeekday` (cihaz-TZ weekday — muhtemelen istenen), NotificationRelativeTime raw-saniye bucket
  (bildirim "23 sa"/"1 g" sınırı), Review/RemoteConfig/WinBack throttle TTL'leri (`/86400`; hepsi server-override).
  Doğrulanmış-sağlam koda cosmetic DST için Calendar-inject churn'ü değmez → belgelendi.

- SS-050 kilit-sınırı reactivation (varsa gap), LibraryCatalog offline cache, WP-F1-G
  review'unda ertelenen küçük optimizasyonlar (CatalogCache `lastAccessAt`/tahliye-bütçe,
  ListemModel batch-delete). Bunlar prep GEREKTİRMEZ; sürekli döngüde ele alınır.
