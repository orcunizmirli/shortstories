# Manuel Prep Bekleyen Kalemler (F2/F3)

**Amaç:** Bu dosya, istemci tarafı KODU hazır/soyutlanmış ama gerçek entegrasyonu için
**dışarıdan manuel hazırlık** (hesap, SDK, sertifika, sunucu ucu, çeviri) gerektiren
kalemleri izler. Kod-içsel iş bittiğinde bu kalemler burada beklerki; prep sağlanınca
her biri mevcut **injectable port**'un arkasına ince bir adaptörle takılır (desen
fraud/win-back/rewarded-ad/hesap-bağlama'da kanıtlandı).

Durum tarihi: 2026-07-20 · Referans: `09-yol-haritasi-tasklar.md`

---

## 1. AdMob rewarded ads — GERÇEK SDK (SS-113)
- **Client durumu:** ✅ HAZIR. `RewardsKit/RewardedAds/` — `RewardedAdProviding` portu +
  `RewardedAdAvailability` + `RewardedAdService` (server-otoriter, 30sn, cap, A/B) +
  `AdUnlockGateway` (POST /rewards/ad-unlock, §4.7 nested proof). UnlockSheet "reklam izle"
  satırı bağlı (SS-114). Şu an `MockRewardedAdProvider` enjekte.
- **Gereken manuel prep:**
  - Google AdMob hesabı + uygulama kaydı → **App ID** + **rewarded ad unit ID**.
  - Google Mobile Ads SDK (SPM: `googleads-mobile-sdk`) `project.yml`'ye eklenir.
  - Backend: **SSV** (Server-Side Verification) ucu `/rewards/ad-unlock` doğrulayıcısı.
- **Prep gelince yapılacak:** `App/DI/Adapters/RewardedAdAdapters.swift` içinde gerçek
  `GADRewardedAd` adaptörü (`RewardedAdProviding` conformance) yazılıp `MockRewardedAdProvider`
  yerine enjekte edilir; App ID Info.plist'e (`GADApplicationIdentifier`).

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

---

## Kod-içsel (prep gerektirmeyen) kalan iş — ayrı izlenir
- SS-050 kilit-sınırı reactivation (varsa gap), LibraryCatalog offline cache, WP-F1-G
  review'unda ertelenen küçük optimizasyonlar (CatalogCache `lastAccessAt`/tahliye-bütçe,
  ListemModel batch-delete). Bunlar prep GEREKTİRMEZ; sürekli döngüde ele alınır.
