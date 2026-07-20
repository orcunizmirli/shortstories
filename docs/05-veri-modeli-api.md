# Veri Modeli ve API Sözleşmesi

**Amaç:** Bu doküman, ShortSeries iOS istemcisinin backend ile paylaştığı domain modellerini, SwiftData yerel şemasını ve REST API sözleşmesini geliştirme ekibinin doğrudan uygulayabileceği ayrıntıda tanımlar. Alan tabloları, örnek istek/yanıt JSON'ları, hata sözleşmesi, sayfalama kalıbı, imzalı URL / FairPlay beklentileri, offline davranış matrisi ve versiyonlama kuralları burada normatiftir: istemci (`ContentKit`, `WalletKit`, `RewardsKit`, `AnalyticsKit`, `AppFoundation`) ve backend ekipleri bu sözleşmeye göre paralel geliştirme yapar.

**İlgili dokümanlar:** `00-genel-bakis.md` (ürün vizyonu), `01-ozellik-envanteri.md` (özellik kapsamı), `02-ekran-haritasi-navigasyon.md` (ekran ↔ endpoint eşlemesi), `03-mimari.md` (modül sınırları, DI, networking katmanı), `04-player-engine.md` (playback, prefetch, imzalı URL tüketimi), `06-monetizasyon.md` (coin ekonomisi, IAP ürün kataloğu), `07-retention-gamification.md` (görev/check-in kuralları), `08-analitik-deney.md` (event şeması), `09-yol-haritasi-tasklar.md` (faz planı).

---

## 1. Genel ilkeler

