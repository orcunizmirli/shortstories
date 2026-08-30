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
- **Başarısız prefetch "completed warmup" sayılıyor (PrefetchController.swift:151, LOW):** `warm`/
  `prepareNext` geçici authorize hatasını (5xx/timeout) yutup normal dönüyor → `taskCompleted` onu
  `completedWarmups`'a ekliyor → o bölüm pencere-içi kaldıkça bir daha WARM EDİLMİYOR (ağ dönse bile
  swipe'ta cold-start spinner) + bandwidth telemetrisi over-count. NON-INVARIANT (kullanıcı swipe'ta
  activate gerçek authorize yapar, doğru oynar — yalnız cold). Fix `EpisodeWarming.warm`'ı Void→Bool
  ("tamamlandı; retry etme") yapmayı gerektirir (protokol + PrefetchController + fake warmer'a yayılır);
  başarıda/kilitlide true, geçici hatada false → completedWarmups'a yalnız true'da eklenir. Değer düşük
  (efficiency/telemetry), izole değil → ayrı pass'e bırakıldı.

### LibraryKit/ProfileKit bug-hunt — ertelenen 2 kalem (2026-08-30)
Kütüphane (favoriler/devam-et) + Profil bug-hunt'ının 5 bulgusundan 3'ü düzeltildi (3 commit:
compensatingDeletes cross-account leak MEDIUM, loadContinue generation-guard MEDIUM, ProfilModel
sessionExpired-çıkış cüzdan-restore MEDIUM); 2'si düşük-değer/self-healing doğası gereği ertelendi:
- **WatchHistoryStore.mergeServerProgress synced-newer LWW boşluğu (WatchHistoryStore.swift:31, LOW):**
  Merge guard'ı yalnız `pendingUpload && watchedAt daha yeni` yerel kaydı korur (`isNewerLocalPending`).
  Yerel kayıt **synced** ama server merge batch'indeki kayıttan DAHA YENİ ise (out-of-order/bayat server
  response: T2 ack'lendikten sonra araya giren eski T1 snapshot'ı) guard false döner → eski T1 server
  kaydı daha yeni synced T2'yi EZER (LWW ihlali). Pratikte self-healing: synced ⇒ server o değeri zaten
  ack'lemiş ⇒ sonraki merge T2'yi geri getirir; pencere yalnız reordered/stale response anıdır. **Fix:**
  guard'ı syncState'ten bağımsız saf `entity.watchedAt > record.watchedAt`'e genişlet (synced kayıt da
  daha yeniyse korunur). Değer düşük (geçici + kendini düzelten), izole değil → ayrı pass'e bırakıldı.
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

---

## Kod-içsel (prep gerektirmeyen) kalan iş — ayrı izlenir
- SS-050 kilit-sınırı reactivation (varsa gap), LibraryCatalog offline cache, WP-F1-G
  review'unda ertelenen küçük optimizasyonlar (CatalogCache `lastAccessAt`/tahliye-bütçe,
  ListemModel batch-delete). Bunlar prep GEREKTİRMEZ; sürekli döngüde ele alınır.
