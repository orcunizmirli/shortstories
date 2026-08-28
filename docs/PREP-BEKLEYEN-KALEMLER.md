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
- **Client durumu:** ✅ Altyapı HAZIR (SS-160 String Catalog, EN kaynak; pseudo-locale build).
- **Gereken manuel prep (SÜREÇ, kod değil):**
  - SS-163: TMS/çeviri sağlayıcı seçimi + terim sözlüğü (coin/unlock/VIP/check-in...).
  - SS-164: string freeze ritmi + eksik-çeviri CI kontrolü.
  - SS-165: native reviewer dil QA + cihazda taşma turu.
  - SS-166: ASC metadata + ekran görüntüleri + IAP display name lokalizasyonu.

## 5. Offline İndirilenler (SS-124, F3)
- FairPlay **persistent key** (SS-053'e bağlı) + `AVAssetDownloadTask` motoru + İndirilenler UI.
  SS-053 gerçek DRM olmadan başlanamaz. F3 kapsamı.

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

---

## Kod-içsel (prep gerektirmeyen) kalan iş — ayrı izlenir
- SS-050 kilit-sınırı reactivation (varsa gap), LibraryCatalog offline cache, WP-F1-G
  review'unda ertelenen küçük optimizasyonlar (CatalogCache `lastAccessAt`/tahliye-bütçe,
  ListemModel batch-delete). Bunlar prep GEREKTİRMEZ; sürekli döngüde ele alınır.