1. **Protokol:** REST + JSON. İstemci tarafında `URLSession` async/await + `Codable`. Combine kullanılmaz (kanon: yeni kodda Combine yok).
2. **Server otoritatiftir.** Cüzdan bakiyesi, entitlement, kilit durumu, abonelik durumu için tek doğruluk kaynağı backend'dir. İstemci optimistic update yapabilir ama her yanıtta sunucu değeriyle üzerine yazar (bkz. §4.3).
3. **Kimlik:** İlk açılışta anonim misafir hesabı otomatik oluşturulur (`POST /auth/guest`); kullanıcı hiçbir zaman "kayıt duvarı" görmez. Apple/Google/e-posta bağlama sonradan yapılır (`POST /auth/link`). Token'lar Keychain'de saklanır.
4. **İçerik erişimi:** İmzalı, süreli URL'ler (Faz 1). FairPlay DRM Faz 2'de eklenir (§8).
5. **Para asla istemcide hesaplanmaz.** `unlockPrice`, bonus coin oranları, VIP entitlement — hepsi API'den okunur. İstemcide hardcoded fiyat yoktur.
6. **Idempotency:** Para/harcama etkisi olan tüm POST'lar (`/wallet/unlock`, `/iap/verify`, `/missions/*/claim`, `/checkin/claim`, `/rewards/ad-unlock`) `Idempotency-Key` header'ı taşır (§6.5, §9).
7. **JSON adlandırma:** Wire formatı `camelCase`. Domain model property adları **istemci sözleşmesidir** ve wire formatından bağımsız stabildir: wire alan adı değişse bile domain adı korunur. Wire adları yalnız decode sınırında eşlenir (`CodingKeys` veya — ayrışma büyüdüğünde — Wire DTO + mapper); UI/ViewModel katmanı asla wire adı görmez, yalnız domain adlarını kullanır.
8. **Tarihler:** ISO 8601 / RFC 3339, her zaman UTC (`2026-07-11T09:30:00Z`). İstemci `ISO8601DateFormatter` (fractional seconds destekli) kullanır.
9. **Para birimleri:** Coin miktarları her zaman `Int`. USD fiyatlar API'de görünmez — StoreKit 2 `Product.displayPrice` yereldir; API yalnız `productId` döner.
10. **Bilinmeyeni yut, kırma:** İstemci tanımadığı JSON alanlarını ve tanımadığı enum değerlerini hatasız yok sayar (§12'de zorunlu decoding kalıbı).

### 1.1 Ortak HTTP header'ları

| Header | Yön | Açıklama |
|---|---|---|
| `Authorization: Bearer <accessToken>` | istek | Auth hariç tüm endpoint'lerde zorunlu |
| `X-Client-Version` | istek | Örn. `ios/1.0.0 (build 42)` — sunucu tarafı zorunlu upgrade kontrolü |
| `X-Platform: ios` | istek | Sabit |
| `X-Device-Id` | istek | `identifierForVendor` tabanlı kalıcı UUID; misafir hesabı eşlemesi ve fraud sinyali |
| `Accept-Language` | istek | Örn. `en-US`, `tr-TR` — feed/metin lokalizasyonu |
| `Idempotency-Key` | istek | Yan etkili POST'larda zorunlu, UUID v4 (§9) |
| `X-Device-Integrity` | istek | **Yalnız authed isteklerde** (SS-100, F2). Cihaz bütünlüğü danışma bayrağı: `clean` \| `suspected`. Best-effort jailbreak/tamper heuristiği (bkz. `AppFoundation/Fraud`); bypass edilebilir → **KESİN değil, karar backend'de**. PII/ham yol TAŞIMAZ; yalnız kaba bayrak. |
| `X-Earn-Velocity-Flag` | istek | **Yalnız authed isteklerde ve sinyal varken** (SS-100, F2). Anormal-kazanç danışma bayrağı: `normal` \| `elevated`. İstemci-taraflı rate-limit İPUCU (WalletKit türetir); istemci bloklamaz, **karar backend'de** (double-entry/audit — 09 R6). Ham sayaç/zaman damgası TAŞIMAZ. |
| `X-Request-Id` | yanıt | Her yanıtta; hata raporlarında ve `AnalyticsKit` loglarında taşınır |
| `Cache-Control`, `ETag` | yanıt | §7.2 |

> **Fraud sinyalleri (SS-100, F2) — DEFANSİF/danışma sözleşmesi.** `X-Device-Integrity` ve `X-Earn-Velocity-Flag` yalnız `requiresAuth` (cüzdan/kazanç dahil) isteklere eklenir (`FraudSignalInterceptor`; kalıp: `AuthInterceptor`/`TimezoneInterceptor`). Her ikisi de BEST-EFFORT danışma bayrağıdır: istemci ASLA karar vermez ve isteği bloklamaz — jailbreak/tamper ve anormal-kazanç kararını backend, kendi sunucu-taraflı sinyalleriyle (cihaz kimliği geçmişi, receipt tutarlılığı, kazanç muhasebesi) birleştirerek verir (§1 kural 2 "server otoritatiftir"). Header'lara PII/secret/ham sayaç KONMAZ; cihaz kimliği zaten `X-Device-Id`'dedir.

---

## 2. Domain modelleri (paylaşılan sözleşme)

Modeller `ContentKit` (katalog), `WalletKit` (ekonomi), `RewardsKit` (görevler), `ProfileKit` (hesap) paketlerinde yaşar; hepsi `Sendable` value type'tır. Aşağıdaki Swift tanımları **istemci domain sözleşmesidir**: property adları wire formatından bağımsız stabildir ve UI/ViewModel'in gördüğü tek adlandırmadır. Bugün wire alan adları bu adlarla örtüşür; ayrıştıkları noktada eşleme yalnız decode sınırında yapılır (§1 kural 7).

### 2.1 Series

```swift
public struct Series: Codable, Identifiable, Hashable, Sendable {
    public let id: String                  // "srs_9f2c1a"
    public let title: String
    public let synopsis: String
    public let coverURL: URL               // portrait poster (2:3)
    public let bannerURL: URL?             // yatay/hero görsel; Kesfet banner'ları için
    public let genres: [Genre]
    public let tags: [Tag]
    public let episodeCount: Int           // toplam planlanan bölüm
    public let releasedEpisodeCount: Int   // şu an yayında olan bölüm (release schedule)
    public let freeEpisodeCount: Int       // ilk N bölüm ücretsiz (5–10 aralığı, server belirler)
    public let releaseState: ReleaseState  // .ongoing | .completed
    public let nextEpisodeAt: Date?        // ongoing ise bir sonraki bölümün yayın zamanı
    public let stats: SeriesStats
    public let localeInfo: LocaleInfo
    public let updatedAt: Date

    public enum ReleaseState: String, Codable, Sendable, UnknownDecodable {
        case ongoing, completed, unknown
    }
}

public struct SeriesStats: Codable, Hashable, Sendable {
    public let viewCount: Int              // gösterim amaçlı, yaklaşık değer
    public let favoriteCount: Int
    public let trendingRank: Int?          // Kesfet "Trend" rafı; null = listede değil
}

public struct LocaleInfo: Codable, Hashable, Sendable {
    public let audioLanguage: String       // BCP-47, örn. "en"
    public let subtitleLanguages: [String] // ["en", "tr", "es", "pt"]
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `id` | String | hayır | Sunucu üretimi opak ID, `srs_` öneki. İstemci asla parse etmez |
| `title` | String | hayır | `Accept-Language`e göre lokalize gelir |
| `synopsis` | String | hayır | DiziDetay özet metni |
| `coverURL` | URL | hayır | 2:3 portrait; CDN, imzasız (public görsel) |
| `bannerURL` | URL? | evet | Yoksa istemci cover'dan kırpar |
| `genres` | [Genre] | hayır | En az 1 |
| `tags` | [Tag] | hayır | Boş olabilir |
| `episodeCount` | Int | hayır | Toplam plan; DiziDetay "80 Bölüm" rozeti |
| `releasedEpisodeCount` | Int | hayır | `<= episodeCount`; BolumListesi bunu baz alır |
| `freeEpisodeCount` | Int | hayır | Kanon: 5–10 aralığı; istemci bu değeri okur, varsaymaz |
| `releaseState` | enum | hayır | Bilinmeyen değer `.unknown`a düşer |
| `nextEpisodeAt` | Date? | evet | DiziDetay "Yeni bölüm: Cuma" etiketi |
| `stats` | SeriesStats | hayır | Yaklaşık sayılar; UI kısaltır (1.2M) |
| `localeInfo` | LocaleInfo | hayır | Ayarlar'daki altyazı dili seçimiyle kesişim alınır |
| `updatedAt` | Date | hayır | Cache invalidation için (§5.3) |

### 2.2 Episode

```swift
public struct Episode: Codable, Identifiable, Hashable, Sendable {
    public let id: String                  // "ep_5410be"
    public let seriesId: String
    public let index: Int                  // 1 tabanlı bölüm numarası
    public let title: String?              // çoğunlukla null; "Bölüm 12" istemcide üretilir
    public let durationSec: Int            // tipik 60–180 sn
    public let thumbnailURL: URL
    public let access: EpisodeAccess
    public let publishedAt: Date?          // null = henüz yayınlanmadı (takvimde görünür)
}

public struct EpisodeAccess: Codable, Hashable, Sendable {
    public let kind: Kind                  // .free | .locked | .unlocked
    public let unlockPrice: Int?           // .locked + coin yolu açıksa dolu (50–100 aralığı); .locked + null = coin yolu kapalı
    public let adUnlockEligible: Bool      // rewarded ad ile açılabilir mi (günlük cap sunucuda)

    public enum Kind: String, Codable, Sendable, UnknownDecodable {
        case free, locked, unlocked, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `id` | String | hayır | Opak, `ep_` öneki |
| `seriesId` | String | hayır | Üst dizi |
| `index` | Int | hayır | UI sırası; BolumListesi ızgarası bununla dizilir |
| `title` | String? | evet | Null ise istemci `"Bölüm \(index)"` üretir |
| `durationSec` | Int | hayır | Progress yüzdesi hesabında payda |
| `thumbnailURL` | URL | hayır | BolumListesi hücresi |
| `access.kind` | enum | hayır | `unlocked`: bu kullanıcı için açılmış kilitli bölüm. **VIP kullanıcıya sunucu tüm bölümleri `free` veya `unlocked` döner** — istemci VIP mantığı uygulamaz |
| `access.unlockPrice` | Int? | koşullu | Yalnız `.locked` iken anlamlı; dolu ise kanon: 50–100 coin, API'den dinamik. `.locked` + `null` = coin yolu kapalı (genişleme noktası, aşağıda) |
| `access.adUnlockEligible` | Bool | hayır | UnlockSheet'te "Reklam izle" seçeneğinin görünürlüğü |
| `publishedAt` | Date? | evet | Release schedule; null bölüm oynatılamaz |

**Edge case — erişim durumu bayatlaması:** `access` kullanıcıya özeldir ve cache'lenen kopya bayatlayabilir (başka cihazda unlock, VIP satın alma). Oynatma yetkisi her zaman sunucudan teyit edilir — `POST /playback/authorize` (§4.4) veya unlock yanıtındaki `playback` bloğu (§4.5); `access` yalnız UI ön-gösterimi içindir.

**Genişleme noktası — coin yolu kapalı kilit:** `access.kind == .locked` + `unlockPrice == null` geçerli bir kombinasyondur ve "bu bölüm coin ile açılamaz" anlamına gelir (örn. salt-VIP içerik). UnlockSheet bu durumda coin satırını çizmez; reklam ve VIP seçenekleri `adUnlockEligible` ve abonelik durumuna göre görünür kalır. Bu semantik, iş modelinin salt-VIP'e evrilmesini `/v2` kırılımı olmadan mümkün kılar (§12 kural 2 kapsamında kırıcı olmayan değişiklik); istemci bugünden bu kombinasyonu doğru işlemek ZORUNDADIR.

### 2.3 Genre ve Tag

```swift
public struct Genre: Codable, Identifiable, Hashable, Sendable {
    public let id: String        // "gnr_romance"
    public let name: String      // lokalize: "Romantik"
    public let iconURL: URL?
}

public struct Tag: Codable, Identifiable, Hashable, Sendable {
    public let id: String        // "tag_revenge"
    public let name: String      // lokalize: "İntikam"
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `Genre.id` | String | hayır | Kesfet tür filtreleri bu ID ile sorgular |
| `Genre.name` | String | hayır | Lokalize görünen ad |
| `Genre.iconURL` | URL? | evet | Onboarding tür tercihi kartları |
| `Tag.id` / `Tag.name` | String | hayır | DiziDetay etiket rozetleri; Arama'da filtre |

### 2.4 UserProfile

```swift
public struct UserProfile: Codable, Identifiable, Sendable {
    public let id: String                    // "usr_ab12cd"
    public let displayName: String?          // misafirde null
    public let avatarURL: URL?
    public let accountState: AccountState    // .guest | .linked
    public let linkedProviders: [Provider]   // [.apple], [.google], [.email] kombinasyonları
    public let preferredGenres: [String]     // Genre.id listesi (Onboarding tercihi)
    public let appLanguage: String           // "en"
    public let subtitleLanguage: String      // "en"
    public let notificationOptIn: Bool
    public let createdAt: Date

    public enum AccountState: String, Codable, Sendable, UnknownDecodable {
        case guest, linked, unknown
    }
    public enum Provider: String, Codable, Sendable, UnknownDecodable {
        case apple, google, email, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `id` | String | hayır | Analitik user ID'si ile aynı (bkz. `08-analitik-deney.md`) |
| `displayName` | String? | evet | Misafirde null → Profil "Misafir" gösterir |
| `avatarURL` | URL? | evet | — |
| `accountState` | enum | hayır | `guest` iken Profil'de "Hesabını bağla" CTA'sı |
| `linkedProviders` | [Provider] | hayır | Ayarlar → hesap yönetimi |
| `preferredGenres` | [String] | hayır | Boş olabilir (Onboarding atlanabilir) |
| `appLanguage` / `subtitleLanguage` | String | hayır | Ayarlar'dan `PATCH /me` ile güncellenir |
| `notificationOptIn` | Bool | hayır | Sunucu tarafı push segmentasyonu |
| `createdAt` | Date | hayır | — |

### 2.5 Wallet

Kanon gereği **purchasedCoins ve earnedCoins ayrı tutulur** (App Store komisyonu muhasebesi + earned coin son kullanma tarihi). Harcama önceliği: **earned önce**. Bu öncelik sunucuda uygulanır; istemci yalnız gösterir.

```swift
public struct Wallet: Codable, Sendable {
    public let purchasedCoins: Int         // IAP ile alınmış, süresiz
    public let earnedCoins: Int            // check-in/görev/rewarded ad; süreli olabilir
    public let earnedExpiringSoon: ExpiryNotice?  // en yakın son kullanma bildirimi
    public let firstTopUpEligible: Bool    // ilk yükleme 2x bonus teklifi hakkı (CoinMagazasi)
    public let updatedAt: Date
    public let version: Int                // monoton artan; eski yanıtı yenisiyle ezme koruması

    public var totalCoins: Int { purchasedCoins + earnedCoins }
}

public struct ExpiryNotice: Codable, Sendable {
    public let amount: Int                 // kaç coin
    public let expiresAt: Date             // ne zaman yanacak
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `purchasedCoins` | Int | hayır | ≥ 0 |
| `earnedCoins` | Int | hayır | ≥ 0; son kullanma sunucuda takip edilir |
| `earnedExpiringSoon` | ExpiryNotice? | evet | OdulMerkezi ve CoinMagazasi "500 coin 3 gün içinde sona erecek" bandı |
| `firstTopUpEligible` | Bool | hayır | `true` iken CoinMagazasi ilk yükleme 2x bonus teklifini çizer (paket kataloğu: §4.5 `GET /wallet/packages`); ilk başarılı coin IAP'ından sonra sunucu `false` yapar |
| `updatedAt` | Date | hayır | — |
| `version` | Int | hayır | İstemci kuralı: `version` düşükse yanıtı at (out-of-order yanıt koruması) |

### 2.6 CoinTransaction

```swift
public struct CoinTransaction: Codable, Identifiable, Sendable {
    public let id: String                  // "txn_77aa01"
    public let type: TxnType
    public let amount: Int                 // işaretli: kazanım +, harcama −
    public let bucket: Bucket              // .purchased | .earned
    public let balanceAfter: Int           // işlem sonrası toplam bakiye (gösterim)
    public let refId: String?              // unlock → episodeId, iap → productId, mission → missionId
    public let note: String?               // lokalize açıklama ("Günlük check-in — 3. gün")
    public let createdAt: Date

    public enum TxnType: String, Codable, Sendable, UnknownDecodable {
        case iapPurchase, episodeUnlock, checkInReward, missionReward,
             adReward, vipDailyBonus, refund, expiry, adminAdjust, unknown
    }
    public enum Bucket: String, Codable, Sendable, UnknownDecodable {
        case purchased, earned, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `id` | String | hayır | Sunucu double-entry kaydının istemciye bakan ID'si |
| `type` | enum | hayır | Profil → işlem geçmişi ikon/metin eşlemesi |
| `amount` | Int | hayır | Negatif = harcama. Tek bölüm kilidi hem earned hem purchased'dan düşerse sunucu **iki satır** döner (bucket başına bir) |
| `bucket` | enum | hayır | Hangi keseden |
| `balanceAfter` | Int | hayır | Yalnız gösterim; istemci bundan bakiye türetmez |
| `refId` | String? | evet | Derin bağlantı (işlemden DiziDetay'a gitmek için) |
| `note` | String? | evet | — |
| `createdAt` | Date | hayır | Liste sıralaması |

### 2.7 UnlockRecord

```swift
public struct UnlockRecord: Codable, Identifiable, Sendable {
    public let id: String                  // "ulk_3c9d10"
    public let episodeId: String
    public let seriesId: String
    public let method: Method              // .coins | .rewardedAd | .vip
    public let coinsSpent: Int             // rewardedAd/vip için 0
    public let unlockedAt: Date

    public enum Method: String, Codable, Sendable, UnknownDecodable {
        case coins, rewardedAd, vip, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `id` | String | hayır | İdempotent unlock'ta aynı `Idempotency-Key` → aynı `id` döner |
| `episodeId` / `seriesId` | String | hayır | — |
| `method` | enum | hayır | Analitik `unlock_method` boyutuyla eşleşir |
| `coinsSpent` | Int | hayır | — |
| `unlockedAt` | Date | hayır | Kilitler kalıcıdır: unlock süresiz geçerlidir (VIP'ten bağımsız) |

### 2.8 SubscriptionStatus

```swift
public struct SubscriptionStatus: Codable, Sendable {
    public let isVIP: Bool
    public let plan: Plan?                 // .weekly | .monthly | .yearly; isVIP=false → null
    public let expiresAt: Date?            // mevcut dönem sonu
    public let willAutoRenew: Bool
    public let isInGracePeriod: Bool       // billing retry / grace period (erişim sürer)
    public let isInIntroOffer: Bool        // intro teklif dönemi
    public let dailyBonusCoins: Int        // VIP günlük bonus miktarı (remote config'ten)
    public let dailyBonusClaimedToday: Bool

    public enum Plan: String, Codable, Sendable, UnknownDecodable {
        case weekly, monthly, yearly, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `isVIP` | Bool | hayır | Tek entitlement bayrağı. Sunucu App Store Server Notifications V2 ile günceller; istemci StoreKit 2 `Transaction.currentEntitlements`i yalnız **hızlı yerel ipucu** olarak kullanır, otorite sunucudur |
| `plan` | enum? | evet | VIPAbonelik "mevcut plan" vurgusu |
| `expiresAt` | Date? | evet | — |
| `willAutoRenew` | Bool | hayır | İptal etmiş ama dönemi sürüyorsa `false` + `isVIP=true` |
| `isInGracePeriod` | Bool | hayır | `true` iken erişim kesilmez; Profil'de "ödeme sorunu" bandı |
| `isInIntroOffer` | Bool | hayır | — |
| `dailyBonusCoins` | Int | hayır | Kanon: VIP = tüm bölümler açık + günlük bonus coin + reklamsız |
| `dailyBonusClaimedToday` | Bool | hayır | OdulMerkezi'ndeki VIP bonus kartının durumu |

### 2.9 Mission

```swift
public struct Mission: Codable, Identifiable, Sendable {
    public let id: String                  // "msn_watch30"
    public let kind: Kind
    public let title: String               // lokalize: "30 dakika izle"
    public let rewardCoins: Int
    public let target: Int                 // hedef değer (dakika, adet…)
    public let progress: Int               // mevcut ilerleme (server hesaplar)
    public let state: State                // .inProgress | .claimable | .claimed
    public let resetPolicy: ResetPolicy    // .daily | .weekly | .oneTime
    public let expiresAt: Date?            // earned coin ödülünün son kullanma bilgisi değil,
                                           // görevin kendisinin bitiş zamanı

    public enum Kind: String, Codable, Sendable, UnknownDecodable {
        case watchMinutes, favoriteSeries, shareSeries, enableNotifications,
             linkAccount, watchAd, unknown
    }
    public enum State: String, Codable, Sendable, UnknownDecodable {
        case inProgress, claimable, claimed, unknown
    }
    public enum ResetPolicy: String, Codable, Sendable, UnknownDecodable {
        case daily, weekly, oneTime, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `id` | String | hayır | Claim endpoint'i bu ID'yi alır |
| `kind` | enum | hayır | İstemci ikon/derin bağlantı eşler (örn. `enableNotifications` → izin akışı) |
| `title` | String | hayır | Sunucudan lokalize |
| `rewardCoins` | Int | hayır | Earned kesesine yazılır |
| `target` / `progress` | Int | hayır | OdulMerkezi ilerleme çubuğu; `progress >= target` olduğunda sunucu `state`i `claimable` yapar |
| `state` | enum | hayır | `claimed` görünümde soluk gösterilir |
| `resetPolicy` | enum | hayır | `daily` görevler UTC gece yarısı değil **kullanıcının saat diliminde** sıfırlanır (server, `X-Timezone` header'ından; istemci her istekte gönderir) |
| `expiresAt` | Date? | evet | — |

### 2.10 CheckInState

```swift
public struct CheckInState: Codable, Sendable {
    public let cycleDay: Int               // 1...7 — 7 günlük artan döngü
    public let todayClaimed: Bool
    public let todayReward: Int            // bugünün coin ödülü (10–50 aralığı, server belirler)
    public let schedule: [DayReward]       // 7 elemanlı takvim (OdulMerkezi görünümü)
    public let streakDays: Int             // kesintisiz gün sayısı
    public let streakBonusAt: Int?         // bir sonraki streak bonusunun eşik günü
    public let streakBonusCoins: Int?

    public struct DayReward: Codable, Sendable {
        public let day: Int                // 1...7
        public let coins: Int
        public let claimed: Bool
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `cycleDay` | Int | hayır | Gün atlanırsa sunucu döngüyü 1'e döndürür (kural `07-retention-gamification.md`) |
| `todayClaimed` | Bool | hayır | OdulMerkezi check-in butonu durumu |
| `todayReward` | Int | hayır | — |
| `schedule` | [DayReward] | hayır | Her zaman 7 eleman |
| `streakDays` | Int | hayır | — |
| `streakBonusAt` / `streakBonusCoins` | Int? | evet | "3 gün daha → +100 coin" teşvik metni |

### 2.11 WatchProgress

```swift
public struct WatchProgress: Codable, Sendable {
    public let episodeId: String
    public let seriesId: String
    public let positionSec: Double         // son izleme konumu
    public let durationSec: Double
    public let completed: Bool             // >= %90 izlendi (server kuralı da aynı)
    public let watchedAt: Date             // son izleme anı (cihaz saati, sunucu düzeltir)
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `episodeId` / `seriesId` | String | hayır | — |
| `positionSec` | Double | hayır | 0 ≤ değer ≤ `durationSec` |
| `durationSec` | Double | hayır | Çift kaynak doğrulaması (asset süresi değişirse sunucu normalize eder) |
| `completed` | Bool | hayır | "Devam Et" rafında tamamlanmış bölüm gösterilmez; dizinin sonraki bölümü önerilir |
| `watchedAt` | Date | hayır | Çakışma çözümü: **en yeni `watchedAt` kazanır** (last-write-wins, §3.3) |

### 2.12 FeedItem

`GET /feed` heterojen kart listesi döner; `type` alanıyla ayrıştırılır. Faz 1'de tek tip (`episode`) baskındır; ileride araya öneri kartları girebilir.

```swift
public struct FeedItem: Codable, Identifiable, Sendable {
    public let id: String                  // feed item ID (episode ID DEĞİL; dedup için)
    public let type: ItemType
    public let episode: Episode?           // type == .episode
    public let series: Series              // her item'da bağlam için mevcut
    public let progress: WatchProgress?    // kullanıcı bu bölümü yarım bırakmışsa
    public let reason: String?             // lokalize öneri gerekçesi ("Romantik izlediğin için")

    public enum ItemType: String, Codable, Sendable, UnknownDecodable {
        case episode, seriesPromo, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `id` | String | hayır | Aynı bölüm feed'e iki kez düşerse ayrı `id`; istemci `episode.id` üzerinden de dedup yapar |
| `type` | enum | hayır | `.unknown` item **render edilmez, atlanır** (ileri uyumluluk) |
| `episode` | Episode? | koşullu | `.episode` için zorunlu |
| `series` | Series | hayır | PlayerFeed overlay'i (başlık, favori butonu) buradan beslenir |
| `progress` | WatchProgress? | evet | Varsa oynatma bu konumdan başlar (`04-player-engine.md`) |
| `reason` | String? | evet | — |

**Feed sözleşme kuralı (kanon §3):** Sunucu, bölüm ilerledikçe **aynı dizinin sonraki bölümünü**, dizi bitince/atlanınca **yeni dizi önerisini** sıralar. İstemci sıralamaya müdahale etmez; yalnız yerel `progress` bilgisini başlangıç konumu için kullanır.

### 2.13 Banner ve Collection (Kesfet)

```swift
public struct Banner: Codable, Identifiable, Sendable {
    public let id: String                  // "bnr_summer01"
    public let imageURL: URL               // yatay hero görseli
    public let deeplink: URL               // shortseries://series/srs_x veya https universal link
    public let title: String?
    public let startsAt: Date
    public let endsAt: Date                // istemci süresi geçmiş banner'ı göstermez
}

public struct Collection: Codable, Identifiable, Sendable {
    public let id: String                  // "col_trending"
    public let kind: Kind                  // .trending | .new | .top10 | .editorial | .genre
    public let title: String               // lokalize raf başlığı
    public let seriesList: [Series]        // raf içeriği (ilk sayfa, max 20)
    public let nextCursor: String?         // raf "tümünü gör" sayfalaması

    public enum Kind: String, Codable, Sendable, UnknownDecodable {
        case trending, new, top10, editorial, genre, unknown
    }
}
```

| Alan | Tip | Nullable | Açıklama |
|---|---|---|---|
| `Banner.deeplink` | URL | hayır | Router (Coordinator) çözer — bkz. `02-ekran-haritasi-navigasyon.md` |
| `Banner.startsAt/endsAt` | Date | hayır | Cache'lenen banner süresi dolunca istemci gizler (offline dahil) |
| `Collection.kind` | enum | hayır | Kanon rafları: Trend, Yeni, Top 10 (`trending`, `new`, `top10`) |
| `Collection.seriesList` | [Series] | hayır | — |
| `Collection.nextCursor` | String? | evet | §7.1 cursor kalıbı |

---

## 3. SwiftData yerel şema

### 3.1 Ne lokalde tutulur, ne tutulmaz

| Veri | Yerel? | Neden |
|---|---|---|
| WatchProgress (izleme geçmişi + kaldığı yer) | **Evet — SwiftData** | Offline "Devam Et"; anında UI; upload kuyruğu |
| Favoriler (Listem) | **Evet — SwiftData** | Optimistic toggle + offline görünürlük |
| Katalog cache metadata (Series/Episode snapshot + ETag) | **Evet — SwiftData** | Soğuk açılış ve offline raflar |
| Feed son sayfa snapshot'ı | Evet — SwiftData (tek kayıt) | Splash ön-yükleme + offline PlayerFeed başlangıcı |
| Wallet bakiyesi | Hayır — bellekte (`WalletStore` actor) + son değer UserDefaults'ta salt-okunur gösterim kopyası | Para verisi cihazda kalıcı otorite olamaz |
| Unlock kayıtları | Hayır — sunucu; bellekte oturum cache'i | Entitlement server otoritatif |
| Token'lar | Keychain | Kanon §2 |
| Ayarlar/flag'ler | UserDefaults | Kanon §2 |
| Video segmentleri | AVAssetDownloadTask + disk cache (~200 MB LRU); metadata defteri SwiftData'da (`CachedAssetRecordEntity`, §3.2) | `04-player-engine.md` kapsamı |

### 3.2 SwiftData modelleri

Bu envanter yerel şemanın **tek doğruluk kaynağıdır**: diğer dokümanlar (`03-mimari.md` §9 dahil) entity'lere buradaki adlarla atıf yapar. `03-mimari.md`de kısaltma olarak geçen `MyListEntry` bu envanterdeki `FavoriteEntity`, `CachedAssetRecord` ise `CachedAssetRecordEntity`dir — tek kanonik ad buradakidir, yeni metinlerde başka ad kullanılmaz.

```swift
import SwiftData

@Model
final class WatchProgressEntity {
    @Attribute(.unique) var episodeId: String
    var seriesId: String
    var positionSec: Double
    var durationSec: Double
    var completed: Bool
    var watchedAt: Date
    var syncState: Int          // 0 = synced, 1 = pendingUpload
    init(...) { ... }
}

@Model
final class FavoriteEntity {
    @Attribute(.unique) var seriesId: String
    var addedAt: Date
    var syncState: Int          // 0 = synced, 1 = pendingAdd, 2 = pendingRemove
    init(...) { ... }
}

@Model
final class CachedSeriesEntity {
    @Attribute(.unique) var seriesId: String
    var payload: Data           // Series JSON snapshot (Codable ile encode)
    var payloadSchemaVersion: Int  // cache şema evrimi (aşağıdaki kural)
    var etag: String?
    var fetchedAt: Date
    var lastAccessAt: Date      // LRU tahliye için
    init(...) { ... }
}

@Model
final class CachedEpisodeListEntity {
    @Attribute(.unique) var seriesId: String
    var payload: Data           // [Episode] snapshot — access alanı BAYAT kabul edilir
    var payloadSchemaVersion: Int
    var etag: String?
    var fetchedAt: Date
    var lastAccessAt: Date      // LRU tahliye için (CachedSeriesEntity ile aynı politika)
    init(...) { ... }
}

@Model
final class FeedSnapshotEntity {
    @Attribute(.unique) var key: String   // "forYou"
    var payload: Data                     // [FeedItem] ilk sayfa
    var payloadSchemaVersion: Int
    var fetchedAt: Date
    init(...) { ... }
}

@Model
final class CachedAssetRecordEntity {     // video cache metadata defteri (04-player-engine.md §7.2, görev SS-043)
    @Attribute(.unique) var episodeId: String
    var localAssetPath: String            // AVAssetDownloadTask çıktısının yerel konumu
    var sizeBytes: Int64
    var lastAccessAt: Date                // ~200 MB LRU tahliyesinin sıralama anahtarı
    var watchCompleted: Bool              // izlenmiş bölümler eviction'da önceliklidir
    init(...) { ... }
}
```

Tahliye politikası: `CachedSeriesEntity`/`CachedEpisodeListEntity` toplamı 500 kaydı veya 20 MB'ı aşarsa `lastAccessAt` sırasıyla LRU silinir. `CachedAssetRecordEntity`, ~200 MB video cache bütçesinin defteridir; eviction'ı `EpisodeCacheStore` yürütür (`04-player-engine.md` §7.2). `WatchProgressEntity` ve `FavoriteEntity` tahliye edilmez (kullanıcı verisi).

**Cache şema evrimi kuralı:** `payload` taşıyan cache entity'leri `payloadSchemaVersion` alanı taşır. Okumada payload decode edilemiyorsa veya `payloadSchemaVersion` istemcinin beklediğinden eskiyse kayıt **sessizce silinir ve sunucudan tazelenir; cache entity'leri için SwiftData migration YAZILMAZ** (cache her zaman yeniden üretilebilir veridir). Migration yalnız kullanıcı verisi entity'leri (`WatchProgressEntity`, `FavoriteEntity`) için söz konusudur.

### 3.3 Senkronizasyon stratejisi

**İlke: server otoritatif, istemci optimistic.**

| Veri | Yazma yönü | Optimistic davranış | Çakışma çözümü |
|---|---|---|---|
| WatchProgress | çift yön | Lokale anında yaz (`syncState=pendingUpload`); 10 sn'de bir veya bölüm değişince batch `POST /playback/progress` | Sunucu her kayıt için `watchedAt` karşılaştırır, **en yeni kazanır**; yanıttaki birleşik liste lokal tabloyu ezer |
| Favoriler | çift yön | Toggle anında UI + lokal; arka planda `PUT/DELETE /me/favorites/{seriesId}` | Sunucu son işlem kazanır; 404/409 durumunda lokal kayıt sunucu durumuna çekilir |
| Wallet/Unlock | yalnız sunucu | UnlockSheet onayında bakiye lokalde anında düşülür (optimistic); yanıt gelince sunucu değeri yazılır | Hata → optimistic düşüm **geri alınır** + hata sözleşmesi (§10) uygulanır |
| Katalog/feed | yalnız sunucu → cache | — | ETag/`updatedAt` tazeliği; TTL §7.2 |
| Missions/CheckIn | yalnız sunucu | Claim butonu anında "alındı" durumuna geçer; hata → geri al + toast | Idempotency-Key sayesinde çift claim imkânsız |

**Misafir → bağlı hesap geçişi:** `POST /auth/link` başarılı olduğunda `userId` DEĞİŞMEZ (aynı hesaba kimlik eklenir). Sunucu tarafında birleşme gerekirse (`409 ACCOUNT_ALREADY_LINKED` sonrası kullanıcı "mevcut hesabıma geç" derse) istemci **tüm lokal `pendingUpload` kayıtlarını flush eder**, sonra `POST /auth/switch` ile yeni kimliğe geçer ve SwiftData store'u sıfırlayıp sunucudan yeniden çeker. Detay akış: `02-ekran-haritasi-navigasyon.md`.

---

## 4. REST API sözleşmesi

Base URL: `https://api.shortseries.app/v1` (staging: `https://api.staging.shortseries.app/v1`). Tüm yollar bu köke görelidir.

### 4.1 Endpoint özet tablosu

| # | Method + Path | Auth | Idempotency-Key | Amaç / Tüketen ekran |
|---|---|---|---|---|
| 1 | `POST /auth/guest` | — | — | Anonim misafir hesabı + token (Splash) |
| 2 | `POST /auth/refresh` | refresh token | — | Access token yenileme |
| 3 | `POST /auth/link` | ✓ | — | Apple/Google kimlik bağlama (Profil); e-posta alt akışı §4.2.1 |
| 4 | `GET /me` | ✓ | — | UserProfile (Profil, Ayarlar) |
| 5 | `PATCH /me` | ✓ | — | Dil/tercih güncelleme (Ayarlar, Onboarding) |
| 6 | `GET /feed?cursor=&limit=` | ✓ | — | For You akışı (PlayerFeed / Ana Sayfa) |
| 7 | `GET /series/{id}` | ✓ | — | DiziDetay |
| 8 | `GET /series/{id}/episodes?cursor=` | ✓ | — | BolumListesi, DiziDetay ızgara |
| 9 | `GET /discover` | ✓ | — | Kesfet rafları (banner + koleksiyonlar) |
| 10 | `GET /collections/{id}?cursor=` | ✓ | — | Raf "tümünü gör" |
| 11 | `POST /playback/authorize` | ✓ | — | İmzalı HLS URL (+ Faz 2 FairPlay) |
| 12 | `POST /playback/progress` | ✓ | — | Progress batch upload |
| 13 | `GET /wallet` | ✓ | — | Bakiye (CoinMagazasi, OdulMerkezi, UnlockSheet) |
| 14 | `GET /wallet/transactions?cursor=` | ✓ | — | İşlem geçmişi (Profil) |
| 15 | `POST /wallet/unlock` | ✓ | **zorunlu** | Coin ile bölüm kilidi açma (UnlockSheet) |
| 16 | `POST /iap/verify` | ✓ | **zorunlu** | StoreKit 2 transaction doğrulama (CoinMagazasi, VIPAbonelik) |
| 17 | `GET /subscription` | ✓ | — | SubscriptionStatus (VIPAbonelik, Profil) |
| 18 | `GET /rewards/checkin` | ✓ | — | CheckInState (OdulMerkezi) |
| 19 | `POST /rewards/checkin/claim` | ✓ | **zorunlu** | Günlük check-in ödülü |
| 20 | `GET /missions` | ✓ | — | Görev listesi (OdulMerkezi) |
| 21 | `POST /missions/{id}/claim` | ✓ | **zorunlu** | Görev ödülü |
| 22 | `POST /rewards/ad-unlock` | ✓ | **zorunlu** | Rewarded ad ile kilit açma (Faz 2, UnlockSheet) |
| 23 | `GET /search/suggest?q=` | ✓ | — | Otomatik tamamlama (Arama) |
| 24 | `GET /search?q=&cursor=` | ✓ | — | Arama sonuçları |
| 25 | `GET /search/popular` | ✓ | — | Popüler aramalar (Arama boş durumu) |
| 26 | `PUT /me/favorites/{seriesId}` / `DELETE …` | ✓ | — (doğal idempotent) | Favori ekle/çıkar (Listem, DiziDetay) |
| 27 | `GET /me/favorites?cursor=` | ✓ | — | Listem → Favoriler |
| 28 | `GET /me/history?cursor=` | ✓ | — | Listem → Devam Et (sunucu birleşik geçmiş) |
| 29 | `POST /devices` | ✓ | — (upsert) | APNs token kaydı |
| 30 | `DELETE /devices/{deviceId}` | ✓ | — | Push kaydı silme (çıkış/kapatma) |
| 31 | `GET /config` | ✓ | — | Remote config + feature flags (Splash) |
| 32 | `GET /wallet/packages` | ✓ | — | Coin paket kataloğu: bonus kademeleri + ilk yükleme teklifi (CoinMagazasi) |
| 33 | `POST /events` | ✓ | — (`event_id` ile dedupe) | Analitik event batch ingest (AnalyticsKit) |
| 34 | `POST /auth/email/start` | link: ✓ / reset: — | — | E-posta doğrulama kodu gönderme (F2, §4.2.1) |
| 35 | `POST /auth/email/verify` | link: ✓ / reset: — | — | Doğrulama kodu teyidi (F2, §4.2.1) |
| 36 | `POST /auth/email/password` | — (`passwordToken`) | — | Şifre belirleme / sıfırlama tamamlama (F2, §4.2.1) |
| 37 | `POST /auth/email/login` | — | — | E-posta+şifre ile oturum açma (F2, §4.2.1) |

### 4.2 Auth

**`POST /auth/guest`** — ilk açılışta, token yokken çağrılır. İstek gövdesi cihaz kimliği taşır; sunucu aynı `deviceId` için mevcut misafir hesabını döndürür (yeniden yükleme senaryosu — Keychain'de token kalmışsa bu adım atlanır).

```json
// İstek
{ "deviceId": "D4A1C2E0-...", "platform": "ios", "appVersion": "1.0.0", "locale": "en-US" }

// 200 Yanıt
{
  "userId": "usr_ab12cd",
  "accessToken": "eyJhbGciOi...",
  "accessTokenExpiresIn": 3600,
  "refreshToken": "rt_8Kj2...",
  "profile": { "id": "usr_ab12cd", "displayName": null, "accountState": "guest", ... }
}
```

**`POST /auth/refresh`** — access token süresi dolduğunda (`401 TOKEN_EXPIRED` alınınca veya proaktif olarak süre dolmadan 5 dk önce).

```json
// İstek
{ "refreshToken": "rt_8Kj2..." }
// 200 Yanıt: yeni accessToken + rotasyonlu yeni refreshToken
{ "accessToken": "eyJ...", "accessTokenExpiresIn": 3600, "refreshToken": "rt_9Lm3..." }
```

Refresh de 401 dönerse istemci sessizce `POST /auth/guest`e döner; kullanıcı bağlı hesapsa yeniden giriş istenir (Profil'e yönlendirme). **Eşzamanlılık kuralı:** `AppFoundation` içindeki `AuthSession` actor'ü aynı anda tek refresh yürütür; bekleyen istekler yeni token'ı paylaşır (thundering herd önlenir).

**`POST /auth/link`** — misafir hesabına kimlik bağlama.

```json
// İstek (Apple örneği)
{ "provider": "apple", "identityToken": "<ASAuthorization JWT>", "email": null }

// 200: güncellenmiş UserProfile (accountState: "linked")
// 409 ACCOUNT_ALREADY_LINKED: bu Apple kimliği başka hesaba bağlı
{
  "error": {
    "code": "ACCOUNT_ALREADY_LINKED",
    "message": "Bu kimlik başka bir hesaba bağlı.",
    "details": { "existingUserMasked": "usr_**12ef", "switchToken": "swt_77x..." }
  },
  "requestId": "req_01H..."
}
```

409 durumunda UI iki seçenek sunar: "Mevcut hesabıma geç" (`POST /auth/switch` + `switchToken`) veya vazgeç. Geçişte lokal veri kuralı §3.3'te.

#### 4.2.1 E-posta bağlama alt akışı (F2 — ONB-06)

Apple/Google `provider + identityToken` kalıbıyla `POST /auth/link`ten geçer; **e-posta bağlama bu kalıba uymaz** (identityToken yoktur) ve aşağıdaki doğrulama-kodu akışını kullanır. Uçlar F2 kapsamındadır (`09-yol-haritasi-tasklar.md`); sözleşme F0 sonunda diğer uçlarla birlikte donar.

**`POST /auth/email/start`** — doğrulama kodu gönderir. `intent: "link"` için misafir/bağlı token zorunlu; `intent: "reset"` token'sız çağrılabilir (şifremi unuttum, oturum yokken).

```json
// İstek
{ "email": "user@example.com", "intent": "link" }   // "link" | "reset"

// 204 No Content — 6 haneli kod e-postaya gönderildi (10 dk geçerli)
// 409 EMAIL_IN_USE (yalnız intent=link): e-posta başka hesaba bağlı → UI "bu e-postayla giriş yap" önerir
// 429 RATE_LIMITED: kod isteme sıklık limiti; Retry-After'a uyulur
```

**`POST /auth/email/verify`** — kodu teyit eder. `intent=link` akışında e-posta hesaba bağlanır (`accountState: "linked"`); her iki akışta şifre adımı için kısa ömürlü `passwordToken` döner.

```json
// İstek
{ "email": "user@example.com", "code": "482913" }

// 200 Yanıt (link akışı)
{ "passwordToken": "pwt_5f0a...", "profile": { "id": "usr_ab12cd", "accountState": "linked", "linkedProviders": ["email"], ... } }

// 400 CODE_INVALID — details.attemptsLeft ile kalan deneme; 0'da yeni kod istenir
// 410 CODE_EXPIRED — "yeni kod gönder" durumu
```

**`POST /auth/email/password`** — şifre belirleme (link) ve sıfırlama tamamlama (reset) için ortak uç; kimlik `passwordToken` ile taşınır, `Authorization` header'ı gerekmez.

```json
// İstek
{ "passwordToken": "pwt_5f0a...", "password": "••••••••" }

// 204 No Content
// 422 WEAK_PASSWORD — details.policy lokalize kural metni taşır (min 8 karakter, harf + rakam)
// 410 CODE_EXPIRED — passwordToken süresi dolmuş; akış baştan
```

**`POST /auth/email/login`** — e-posta+şifre ile oturum açma; token'sız çağrılır (örn. refresh zinciri koptuğunda bağlı hesap için "yeniden giriş istenir" yolu, §4.2).

```json
// İstek
{ "email": "user@example.com", "password": "••••••••", "deviceId": "D4A1C2E0-..." }

// 200 Yanıt — POST /auth/guest ile aynı token zarfı (userId + accessToken + refreshToken + profile)
// 401 INVALID_CREDENTIALS — form hatası; hangi alanın yanlış olduğu söylenmez
// 429 RATE_LIMITED — brute-force koruması; Retry-After'a uyulur
```

Akış özetleri:
- **Bağlama (link):** `start(intent: link)` → `verify` (e-posta bağlanır) → `password` (şifre belirlenir). `userId` değişmez (§3.3 kuralı — `POST /auth/link` ile aynı).
- **Şifre sıfırlama (reset):** `start(intent: reset)` → `verify` → dönen `passwordToken` ile `password`. Ayrı bir reset ucu yoktur; aynı üç uç iki akışı da taşır.
- **Giriş sonrası lokal veri:** cihazda misafir oturumu varken `login` yapılırsa kimlik değişir; §3.3'teki hesap geçişi kuralı uygulanır (`pendingUpload` flush → SwiftData store sıfırla → sunucudan çek).

### 4.3 Feed

**`GET /feed?cursor=&limit=10`** — PlayerFeed (Ana Sayfa) beslemesi. Uygulama doğrudan video ile açıldığı için Splash bu isteği arka planda başlatır ve ilk yanıtı `FeedSnapshotEntity`e yazar.

```json
// 200 Yanıt
{
  "items": [
    {
      "id": "fi_001",
      "type": "episode",
      "series": { "id": "srs_9f2c1a", "title": "Midnight Heir", "freeEpisodeCount": 8, ... },
      "episode": {
        "id": "ep_5410be", "seriesId": "srs_9f2c1a", "index": 1,
        "durationSec": 92, "thumbnailURL": "https://cdn.shortseries.app/t/ep_5410be.jpg",
        "access": { "kind": "free", "unlockPrice": null, "adUnlockEligible": false },
        "publishedAt": "2026-06-20T00:00:00Z"
      },
      "progress": null,
      "reason": null
    }
  ],
  "nextCursor": "eyJvZmZzZXQiOiIxMCJ9",
  "ttlSec": 300
}
```

Davranış kuralları:
- İstemci `nextCursor` ile **görünen index son 3 item'a yaklaşınca** sonraki sayfayı ister (prefetch eşiği `04-player-engine.md` ile hizalı).
- `ttlSec` içinde uygulama foreground'a dönerse feed yenilenmez; aşılmışsa mevcut liste korunur, arkada tazelenir ve **yalnız kullanıcının henüz görmediği kuyruk** değiştirilir (izleme ortasında içerik altından kaymaz — kabul kriteri).
- Kilitli bölüm feed'e gelebilir (`access.kind == "locked"`): PlayerFeed bölüm başında UnlockSheet akışını tetikler; sunucu bunu yalnız kullanıcının izleme bağlamında sıradaki bölüm olduğunda yapar.

### 4.4 Playback — imzalı URL ve progress

**`POST /playback/authorize`** — her bölüm oynatımından önce çağrılır (istisna: coin ile unlock başarısı — unlock 200 yanıtı `playback` bloğunu zaten taşır, §4.5). Prefetch için de aynı endpoint kullanılır (PlayerPool sıradaki 1–2 bölüm için önceden yetki alır).

```json
// İstek
{ "episodeId": "ep_5410be" }

// 200 Yanıt (Faz 1 — clear HLS + imzalı URL)
{
  "episodeId": "ep_5410be",
  "playbackURL": "https://cdn.shortseries.app/hls/ep_5410be/master.m3u8?tk=eyJ...&exp=1783190400",
  "expiresAt": "2026-07-11T12:00:00Z",
  "drm": null
}

// 200 Yanıt (Faz 2 — FairPlay)
{
  "episodeId": "ep_5410be",
  "playbackURL": "https://cdn.shortseries.app/hls/ep_5410be/master.m3u8?tk=...",
  "expiresAt": "2026-07-11T12:00:00Z",
  "drm": {
    "scheme": "fairplay",
    "licenseURL": "https://drm.shortseries.app/fps/license",
    "certificateURL": "https://drm.shortseries.app/fps/cert",
    "licenseToken": "lt_abc..."
  }
}

// 403 EPISODE_LOCKED — kilitli bölüm, unlock yok
{
  "error": {
    "code": "EPISODE_LOCKED",
    "message": "Bu bölüm kilitli.",
    "details": { "unlockPrice": 60, "adUnlockEligible": true, "wallet": { "purchasedCoins": 20, "earnedCoins": 15 } }
  },
  "requestId": "req_..."
}
```

- `403 EPISODE_LOCKED` yanıtındaki `details`, UnlockSheet'in tek istekle açılabilmesi için fiyat + bakiye taşır (ekstra round-trip yok — kabul kriteri: kilitli bölüme swipe → UnlockSheet < 300 ms). `details.unlockPrice` null olabilir — coin yolu kapalı kilit (§2.2 genişleme noktası).
- İmzalı URL süresi ve yenileme akışı §8'de.
- Token, URL query'sindedir; `AVURLAsset` ek header gerektirmez (CDN uyumluluğu).

**`POST /playback/progress`** — batch, at-least-once teslim. İstemci 10 sn'de bir, bölüm geçişinde ve `applicationDidEnterBackground`da flush eder.

```json
// İstek
{
  "entries": [
    { "episodeId": "ep_5410be", "seriesId": "srs_9f2c1a", "positionSec": 61.4,
      "durationSec": 92.0, "completed": false, "watchedAt": "2026-07-11T09:31:02Z" },
    { "episodeId": "ep_5410aa", "seriesId": "srs_9f2c1a", "positionSec": 88.0,
      "durationSec": 90.0, "completed": true,  "watchedAt": "2026-07-11T09:29:30Z" }
  ]
}

// 200 Yanıt — sunucunun birleşik (diğer cihazlar dahil) son durumu
{ "merged": [ { "episodeId": "ep_5410be", "positionSec": 61.4, "completed": false, "watchedAt": "2026-07-11T09:31:02Z", "seriesId": "srs_9f2c1a", "durationSec": 92.0 } ] }
```

Aynı entry'nin iki kez gönderilmesi zararsızdır (`watchedAt` eşit/eski ise sunucu yok sayar) — bu yüzden Idempotency-Key gerekmez.

### 4.5 Wallet ve unlock

**`GET /wallet`**

```json
{ "purchasedCoins": 120, "earnedCoins": 45,
  "earnedExpiringSoon": { "amount": 30, "expiresAt": "2026-07-14T00:00:00Z" },
  "firstTopUpEligible": false,
  "updatedAt": "2026-07-11T09:00:00Z", "version": 118 }
```

**`GET /wallet/packages`** — CoinMagazasi paket kataloğu. Coin adetleri, bonus kademeleri ve rozet metinleri sunucudan gelir (istemcide hardcoded coin/bonus yoktur — §1 kural 5); USD fiyat StoreKit 2 `Product.displayPrice`ten okunur, API'de görünmez (§1 kural 9).

```json
// 200 Yanıt
{
  "packages": [
    { "productId": "com.shortseries.coins.tier1", "baseCoins": 100,   "bonusPercent": 0,   "bonusCoins": 0,     "firstTopUpBonusCoins": 100,   "badge": null },
    { "productId": "com.shortseries.coins.tier2", "baseCoins": 500,   "bonusPercent": 10,  "bonusCoins": 50,    "firstTopUpBonusCoins": 500,   "badge": null },
    { "productId": "com.shortseries.coins.tier3", "baseCoins": 1000,  "bonusPercent": 20,  "bonusCoins": 200,   "firstTopUpBonusCoins": 1000,  "badge": "EN POPÜLER" },
    { "productId": "com.shortseries.coins.tier4", "baseCoins": 2000,  "bonusPercent": 40,  "bonusCoins": 800,   "firstTopUpBonusCoins": 2000,  "badge": null },
    { "productId": "com.shortseries.coins.tier5", "baseCoins": 5000,  "bonusPercent": 70,  "bonusCoins": 3500,  "firstTopUpBonusCoins": 5000,  "badge": null },
    { "productId": "com.shortseries.coins.tier6", "baseCoins": 10000, "bonusPercent": 100, "bonusCoins": 10000, "firstTopUpBonusCoins": 10000, "badge": "EN İYİ DEĞER" }
  ],
  "firstTopUpEligible": true,
  "ttlSec": 600
}
```

Davranış kuralları:
- `packages` dizisinin sırası UI sırasıdır; `productId` seti `GET /config.coinProducts` ile aynıdır (kanon: 6 kademe, %0→%100 artan bonus). Buradaki coin adetleri örnektir — gerçek değerler sunucu konfigürasyonudur, istemci sürümünden bağımsız değişebilir.
- `firstTopUpEligible == true` iken CoinMagazasi ilk yükleme teklifini çizer: `bonusCoins` yerine `firstTopUpBonusCoins` gösterilir (2x teklif — toplam `baseCoins + firstTopUpBonusCoins`). Bu bayrak `Wallet.firstTopUpEligible` (§2.5) ile aynı sunucu durumunu yansıtır; hangi bonusun fiilen uygulandığını sunucu `POST /iap/verify` yanıtındaki `granted.firstPurchaseBonusApplied` ile bildirir (§4.6). İstemci bonus hesaplamaz.
- `badge` sunucudan lokalize gelir ("EN POPÜLER", "EN İYİ DEĞER" vb.); `null` ise rozet çizilmez. Tanınmayan ek alanlar yutulur (§1 kural 10).
- Cache: `Cache-Control: private, max-age=600`; CoinMagazasi her açılışta stale-while-revalidate ile tazeler (bonus kademeleri kampanyayla değişebilir).

**`POST /wallet/unlock`** — `Idempotency-Key` **zorunlu**; istemci UnlockSheet onay dokunuşunda üretir ve retry'larda aynı anahtarı yeniden kullanır.

```json
// İstek  (Header: Idempotency-Key: 4d5e6f70-....)
{ "episodeId": "ep_5410be", "expectedPrice": 60 }

// 200 Yanıt
{
  "unlock": { "id": "ulk_3c9d10", "episodeId": "ep_5410be", "seriesId": "srs_9f2c1a",
              "method": "coins", "coinsSpent": 60, "unlockedAt": "2026-07-11T09:32:00Z" },
  "wallet": { "purchasedCoins": 105, "earnedCoins": 0, "earnedExpiringSoon": null,
              "firstTopUpEligible": false, "updatedAt": "2026-07-11T09:32:00Z", "version": 119 },
  "transactions": [
    { "id": "txn_901", "type": "episodeUnlock", "amount": -45, "bucket": "earned",  "balanceAfter": 120, "refId": "ep_5410be", "note": null, "createdAt": "2026-07-11T09:32:00Z" },
    { "id": "txn_902", "type": "episodeUnlock", "amount": -15, "bucket": "purchased", "balanceAfter": 105, "refId": "ep_5410be", "note": null, "createdAt": "2026-07-11T09:32:00Z" }
  ],
  "playback": {
    "episodeId": "ep_5410be",
    "playbackURL": "https://cdn.shortseries.app/hls/ep_5410be/master.m3u8?tk=eyJ...&exp=1783190400",
    "expiresAt": "2026-07-11T12:00:00Z",
    "drm": null
  }
}
```

Davranış kuralları ve edge case'ler:
- **Unlock yanıtı `playback` taşır; istemci ayrıca authorize çağırmaz.** `playback` bloğu `POST /playback/authorize` 200 yanıtıyla birebir aynı şemadır (§4.4; Faz 2'de `drm` alanı dahil). Unlock başarısında oynatma doğrudan bu blokla başlatılır — ekstra round-trip olmadığı için kabul kriteri "unlock başarısı → ilk video karesi < 1 sn" sağlanır (ekran akışı: `02-ekran-haritasi-navigasyon.md`; player tarafı: `04-player-engine.md`). Blok opsiyoneldir: yanıt herhangi bir nedenle `playback` içermiyorsa istemci normal `POST /playback/authorize` yoluna düşer. `expiresAt` ve yenileme kuralları §8.1 ile aynıdır.
- `expectedPrice`, istemcinin UnlockSheet'te gösterdiği fiyattır. Sunucudaki güncel `unlockPrice` farklıysa **409 `PRICE_CHANGED`** döner (`details.currentPrice` ile); istemci sheet'i yeni fiyatla günceller, sessizce farklı tutar çekmez.
- Bakiye yetersizse **402 `INSUFFICIENT_COINS`** (`details.shortfall` coin ile); UnlockSheet CoinMagazasi'na akar (kanon §3 akışı). Satın alma tamamlanınca UnlockSheet'e dönülür ve unlock **yeni** Idempotency-Key ile tekrarlanır.
- Aynı anahtar ile tekrar istek → sunucu **aynı 200 gövdesini** döner (çift harcama yok). Aynı anahtar, farklı gövde → `422 IDEMPOTENCY_PAYLOAD_MISMATCH`.
- Bölüm zaten açıksa (başka cihazdan) → `200` + `alreadyUnlocked: true` semantiği yerine sunucu mevcut `UnlockRecord`u döner, `transactions` boş olur. İstemci farkı umursamaz.
- Harcama önceliği (earned önce) yanıttaki `transactions` satırlarından görünür; istemci hesaplamaz.

**`GET /wallet/transactions?cursor=&limit=20`** — §7.1 cursor kalıbıyla `CoinTransaction` sayfası döner.

### 4.6 IAP doğrulama

StoreKit 2 kullanılır; istemci satın alma sonrası **imzalı transaction JWS**'ini backend'e gönderir. Sunucu App Store Server API ile doğrular; abonelik yaşam döngüsü App Store Server Notifications V2 ile sunucuya akar (istemciden bağımsız).

**`POST /iap/verify`** — `Idempotency-Key` zorunlu (anahtar olarak `transactionId` türevi önerilir: `iap-<originalTransactionId>-<transactionId>`).

```json
// İstek
{
  "productId": "com.shortseries.coins.tier3",
  "jwsTransaction": "eyJhbGciOiJFUzI1NiIs...",
  "kind": "consumable"            // "consumable" | "subscription"
}

// 200 Yanıt (coin paketi)
{
  "granted": { "coins": 1000, "bonusCoins": 200, "firstPurchaseBonusApplied": false },
  "wallet": { "purchasedCoins": 1205, "earnedCoins": 0, "earnedExpiringSoon": null,
              "firstTopUpEligible": false, "updatedAt": "...", "version": 124 },
  "transaction": { "id": "txn_905", "type": "iapPurchase", "amount": 1200, "bucket": "purchased",
                   "balanceAfter": 1205, "refId": "com.shortseries.coins.tier3", "note": null, "createdAt": "..." }
}

// 200 Yanıt (abonelik)
{ "subscription": { "isVIP": true, "plan": "weekly", "expiresAt": "2026-07-18T09:35:00Z",
                    "willAutoRenew": true, "isInGracePeriod": false, "isInIntroOffer": true,
                    "dailyBonusCoins": 50, "dailyBonusClaimedToday": false } }

// 409 RECEIPT_ALREADY_PROCESSED — replay: sunucu ilk işlemin sonucunu aynen döner (200 ile eşdeğer gövde `details.original` içinde)
// 422 RECEIPT_INVALID — doğrulanamayan/sahte JWS; istemci StoreKit transaction'ı finish ETMEZ, destek akışına yönlendirir
```

İstemci kuralı: `Transaction.updates` dinleyicisi (`WalletKit`) her transaction'ı `POST /iap/verify`den **200 aldıktan sonra** `finish()` eder. Ağ yoksa transaction unfinished kalır ve sonraki açılışta yeniden denenir — coin kaybı imkânsızdır. Ürün kataloğu (`productId` listesi) `GET /config`ten gelir; coin adetleri, bonus kademeleri ve rozetler `GET /wallet/packages`tan okunur (§4.5); fiyat noktalarının pazarlama tanımı `06-monetizasyon.md`dedir (kanon: $0.99 / $4.99 / $9.99 / $19.99 / $49.99 / $99.99 + %0→%100 bonus, ilk yüklemeye 2x; VIP haftalık $5.99 — intro $3.99/ilk hafta —, aylık $14.99, yıllık $49.99). Rakip fiyatları kaynaklar arasında tutarsız raporlandığından nihai fiyat noktaları **lansman öncesi App Store'dan doğrulanmalıdır**.

### 4.7 Missions ve check-in

**`GET /rewards/checkin`** → `CheckInState` (bkz. §2.10 örnek şema).

**`POST /rewards/checkin/claim`** — `Idempotency-Key` zorunlu.

```json
// 200 Yanıt
{
  "reward": { "coins": 30, "bucket": "earned", "expiresAt": "2026-08-10T00:00:00Z" },
  "checkin": { "cycleDay": 3, "todayClaimed": true, "todayReward": 30, "streakDays": 3, ... },
  "wallet": { "purchasedCoins": 105, "earnedCoins": 30, ... , "version": 125 }
}

// 409 ALREADY_CLAIMED — bugün alınmış; istemci CheckInState'i yanıttaki `details.checkin` ile tazeler
```

**`GET /missions`** → `{ "missions": [Mission, ...] }`. **`POST /missions/{id}/claim`** aynı kalıptır; `state != claimable` ise `409 MISSION_NOT_CLAIMABLE` döner.

**`POST /rewards/ad-unlock`** (Faz 2) — rewarded ad tamamlama kanıtı sunucuda doğrulanır. İstek zarfı **sağlayıcı-bağımsızdır**: kanıt opak `proofPayload` içinde taşınır, sunucu `provider` alanına göre doğrulayıcı seçer (aktif sağlayıcıda sunucu-tarafı doğrulama — AdMob'da SSV; karar `06-monetizasyon.md`). Reklam sağlayıcı değişimi bu sözleşmeyi DEĞİŞTİRMEZ — yalnız yeni `provider` değeri ve sunucu tarafında yeni doğrulayıcı eklenir.

```json
// İstek  (Header: Idempotency-Key: 9a0b1c2d-....)
{
  "episodeId": "ep_5410bf",
  "proof": {
    "provider": "admob",
    "nonce": "adn_84f2...",                       // sağlayıcının S2S callback'iyle eşleşen tek kullanımlık değer
    "proofPayload": "<opak, sağlayıcıya özgü kanıt bloğu>"
  }
}

// 200 Yanıt — POST /wallet/unlock ile aynı zarf (§4.5): unlock (method: "rewardedAd", coinsSpent: 0) + wallet + playback
```

Günlük cap (kanon: 5–10, remote config) sunucuda uygulanır; aşımda `429 AD_UNLOCK_CAP_REACHED` + `details.resetsAt`. İstemci cap değerini `GET /config`ten okuyup UnlockSheet'te "Bugün 3/5 hakkın kaldı" gösterir ama asla kendi saymaz.

### 4.8 Search

**`GET /search/suggest?q=mid`** — debounce 250 ms, minimum 2 karakter.

```json
{ "suggestions": [ { "text": "midnight heir", "type": "series", "seriesId": "srs_9f2c1a" },
                   { "text": "midnight", "type": "query", "seriesId": null } ] }
```

**`GET /search?q=midnight&cursor=`** — sonuç ızgarası; `{ "results": [Series], "nextCursor": "..." }`. **`GET /search/popular`** — `{ "queries": ["ceo romance", "revenge", ...] }` (Arama boş durumu). Arama analitik eventleri `08-analitik-deney.md`de.

### 4.9 Notifications

**`POST /devices`** — APNs token kaydı; upsert semantiği (aynı `deviceId` günceller).

```json
// İstek
{ "deviceId": "D4A1C2E0-...", "apnsToken": "a1b2c3...", "environment": "production",
  "locale": "en-US", "timezone": "America/New_York", "notificationOptIn": true }
// 204 No Content
```

Token her app açılışında ve `didRegisterForRemoteNotificationsWithDeviceToken`da yeniden gönderilir (token rotasyonu). Bildirim tercihi kapatıldığında `notificationOptIn: false` ile güncellenir (kayıt silinmez — sunucu segmentasyonu için). Çıkışta `DELETE /devices/{deviceId}`.

### 4.10 Config

**`GET /config`** — Splash'ta çekilir, UserDefaults'a cache'lenir, 24 saat TTL + arka plan tazeleme. Feature flag'ler ve A/B deney atamaları da bu yanıttadır (`08-analitik-deney.md`).

```json
{
  "minSupportedVersion": "1.0.0",
  "coinProducts": ["com.shortseries.coins.tier1", "...tier2", "...tier3", "...tier4", "...tier5", "...tier6"],
  "vipProducts": ["com.shortseries.vip.weekly", "com.shortseries.vip.monthly", "com.shortseries.vip.yearly"],
  "adUnlockDailyCap": 5,
  "flags": { "rewardedAdsEnabled": false, "fairplayEnabled": false, "liveActivitiesEnabled": false },
  "experiments": [ { "key": "paywall_layout", "variant": "B" } ]
}
```

### 4.11 Analitik event ingest

**`POST /events`** — `AnalyticsKit` batch upload ucu. Event adları, ortak parametreler ve şema evrimi `08-analitik-deney.md`de tanımlıdır; buradaki sözleşme taşıma katmanıdır. Teslim garantisi **at-least-once**: istemci diske kuyruklar, yanıt alamadığı batch'i aynen tekrar gönderir; sunucu her event'i `event_id` (istemci üretimi **UUIDv7**, zaman sıralı) ile tekilleştirir — aynı `event_id` ikinci kez gelirse sessizce yok sayılır. Bu yüzden `Idempotency-Key` header'ı kullanılmaz.

```json
// İstek  (Header: Content-Encoding: gzip)
{
  "events": [
    {
      "event_id": "018f6c3e-7d2a-7cc0-9a3b-2f1e5d4c3b2a",
      "name": "video_start",
      "event_ts": 1783762262412,
      "session_id": "7b1f4e2a-0c3d-4a5b-9e8f-6d7c8b9a0e1f",
      "user_id": "usr_ab12cd",
      "session_seq": 4,
      "schema_version": 1,
      "ab_variants": "exp_free_eps:v8,exp_unlock_sheet:control",
      "app_version": "1.0.0", "build_number": 42,
      "os_version": "17.5.1", "device_model": "iPhone15,3",
      "locale": "en-US", "network_type": "wifi", "is_vip": false,
      "params": { "series_id": "srs_9f2c1a", "episode_id": "ep_5410be", "episode_number": 1,
                  "is_locked_content": false, "start_type": "swipe", "resume_position_s": 0, "ttff_ms": 342 }
    },
    {
      "event_id": "018f6c3e-9b11-7dd4-8c02-aa41f0b7e6d1",
      "name": "episode_unlock_prompt",
      "event_ts": 1783762360005,
      "session_id": "7b1f4e2a-0c3d-4a5b-9e8f-6d7c8b9a0e1f",
      "session_seq": 9,
      "params": { "series_id": "srs_9f2c1a", "episode_id": "ep_5410bf", "unlock_price": 60,
                  "coin_balance": 165, "options_shown": "coin,ad,vip", "source": "auto_advance" }
    }
  ]
}
// (ikinci event'te ortak zarfın kalan alanları kısaltıldı; gerçek istekte HER event tam zarfı taşır)

// 202 Accepted — gövde boş; sunucu asenkron işler
```

Zarf alanları (`event_id`, `event_ts` — Unix epoch **ms**, int —, `session_id`, `user_id`, `session_seq`, `schema_version`, `ab_variants`, cihaz/sürüm alanları) `08-analitik-deney.md` §2.2'deki ortak parametre setidir; event adları ve `params` anahtarları oradaki event kataloğundan (§3) gelir. **Bu adlardan, tiplerden veya birimlerden sapma şema ihlalidir** (DEBUG'da `assertionFailure`, `08-analitik-deney.md` §1).

Davranış kuralları:
- **Kimlik:** `Authorization: Bearer` zorunlu; misafir token'ı yeterlidir (anonim kullanıcı eventleri aynı misafir kullanıcı kimliği altında akar). `user_id` ortak parametre zarfında da taşınır (`08-analitik-deney.md` §2.2); sunucu, token'dan çözülen kimlikle eşleştiğini doğrular. Cihaz/sürüm bağlamı §1.1 header'larında da vardır ama raporlamada zarftaki değerler esastır.
- **Sıkıştırma:** `Content-Encoding: gzip` zorunludur (batch gövdeleri metin ağırlıklı).
- **Batch sınırı:** en fazla 100 event veya 256 KB (gzip öncesi). Aşımda `413 PAYLOAD_TOO_LARGE` → istemci batch'i ikiye bölüp tekrarlar.
- **Oran limiti:** cihaz başına dakikada en fazla 6 istek; aşımda `429 RATE_LIMITED` + `Retry-After` → kuyruk bekler, event **atılmaz**.
- **Hata yolu:** `400` şema hatasında batch'in tamamı reddedilir; aynı batch üst üste 3 kez `400` alırsa istemci batch'i düşürür ve lokal loglar (poison-pill koruması). `5xx`/ağ hatasında batch kuyruğa geri döner (dedupe sayesinde çift sayım oluşmaz).
- **Flush tetikleri:** kuyruk 100 event'e ulaşınca, 30 sn'de bir ve `applicationDidEnterBackground`da (`08-analitik-deney.md` ile hizalı).

---

## 5. İstemci networking iskeleti (AppFoundation)

Tip tanımları BURADA DEKLARE EDİLMEZ — **tek normatif tanım [03-mimari.md](03-mimari.md) §8.1'dedir**: istek sözleşmesi `Endpoint` protokolü (üyeler: `method`, `path`, `query`, `body`, `requiresAuth`, `retryPolicy`, `idempotencyKey`, `cachePolicy`), istemci arayüzü `APIClientProtocol`, somut implementasyon `APIClient` struct'ı. Bu dokümanda endpoint tablolarında görülen tüm uçlar birer `Endpoint` uygulamasıdır.

Bu bölüm yalnız API katmanının **çalışma zamanı davranışını** tanımlar. `APIClient` sorumlulukları (sırayla): ortak header'lar → 401'de tek-uçuş token refresh + orijinal isteğin bir kez tekrarı → `AppError` map'leme (§10) → 5xx/`URLError` için exponential backoff retry (uygunluk HTTP verb'inden DEĞİL isteğin `retryPolicy` beyanından okunur — §10.3; pratikte GET'ler ve Idempotency-Key'li POST'lar retry'a uygun beyan edilir; max 3 deneme, 0.5s/1s/2s + jitter) → `X-Request-Id` loglama. ViewModel'ler istemciyi `APIClientProtocol` olarak init-injection ile alır (mimari: `03-mimari.md` §5).

---

## 6. Kabul kriterleri (API katmanı)

1. Uçtan uca soğuk açılış: Splash'ta `POST /auth/guest` (gerekirse) + `GET /feed` + `GET /config` **paralel** koşar; ilk video için `POST /playback/authorize` feed yanıtı gelir gelmez atılır. Hedef: ilk frame < 500 ms'e katkıda API'nin payı ölçülür (`08-analitik-deney.md` `api_latency` eventi).
2. Kilitli bölüme swipe → UnlockSheet açılışı tek RTT (403 gövdesindeki `details` ile) — ikinci istek atılmaz.
3. Unlock çift dokunma / ağ kopması / uygulama öldürme senaryolarının hiçbirinde çift harcama oluşmaz (Idempotency-Key + sunucu tekilleştirme; entegrasyon testi zorunlu).
4. IAP: satın alma sırasında uygulama öldürülürse coin/VIP sonraki açılışta `Transaction.updates` üzerinden tazmin edilir; test planı `09-yol-haritasi-tasklar.md`.
5. Token refresh fırtınası yok: eşzamanlı 10 istek 401 aldığında yalnız 1 refresh çağrısı çıkar (unit test).
6. Bilinmeyen enum/alan içeren yanıtlar decode hatası üretmez (contract testte "geleceğe dönük yanıt" fixture'ı).
7. Unlock başarısı → ilk video karesi < 1 sn: unlock 200 yanıtındaki `playback` bloğu kullanılır, ek `POST /playback/authorize` round-trip'i atılmaz (§4.5).

---

## 7. Sayfalama ve cache

### 7.1 Cursor tabanlı sayfalama kalıbı

Tüm listeler aynı zarfı kullanır:

```json
{ "items": [ ... ], "nextCursor": "eyJ2IjoxLCJrIjoiLi4uIn0", "ttlSec": 300 }
```

Kurallar:
- `cursor` **opak** ve URL-safe base64'tür; istemci içeriğini yorumlamaz, saklayıp aynen geri gönderir.
- `nextCursor: null` → son sayfa. Boş `items` + null cursor geçerli bir "boş liste" yanıtıdır.
- Cursor'lar sayfalama oturumuna bağlıdır ve en az 15 dk geçerlidir; süresi dolmuş cursor `410 CURSOR_EXPIRED` döner → istemci listeyi baştan yükler (kullanıcıya sessiz).
- `limit` varsayılanı endpoint bazında sunucuda tanımlıdır (feed 10, listeler 20); istemci `limit` gönderebilir, sunucu 50 ile sınırlar.
- Offset tabanlı sayfalama hiçbir endpoint'te kullanılmaz (feed sıralaması kişisel ve değişken olduğundan cursor zorunlu).

### 7.2 Cache-Control beklentileri

| Kaynak | Sunucu başlığı | İstemci davranışı |
|---|---|---|
| `GET /series/{id}`, `/series/{id}/episodes` | `Cache-Control: private, max-age=300` + `ETag` | SwiftData snapshot + `If-None-Match`; `304` → `fetchedAt` tazele |
| `GET /discover`, `/collections/{id}` | `private, max-age=600` | stale-while-revalidate: önce cache bas, arkada tazele |
| `GET /wallet/packages` | `private, max-age=600` | stale-while-revalidate; CoinMagazasi açılışında tazele (§4.5) |
| `GET /feed` | `no-store` (yanıt gövdesindeki `ttlSec` esas) | Yalnız `FeedSnapshotEntity` (offline başlangıç); HTTP cache yok |
| `GET /wallet`, `/subscription`, `/rewards/*`, `/missions` | `no-store` | Asla disk cache'lenmez; bellekte tutulur |
| Görseller (cover/thumbnail, public CDN) | `public, max-age=86400, immutable` (URL versiyonlu) | `URLCache` + `04-player-engine.md` görsel pipeline'ı |
| `POST /playback/authorize` yanıtı | `no-store` | Bellekte, `expiresAt`e kadar (§8) |

`URLCache` limiti: 50 MB disk / 10 MB bellek (görseller hariç video segmentleri buradan geçmez — kanon: HLS cache `AVAssetDownloadTask` ile, bkz. `04-player-engine.md`).

---

## 8. İmzalı URL ve FairPlay DRM (Faz 2)

### 8.1 Faz 1 — imzalı URL

- `playbackURL` süreli imza taşır (`exp` + HMAC token, query'de). Tipik geçerlilik ~1 saattir ama istemci **süreyi varsaymaz**, `expiresAt` alanını okur.
- İmza master playlist, variant playlist'ler ve segment istekleri için CDN'de doğrulanır (edge auth). İmza kapsamı backend/CDN sorumluluğudur; istemci yalnız URL'i olduğu gibi `AVURLAsset`e verir.
- **Yenileme akışı (URL süresi dolunca):**
  1. Proaktif: `PlayerPool`, `expiresAt - 60 sn` eşiğini geçmiş bir yetkiyle oynatma/prefetch başlatmaz; önce `POST /playback/authorize` ile tazeler.
  2. Reaktif: Oynatma sırasında CDN `403` dönerse `AVPlayerItem` failed durumuna düşer → `PlayerKit` hata alanından `errorLog()` kontrol edilir → tek seferlik sessiz kurtarma: yeni authorize → yeni `AVPlayerItem` → `seek(to: lastPosition)` → oynatmaya devam. İkinci ardışık başarısızlıkta kullanıcıya hata durumu + "Tekrar dene" gösterilir.
  3. Background→foreground dönüşünde aktif item'ın `expiresAt`i geçmişse oynatma başlamadan tazeleme yapılır.
- Prefetch edilen bölümlerin yetkileri de `expiresAt` taşır; süresi dolan prefetch yetkisi çöpe atılır, segment cache'i (indirilen ~500 KB) korunur — segmentler URL'den bağımsız içerik olarak cache'lidir (`04-player-engine.md`).

### 8.2 Faz 2 — FairPlay

- `drm` alanı dolu geldiğinde (`flags.fairplayEnabled` + içerik bazlı) `PlayerKit`, `AVContentKeySession(keySystem: .fairPlayStreaming)` kurar; `licenseURL`e SPC gönderir, CKC alır. `licenseToken`, license isteğinin `Authorization` header'ında taşınır.
- Uygulama sertifikası `certificateURL`den çekilir ve 7 gün disk cache'lenir.
- Faz 2'de offline oynatma hedeflenmediği sürece persistable key istenmez; İndirilenler (Faz 3) geldiğinde `AVAssetDownloadTask` + persistent CKC bu bölüme eklenecek.
- Geçiş stratejisi: aynı `POST /playback/authorize` sözleşmesi hem clear hem DRM içerik için kullanılır; istemci `drm == null` ise bugünkü yolu izler. **Bu, Faz 2'nin API değişikliği gerektirmeden açılabilmesini sağlar.**

---

## 9. Idempotency sözleşmesi

- Anahtar formatı: UUID v4 (IAP'de `iap-<originalTransactionId>-<transactionId>` istisnası, §4.6).
- Üretim anı: kullanıcı niyetinin oluştuğu an (buton dokunuşu). Retry'lar aynı anahtarı taşır; **yeni niyet = yeni anahtar** (örn. CoinMagazasi'ndan dönüp unlock'u tekrar denemek yeni anahtardır çünkü bakiye bağlamı değişti).
- Sunucu saklama süresi: en az 24 saat. Aynı anahtar + aynı gövde → ilk yanıtın aynısı (200). Aynı anahtar + farklı gövde → `422 IDEMPOTENCY_PAYLOAD_MISMATCH`.
- İstemci, gönderilmemiş/yanıtsız kalmış para etkili istekleri kalıcı kuyrukta tutmaz — **yalnız IAP** StoreKit'in unfinished transaction mekanizmasıyla kalıcıdır. Unlock/claim gibi işlemler yanıtsız kalırsa UI "tekrar dene" durumuna düşer ve aynı anahtarla tekrarlar; uygulama ölürse işlem kullanıcı tekrar istediğinde yeni anahtarla yapılır (sunucu zaten işlediyse `alreadyUnlocked`/`ALREADY_CLAIMED` yolları durumu düzeltir).

---

## 10. Hata sözleşmesi

### 10.1 Hata gövdesi şeması

Tüm 4xx/5xx yanıtları aynı zarfı kullanır:

```json
{
  "error": {
    "code": "INSUFFICIENT_COINS",     // SCREAMING_SNAKE, makine-okur, sözleşmenin parçası
    "message": "Yetersiz coin.",       // lokalize, DOĞRUDAN gösterilebilir
    "details": { "shortfall": 25 },    // koda özgü ek alanlar (opsiyonel)
    "retryable": false                 // istemcinin otomatik retry ipucu
  },
  "requestId": "req_01HZY..."
}
```

```swift
public struct APIErrorBody: Decodable, Sendable {
    public struct Payload: Decodable, Sendable {
        public let code: String
        public let message: String
        public let details: JSONValue?   // hafif dinamik JSON sarmalayıcı (AppFoundation)
        public let retryable: Bool?
    }
    public let error: Payload
    public let requestId: String?
}
```

### 10.2 İstemci davranış tablosu

| HTTP | `error.code` | İstemci davranışı |
|---|---|---|
| 400 | `BAD_REQUEST` | Programlama hatası; log + genel hata UI. Retry yok |
| 400 | `CODE_INVALID` | E-posta doğrulama kodu hatalı (F2, §4.2.1); alan hatası + `details.attemptsLeft` |
| 401 | `TOKEN_EXPIRED` | `AuthSession` tek-uçuş refresh → orijinal isteği 1 kez tekrarla. Refresh de düşerse misafir yeniden-auth / giriş akışı (§4.2) |
| 401 | `TOKEN_INVALID` | Refresh deneme YOK; Keychain temizle → `POST /auth/guest` |
| 401 | `INVALID_CREDENTIALS` | E-posta+şifre girişi hatalı (F2, §4.2.1); form hatası, refresh/yeniden-auth tetiklenmez |
| 402 | `INSUFFICIENT_COINS` | UnlockSheet → CoinMagazasi akışı; `details.shortfall` ile "25 coin daha gerekli" metni |
| 403 | `EPISODE_LOCKED` | UnlockSheet aç (`details` fiyat + bakiye taşır, §4.4) |
| 403 | `FORBIDDEN` | Genel yetki hatası; sessiz log + içerik gizle |
| 404 | `NOT_FOUND` | İçerik kaldırılmış: DiziDetay/oynatma → "İçerik artık mevcut değil" + feed'den düşür; lokal cache kaydını sil |
| 409 | `PRICE_CHANGED` | UnlockSheet'i `details.currentPrice` ile güncelle; kullanıcı yeniden onaylar |
| 409 | `ALREADY_CLAIMED` / `MISSION_NOT_CLAIMABLE` | Yanıttaki güncel durumla UI'ı tazele; hata gösterme (idempotent tekrar semantiği) |
| 409 | `RECEIPT_ALREADY_PROCESSED` | Başarı say: `details.original`deki sonucu uygula, transaction'ı finish et |
| 409 | `ACCOUNT_ALREADY_LINKED` | Hesap birleştirme seçenek diyaloğu (§4.2) |
| 409 | `EMAIL_IN_USE` | E-posta başka hesaba bağlı (F2, §4.2.1); "bu e-postayla giriş yap" önerisi |
| 410 | `CURSOR_EXPIRED` | Listeyi baştan yükle (sessiz) |
| 410 | `SIGNED_URL_EXPIRED` | `POST /playback/authorize` ile tazele (§8.1) — CDN 403'ü de aynı yola düşer |
| 410 | `CODE_EXPIRED` | Doğrulama kodu / `passwordToken` süresi doldu (F2, §4.2.1); "yeni kod gönder" durumu |
| 413 | `PAYLOAD_TOO_LARGE` | Event batch'ini ikiye böl ve tekrarla (§4.11); diğer uçlarda programlama hatası (log) |
| 422 | `RECEIPT_INVALID` | Transaction finish etme; hata UI + destek yönlendirmesi |
| 422 | `IDEMPOTENCY_PAYLOAD_MISMATCH` | Programlama hatası; log/alert, kullanıcıya genel hata |
| 422 | `WEAK_PASSWORD` | Şifre politikası hatası (F2, §4.2.1); `details.policy` metni alan hatası olarak gösterilir |
| 426 | `UPGRADE_REQUIRED` | Zorunlu güncelleme tam-ekranı (App Store'a yönlendir); uygulama kilitlenir |
| 429 | `RATE_LIMITED` / `AD_UNLOCK_CAP_REACHED` | `Retry-After` header'ına uy; ad-cap'te `details.resetsAt` ile UnlockSheet seçeneğini devre dışı göster |
| 5xx | `INTERNAL` vb. | İsteğin `retryPolicy` beyanı uygunsa backoff'lu 3 deneme (§5, §10.3); diğerleri: hata UI. `retryable:false` ise retry atlanır |
| — | (ağ yok, `URLError`) | Offline moda düş (§11); kuyruklanabilir yazımlar (progress, favori) `syncState` ile bekler |

Kural: istemci **önce `error.code`a, sonra HTTP koduna** bakar; tanımadığı kod için HTTP sınıfının varsayılan davranışını uygular.

### 10.3 Sınır kuralı — hata eşlemesi yalnız AppFoundation'da

- HTTP statü + `error.code` → tipli hata (`AppError`) eşlemesi **yalnız `AppFoundation`'daki API katmanında** yapılır. Feature modülleri (`ContentKit`, `WalletKit`, `PlayerKit`…) ham HTTP kodunu veya ham hata gövdesini GÖRMEZ; §10.2 tablosundaki davranışları tipli hata üzerinden uygular.
- Otomatik retry uygunluğu HTTP verb'inden türetilmez; isteğin `retryPolicy` beyanından okunur (§5). "GET olduğu için retry edilir / POST olduğu için edilmez" biçiminde örtük davranış YOKTUR.
- §10.2 tablosu bu eşlemenin normatif tanımıdır: yeni bir `error.code` eklemek = aynı PR'da bu tabloya satır + `AppFoundation` eşlemesine vaka eklemek.

---

## 11. Offline davranış matrisi

Ağ yokken (veya art arda başarısız isteklerde) her ekran ne gösterir:

| Ekran | Cache'ten gösterilen | Gösterilemeyen / davranış |
|---|---|---|
| PlayerFeed (Ana Sayfa) | `FeedSnapshotEntity` son sayfası; disk cache'inde segmenti olan bölümler oynar (~200 MB LRU) | Cache'siz bölümde oynatma duraklar → "Bağlantı yok" bandı + otomatik yeniden deneme (reachability değişince) |
| DiziDetay | `CachedSeriesEntity` snapshot'ı + yerel favori durumu | `stats` bayat olabilir (etiketlenmez); "İzlemeye Başla" cache'siz içerikte bağlantı uyarısı verir |
| BolumListesi | `CachedEpisodeListEntity` — kilit ikonları **son bilinen** duruma göre | `access` bayat uyarısı yok; oynatma denemesi authorize gerektirdiğinden gerçek durum orada çözülür |
| UnlockSheet / CoinMagazasi / VIPAbonelik | Açılmaz (para işlemi offline yapılmaz) | "Bağlantı gerekli" durumu; StoreKit offline zaten satın alma başlatamaz |
| OdulMerkezi | Son bilinen `CheckInState`/`Mission` bellek kopyası (varsa) + bakiyenin salt-okunur son değeri | Claim butonları devre dışı; "çevrimdışı" rozeti |
| Kesfet | `discover` stale-while-revalidate kopyası; süresi geçmiş `Banner` gizlenir | Raf "tümünü gör" sayfalaması çalışmaz |
| Arama | `search/popular` son kopyası | Suggest/sonuç istekleri hata durumuna düşer; boş durum + "bağlantı yok" |
| Listem → Favoriler | `FavoriteEntity` tam liste (yerel otorite kopyası) | Toggle çalışır (`pendingAdd/Remove` kuyruklanır) |
| Listem → Devam Et | `WatchProgressEntity` tam liste | Diğer cihazların ilerlemesi görünmez (sync bekler) |
| Profil / Ayarlar | Son `UserProfile` kopyası; yerel tercihler | Hesap bağlama, `PATCH /me` kuyruklanmaz — bağlantı ister |
| Splash | Cache'li config + feed ile normal açılır | İlk kurulum + offline (hiç token yok): tam ekran "bağlantı gerekli" |

Bağlantı geri geldiğinde sıra: token tazele → `pendingUpload` progress flush → favori kuyruğu → wallet/subscription tazele → feed tazele (görünür kuyruğu bozmadan, §4.3).

---

## 12. API versiyonlama ve geriye uyumluluk

1. **Yol tabanlı major versiyon:** `/v1`. Kırıcı değişiklik ancak `/v2` ile gelir; `/v1` en az 12 ay yaşatılır (App Store'daki eski istemciler için).
2. **Kırıcı olmayan değişiklikler** her zaman serbesttir ve istemci bunlara dayanıklı olmak ZORUNDADIR: yeni alan ekleme, yeni enum değeri, yeni endpoint, yeni `FeedItem.type`, opsiyonel yeni header.
3. **Kırıcı sayılanlar:** alan silme/yeniden adlandırma, tip değişimi, non-null → null, anlam değişikliği, hata kodu semantiği değişimi.
4. **Zorunlu decoding kalıbı** — bilinmeyen enum değeri asla decode hatası üretmez:

```swift
public protocol UnknownDecodable: RawRepresentable, CaseIterable where RawValue == String {
    static var unknown: Self { get }
}
public extension UnknownDecodable where Self: Decodable {
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}
```

   `.unknown` değerine düşen kayıtlar için varsayılan davranışlar: `FeedItem.type == .unknown` → item atlanır; `EpisodeAccess.kind == .unknown` → kilitli varsayılır (güvenli taraf) ve authorize gerçek durumu çözer; `TxnType.unknown` → nötr ikonla listelenir.
5. **Sunucu tarafı istemci kapısı:** `X-Client-Version` + `GET /config.minSupportedVersion` + `426 UPGRADE_REQUIRED` üçlüsü, çok eski istemcileri kontrollü emekliye ayırır.
6. **Sözleşme testi:** Her iki repo da paylaşılan JSON fixture setine karşı contract test koşar (istemci: decode + davranış; backend: encode). Fixture'lara alan eklemek serbest, silmek PR'da API review etiketi gerektirir. Süreç `09-yol-haritasi-tasklar.md`de görevlendirilmiştir. **Adlandırma doğrulaması (§1 kural 7):** contract test fixture'ları **wire adlarını** kullanır (decode sınırını sınar); ViewModel/feature testleri yalnız **domain adlarını** kullanır — bir wire adı değişikliği yalnız `CodingKeys`/mapper + fixture'ları değiştirir, ViewModel testlerine dokunmaz.
7. **Deprecation:** Kaldırılacak alan önce yanıtta `Deprecation` başlığı + changelog ile işaretlenir, en az 2 minor sürüm yaşar.

---

## 13. Açık konular

| Konu | Durum | Sahip |
|---|---|---|
| Rewarded ad kanıt doğrulama detayı (`/rewards/ad-unlock` — zarf §4.7'de sağlayıcı-bağımsız; aktif sağlayıcı AdMob → SSV) | Faz 2 tasarımında netleşecek | `06-monetizasyon.md` |
| İndirilenler (Faz 3) için persistent FairPlay key + download API | Faz 3 | `04-player-engine.md` + bu doküman güncellenecek |
| BildirimMerkezi (Faz 2) uygulama içi bildirim listesi endpoint'i | Taslak: `GET /notifications?cursor=` aynı cursor kalıbıyla | Bu doküman, Faz 2 revizyonu |
| Earned coin son kullanma kohort kuralları (süre, bildirim zamanlaması) | Ekonomi ayarı | `06-monetizasyon.md` / `07-retention-gamification.md` |
| Öneri sistemine istemci sinyalleri (skip, rewatch) — progress'e ek event mi? | `08-analitik-deney.md` event şemasıyla çözülür; ayrı endpoint açılmaz (karar) | `08-analitik-deney.md` |
