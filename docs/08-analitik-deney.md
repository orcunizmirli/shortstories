# Analitik, Event Şeması ve A/B Deney Altyapısı

**Amaç:** Bu doküman, ShortSeries iOS istemcisinin analitik mimarisini, kanonik event şemasını, player performans metriklerini, funnel ve KPI tanımlarını, A/B deney altyapısını ve gizlilik/uyumluluk gereksinimlerini uygulanabilir düzeyde spesifiye eder. `AnalyticsKit` modülünün geliştirme sözleşmesidir: burada tanımlanan event adları, parametreler ve tetiklenme anları bağlayıcıdır; yeni event eklemek veya mevcut bir eventi değiştirmek bu dokümanın ve şema registry'sinin güncellenmesini gerektirir.

**İlgili dokümanlar:** `00-genel-bakis.md` (kuzey yıldızı ve hedefler), `03-mimari.md` (`AnalyticsKit` modül sınırları ve DI), `04-player-engine.md` (performans bütçeleri ve ölçüm noktaları), `05-veri-modeli-api.md` (event ingest endpoint'i ve backend sözleşmesi), `06-monetizasyon.md` (ödeme funnel'ının UX karşılığı), `07-retention-gamification.md` (check-in/görev mekanikleri), `09-yol-haritasi-tasklar.md` (fazlara dağılım), `10-arastirma-raporu.md` (benchmark kaynakları).

---

## 1. Analitik hedefleri ve araç seti

### 1.1 Neyi ölçüyoruz, neden

Analitik yatırımı kuzey yıldızı önceliklerini birebir takip eder:

1. **Akıcı, kesintisiz izleme deneyimi** → player performans telemetrisi (TTFF, stall, swipe gecikmesi) ve crash/hang oranları.
2. **Retention** → D1/D7/D30 kohortları, check-in/görev katılımı, push etkinliği, binge derinliği (oturum başına bölüm sayısı).
3. **Discovery** → feed impression → izleme dönüşümü, Kesfet/Arama etkinliği, öneri kabul oranı.

Bunlara ek olarak iş modeli ölçümü (ödeme dönüşümü, ARPDAU, coin ekonomisi sağlığı) ve deney altyapısı (A/B) bu dokümanın kapsamındadır.

### 1.2 Araç seti

Kanon kararı: **kendi event şemamız + üçüncü parti (Firebase Analytics + Crashlytics)**, A/B için **remote-config/feature-flag** altyapısı. Buna işletim sistemi seviyesinde **MetricKit** eklenir.

| Araç | Rol | Veri kapsamı | Not |
|---|---|---|---|
| **Kendi event pipeline'ı** (birincil) | Ürün analitiği, funnel, deney analizi, coin ekonomisi | Bu dokümandaki TAM katalog; ham event, sınırsız parametre | Backend ingest endpoint'i `05-veri-modeli-api.md`'de. Tek doğruluk kaynağı budur. |
| **Firebase Analytics** (ikincil sink, Faz 1) | Hızlı dashboard, gerçek zamanlı sağlık kontrolü, Firebase A/B entegrasyonu opsiyonu | Kataloğun bir alt kümesi (aşağıda "2°" kolonu; sözleşmede `secondary_sinks` kümesi — bkz. §1.3); Firebase'in 25 parametre/40 karakter limitlerine uyar | Kendi pipeline'ımızla **event adları birebir aynı** tutulur; çift bakım maliyeti yok. |
| **Crashlytics** | Crash-free oranı, non-fatal hatalar, breadcrumb | Crash raporları + custom key olarak `session_id`, aktif `series_id/episode_id`, `ab_variants` | Crash-free hedefi kanon: **≥ %99.8**. |
| **MetricKit** | OS seviyesinde launch time, hang rate, disk/CPU/batarya, `MXSignpostMetric` | Günlük `MXMetricPayload` + `MXDiagnosticPayload`; kendi pipeline'a JSON olarak yüklenir | Player performans bütçelerinin saha doğrulaması (`04-player-engine.md`). |

**Bilinçli karar — çift yazım (dual-write):** Her event önce `AnalyticsKit` içindeki tek bir `track()` API'sine gelir; oradan kayıtlı sink'lere dağıtılır (birincil sink — kendi pipeline — her zaman ve koşulsuz; ikincil sink'ler yalnızca event'in `secondarySinks` kümesinde işaretliyse). Ürün kodu hiçbir zaman vendor SDK'sını doğrudan çağırmaz — Firebase, `AnalyticsSink` implementasyonu olarak kompozisyonda kaydedilen bir implementasyon detayıdır ve `AnalyticsKit` sözleşmesinin arkasında kalır (sink mimarisi: §1.3).

### 1.3 İstemci mimarisi: `AnalyticsKit`

`03-mimari.md`'deki modül sınırlarına uygun olarak `AnalyticsKit` şu bileşenlerden oluşur (Combine kullanılmaz; structured concurrency):

```swift
// AnalyticsKit — genel API yüzeyi

public protocol AnalyticsEvent: Sendable {
    /// snake_case, alan_eylem kalıbı (bkz. §2.1)
    var name: String { get }
    var parameters: [String: AnalyticsValue] { get }
    /// Event'in ait olduğu şema versiyonu (bkz. §2.3)
    static var schemaVersion: Int { get }
    /// Event'in ek olarak gönderileceği ikincil sink'ler (vendor-nötr kimlikler; bkz. "Sink mimarisi").
    /// Boş küme = yalnız birincil pipeline. Birincil pipeline bu kümeden BAĞIMSIZ olarak her event'i alır.
    static var secondarySinks: Set<AnalyticsSinkID> { get }
}

// AnalyticsValue BURADA tanımlanmaz — evi AppFoundation'dır (03-mimari.md §5.1):
// public enum AnalyticsValue: Sendable, Equatable { case string(String), int(Int), double(Double), bool(Bool) }
// AnalyticsKit yalnız kullanır; ek conformance (ör. Codable) gerekiyorsa AppFoundation'daki tanıma eklenir.

/// İkincil sink kimliği — vendor-nötr, opak tanımlayıcı. Vendor adı yalnız kompozisyon kökünde
/// somut sink implementasyonuna eşlenirken görünür; event tanımları vendor adı bilmez.
public struct AnalyticsSinkID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// Tek giriş noktası. Actor: buffer + flush yarış koşullarına kapalı.
public actor AnalyticsClient {
    public func track(_ event: some AnalyticsEvent) async
    public func setUser(id: String, isVIP: Bool)
    public func setABVariants(_ variants: [String: String]) // "exp_key": "variant"
    public func flush(reason: FlushReason) async            // .timer, .count, .background, .critical
    public func deleteUserData() async throws               // GDPR/CCPA silme; kayıtlı tüm sink'lere yayılır (bkz. §9.3)
}
```

**Davranış sözleşmesi (kabul kriterleri):**

- **Zenginleştirme:** `track()` çağrısında istemci her event'e ortak parametreleri (bkz. §2.2) otomatik ekler. Çağıran modül ortak parametre GÖNDERMEZ.
- **Buffering & flush:** Event'ler bellekte kuyruklanır ve disk'e (SwiftData değil — `AppFoundation` içinde append-only JSONL dosyası) yazılır. Flush tetikleyicileri: 30 sn timer, 50 event birikmesi, `scenePhase == .background`, veya `critical` işaretli event (satın alma sonuçları anında flush edilir).
- **Teslimat garantisi:** At-least-once. Her event istemcide üretilen `event_id` (UUIDv7 — zaman sıralı) taşır; backend `event_id` ile dedupe eder. Upload başarısızsa exponential backoff (1s → 2s → 4s… max 5 dk), kuyruk diskte kalıcıdır; uygulama öldürülse bile kaybolmaz.
- **Kuyruk sınırı:** Disk kuyruğu max 10 MB veya 20.000 event; aşılırsa en eski event'ler düşürülür ve `analytics_queue_overflow` sayacı bir sonraki başarılı yüklemede raporlanır.
- **Sıralama:** Backend `event_ts` + `event_id` (UUIDv7 monotonik) ile sıralar; istemci sıra garantisi vermez.
- **Ana thread kuralı:** `track()` çağrısı ana thread'i bloklamaz; PlayerFeed kaydırma sırasında event üretimi 60 fps bütçesini etkileyemez (imza `async`, iç işlem actor'de).
- **Debug doğrulama:** DEBUG build'de her event, repo'daki şema registry'sine (bkz. §2.3) karşı çalışma zamanında doğrulanır; bilinmeyen event adı veya parametre tipi `assertionFailure` üretir. RELEASE'te sessizce loglanır ve gönderilir (veri kaybetmemek şema polisliğinden önce gelir).

**Sink mimarisi ve genişleme (vendor değişim sözleşmesi):**

```swift
/// Her analitik hedef (kendi pipeline, üçüncü parti vendor köprüleri) bu protokolü uygular.
/// AnalyticsClient event'leri kayıtlı sink'lere dağıtır; sink'ler kompozisyon kökünde
/// (ShortSeriesApp DI, bkz. 03-mimari.md) kaydedilir.
public protocol AnalyticsSink: Sendable {
    var id: AnalyticsSinkID { get }
    func send(_ event: EnrichedEvent) async      // ortak parametreleri (§2.2) eklenmiş event
    func setUser(id: String, isVIP: Bool) async
    func deleteUserData() async throws           // vendor'a özgü silme API'leri BURADA yaşar (bkz. §9.3)
}
```

- **Birincil sink değişmezdir:** Kendi event pipeline'ımız birincil sink'tir; her event koşulsuz ona gider ve `secondarySinks` kümesinden etkilenmez. Birincil sink'i devre dışı bırakan bir konfigürasyon yoktur (consent istisnası: §9.3).
- **İkincil sink'ler kompozisyonda kaydedilir:** Sink kimlikleri ROL adlandırır, vendor adlandırmaz. Faz 1'de tek ikincil sink vardır: `AnalyticsSinkID(rawValue: "dashboard")` (hızlı dashboard / gerçek zamanlı sağlık rolü) → bugünkü implementasyonu Firebase Analytics köprüsüdür. `AnalyticsKit` vendor SDK'sını bilmez; köprü, vendor SDK'sını saran ayrı bir sink implementasyonudur ve yalnız `ShortSeriesApp` DI kompozisyonunda bu kimliğe eşlenir.
- **Vendor değişimi = yeni sink + kompozisyonda kayıt:** Ürün kodu, event tanımları ve `events.yaml` DEĞİŞMEZ; yeni bir `AnalyticsSink` implementasyonu yazılır ve kompozisyonda aynı kimliğe kaydedilir. Geçiş döneminde eski ve yeni sink birlikte kayıtlı kalır (dual-write); veri sürekliliği doğrulandıktan sonra N sürüm (öneri: 2) sonunda eski sink kompozisyondan sökülür.

---

## 2. Event şeması standartları

### 2.1 Adlandırma

- **Biçim:** `snake_case`, ASCII, max 40 karakter — kanonik şema kısıtı (bilgi notu: en dar ikincil sink limiti baz alınmıştır).
- **Kalıp:** `alan_eylem` — önce alan/nesne, sonra eylem. Doğru: `coin_purchase_success`, `search_query`. Yanlış: `purchaseCoinSuccess`, `didSearch`.
- **Süreç event'leri** üçlemesi: `*_start` / `*_success` / `*_fail` (+ gerekiyorsa `*_cancel`). Tek anlık olaylar tek isimdir (`feed_impression`).
- **Parametre adları** da `snake_case`; birim, adın sonuna eklenir: `ttff_ms`, `stall_duration_ms`, `watch_time_s`.
- **Enum değerleri** string ve `snake_case`: `source: "player_feed" | "dizi_detay" | "bolum_listesi" | "kesfet" | "arama" | "listem" | "push" | "deeplink"`.
- Yeni event adı üretmek şu onayı gerektirir: `AnalyticsKit` sahibi + ilgili modül sahibi + bu dokümana ve registry'ye PR.

### 2.2 Ortak parametreler (her event'e otomatik eklenir)

| Parametre | Tip | Tanım |
|---|---|---|
| `event_id` | string | UUIDv7, istemcide üretilir; dedupe anahtarı |
| `event_ts` | int | Unix epoch **ms**, UTC; cihaz saati (backend `received_ts` ile çarpıklık düzeltir) |
| `session_id` | string | UUID; oturum tanımı: ilk `app_open`'da üretilir, **30 dk** arka planda kalma sonrası yenilenir |
| `user_id` | string | Backend'in verdiği kalıcı kullanıcı ID'si. İlk açılışta anonim misafir hesabına aittir; Apple/Google/e-posta bağlanınca **aynı `user_id` korunur** (kimlik birleştirme backend'de) |
| `ab_variants` | string | Aktif deney atamaları, `"exp_free_eps:v8,exp_unlock_sheet:control"` biçiminde tek string — kanonik şema kısıtı olarak düzleştirilmiş (bilgi notu: en dar ikincil sink limiti) |
| `schema_version` | int | Event'in şema versiyonu (bkz. §2.3) |
| `app_version` / `build_number` | string / int | Semver + build |
| `os_version` | string | ör. `"17.5.1"` |
| `device_model` | string | ör. `"iPhone15,3"` |
| `locale` | string | uygulama dili, ör. `"en-US"` |
| `network_type` | string | `"wifi" \| "cellular" \| "offline"` |
| `is_vip` | bool | Aktif VIP entitlement var mı |
| `session_seq` | int | Oturum içi event sıra numarası (funnel sıralama güvencesi) |

**PII kuralı:** Ortak veya event parametrelerinde e-posta, ad, IDFA, telefon, tam IP **asla** yer almaz. `user_id` backend'in ürettiği opak bir ID'dir. Serbest metin parametresi yalnızca `search_query`'de vardır ve backend'de PII taraması + 90 gün saklama sınırına tabidir.

### 2.3 Şema versiyonlama

- Şema registry'si repo'da yaşar: `AnalyticsKit/Schema/events.yaml`. Her event için: ad, sahip modül, parametre listesi (ad, tip, zorunlu/opsiyonel, enum değerleri), `schema_version`, `secondary_sinks` (event'in gönderileceği ikincil sink kimlikleri; vendor-nötr — bkz. §1.3), açıklama. `secondary_sinks` kolon adı codegen kurulmadan ÖNCE bu haliyle sabitlenir; vendor adlı bir kolon sonradan yeniden adlandırılırsa üretilen tüm çağrı noktalarına yayılacağından registry'de vendor adı geçemez.
- **Versiyon artırma kuralları:** parametre EKLEMEK (opsiyonel) → versiyon artmaz. Parametre tipini/anlamını değiştirmek, zorunlu parametre eklemek, parametre silmek → `schema_version` +1 ve backend'e migration notu.
- **Event silme:** Event asla yeniden adlandırılmaz. Eski event `deprecated: true` işaretlenir, en az 2 sürüm boyunca çift yazılır (eski + yeni), sonra eski kaldırılır.
- **CI kontrolü:** `events.yaml` ↔ Swift event tipleri arasında codegen (Swift kaynak üretimi) kullanılır; el yazımı event tanımına lint hatası. Registry'de olmayan event derlenemez.

---

## 3. Event kataloğu (TAM)

Kolonlar: event adı, kendine özgü parametreleri (ortak parametreler §2.2 hariç), tetiklenme anı, sahibi modül. "2°" = event'in `secondary_sinks` kümesi boş değildir, yani ikincil sink'lere de gönderilir (bkz. §1.3). Faz 1 kompozisyonunda tek ikincil sink Firebase Analytics olduğundan bu işaret pratikte "Firebase'e de gider" anlamına gelir; sözleşme düzeyinde vendor-nötrdür.

### 3.1 Yaşam döngüsü ve Onboarding

| Event | Parametreler | Tetiklenme anı | Sahip | 2° |
|---|---|---|---|---|
| `app_open` | `launch_type: "cold"\|"warm"`, `entry_point: "icon"\|"push"\|"deeplink"`, `cold_start_ms` (yalnız cold) | `Splash` görünür olduğunda; warm için `scenePhase .active` (oturum yenilenmişse) | `ShortSeriesApp` | ✔ |
| `deeplink_opened` | `route_type` (§8.3 rota tipi: `home\|series\|episode\|play\|discover\|search\|rewards\|coin_store\|vip\|my_list\|profile\|settings\|notifications`), `source: "push"\|"universal"\|"qr"\|"internal"`, `campaign_id?` | Deep link / universal link başarıyla çözülüp hedef sekme + rota kompozisyonuna yönlendirildiğinde (02 §8.4 kural 5) | `ShortSeriesApp` | ✔ |
| `onboarding_start` | — | `Onboarding` ilk adımı görünür | `ShortSeriesApp` | ✔ |
| `onboarding_step_view` | `step: "language"\|"genre"\|"permissions"`, `step_index` | Her adım görünür olduğunda | `ShortSeriesApp` | ✔ |
| `onboarding_language_select` | `language` | Dil seçimi onaylandığında | `ShortSeriesApp` | |
| `onboarding_genre_select` | `genres` (virgüllü string), `genre_count` | Tür tercihi kaydedildiğinde (atlanırsa gönderilmez) | `ShortSeriesApp` | |
| `onboarding_push_prompt` | `action: "grant"\|"deny"` | Sistem bildirim izni diyaloğu kapandığında | `ShortSeriesApp` | ✔ |
| `onboarding_att_prompt` | `action: "authorized"\|"denied"\|"restricted"\|"not_determined"` | ATT diyaloğu kapandığında (bkz. §9.1) | `ShortSeriesApp` | ✔ |
| `onboarding_skip` | `skipped_at_step` | Kullanıcı akışı atladığında | `ShortSeriesApp` | ✔ |
| `onboarding_complete` | `duration_s` | Son adım tamamlandığında | `ShortSeriesApp` | ✔ |

### 3.2 Feed ve oynatma (PlayerFeed / `PlayerKit`)

| Event | Parametreler | Tetiklenme anı | Sahip | 2° |
|---|---|---|---|---|
| `feed_impression` | `series_id`, `episode_id`, `feed_position`, `source` | Hücre ekranın **≥ %50**'sini **≥ 500 ms** kapladığında; hücre başına oturumda 1 kez | `PlayerKit` | |
| `video_start` | `series_id`, `episode_id`, `episode_number`, `is_locked_content: bool` (VIP/unlock ile açılmış mı), `start_type: "auto_advance"\|"swipe"\|"tap"\|"resume"`, `resume_position_s`, `ttff_ms` | Normatif: ilk video frame'i ekranda görünür şekilde render edildiğinde (player-teknolojisi-bağımsız). *Faz 1 AVFoundation implementasyon notu:* `AVPlayerItem` ilk `.readyToPlay` + görüntü katmanı dolu; ölçüm `PlayerMetricsCollector` arkasında (bkz. §4) | `PlayerKit` | ✔ |
| `video_progress` | `series_id`, `episode_id`, `checkpoint: 25\|50\|75\|100`, `watch_time_s` (gerçek izleme, seek hariç) | Oynatma konumu bölüm süresinin %25/50/75/100'ünü İLK geçtiğinde; checkpoint başına bölüm-oturum çifti için 1 kez; seek ile atlanan checkpoint gönderilmez | `PlayerKit` | ✔ (yalnız 100) |
| `video_stall` | `series_id`, `episode_id`, `stall_duration_ms`, `position_s`, `network_type` | Buffer beklemesi **≥ 250 ms** sürüp oynatma durduğunda; stall bittiğinde gönderilir | `PlayerKit` | |
| `swipe_next` | `from_episode_id`, `to_episode_id`, `swipe_latency_ms`, `watch_pct_at_swipe` | Kullanıcı sonraki içeriğe kaydırıp geçiş tamamlandığında | `PlayerKit` | |
| `swipe_prev` | `from_episode_id`, `to_episode_id`, `swipe_latency_ms` | Önceki içeriğe kaydırma tamamlandığında | `PlayerKit` | |

**Edge case'ler:**
- `video_progress` checkpoint'leri **gerçek izleme süresine değil oynatma konumuna** bağlıdır; `watch_time_s` ayrıca gerçek izlemeyi taşır (seek/tekrar izleme analizi için ikisi birlikte gerekir).
- Bölüm bittiğinde otomatik geçiş `swipe_next` DEĞİLDİR; yeni bölümün `video_start.start_type = "auto_advance"` olması yeterlidir.
- Uygulama arka plana giderken aktif bölüm için son `watch_time_s` değeri `video_heartbeat` yerine `video_progress` mantığıyla değil, `Listem`/devam-et senkronu üzerinden korunur (`05-veri-modeli-api.md`). Ayrı bir heartbeat event'i **bilinçli olarak yoktur** — hacim maliyeti checkpoint modeliyle çözülür.

### 3.3 İçerik keşfi (`ContentKit`, `DiscoverKit`, `LibraryKit`)

| Event | Parametreler | Tetiklenme anı | Sahip | 2° |
|---|---|---|---|---|
| `series_detail_view` | `series_id`, `source`, `free_episode_count`, `total_episode_count` | `DiziDetay` görünür olduğunda | `ContentKit` | ✔ |
| `search_open` | `source` | `Arama` ekranı açıldığında | `DiscoverKit` | |
| `search_query` | `query` (≤100 karakter), `result_count`, `is_autocomplete: bool` | Sonuçlar render edildiğinde (300 ms debounce sonrası) | `DiscoverKit` | |
| `search_result_tap` | `query`, `series_id`, `result_position` | Sonuca dokunulduğunda | `DiscoverKit` | |
| `search_no_result` | `query` | Sonuç sayısı 0 render edildiğinde | `DiscoverKit` | |
| `favorite_add` | `series_id`, `source` | Favorilere ekleme başarıyla senkronlandığında (optimistic UI olsa da event sunucu onayında) | `LibraryKit` | ✔ |
| `favorite_remove` | `series_id`, `source` | Favoriden çıkarma onaylandığında | `LibraryKit` | |
| `share_tap` | `series_id`, `episode_id?`, `source` | Paylaş butonuna dokunulduğunda | `ContentKit` | |
| `share_complete` | `series_id`, `episode_id?`, `channel` (`UIActivity` tipi, alınabiliyorsa; yoksa `"unknown"`) | `UIActivityViewController` completion `completed == true` döndüğünde | `ContentKit` | ✔ |

### 3.4 Monetizasyon (`WalletKit`) — kritik yol, tüm sonuç event'leri `critical` flush

| Event | Parametreler | Tetiklenme anı | Sahip | 2° |
|---|---|---|---|---|
| `episode_unlock_prompt` | `series_id`, `episode_id`, `unlock_price` (coin), `coin_balance`, `options_shown: "coin,ad,vip"` alt kümesi, `source: "auto_advance"\|"bolum_listesi"\|"dizi_detay"` | `UnlockSheet` görünür olduğunda | `WalletKit` | ✔ |
| `unlock_coin` | `series_id`, `episode_id`, `unlock_price`, `earned_spent`, `purchased_spent`, `balance_after` | Cüzdan düşümü backend'de onaylandığında (idempotent işlem tamam) | `WalletKit` | ✔ |
| `unlock_ad` | `series_id`, `episode_id`, `ad_unlocks_used_today`, `daily_cap` | Rewarded ad %100 tamamlanıp kilit açıldığında (Faz 2) | `WalletKit` | ✔ |
| `unlock_vip_upsell` | `series_id`, `episode_id` | `UnlockSheet` içinden "VIP ol" seçeneğine dokunulduğunda (`VIPAbonelik`e yönlenme) | `WalletKit` | ✔ |
| `coin_store_view` | `source: "unlock_sheet"\|"profil"\|"odul_merkezi"\|"deeplink"`, `coin_balance` | `CoinMagazasi` görünür olduğunda | `WalletKit` | ✔ |
| `coin_purchase_start` | `product_id`, `price_usd`, `coin_amount`, `bonus_coin_amount`, `is_first_purchase_offer: bool` | Pakete dokunulup StoreKit 2 `purchase()` çağrılmadan hemen önce | `WalletKit` | ✔ |
| `coin_purchase_success` | `product_id`, `price_usd`, `coin_amount`, `bonus_coin_amount`, `transaction_id`, `balance_after` | Server-side receipt doğrulaması geçip coin cüzdana yazıldığında (StoreKit başarısı DEĞİL) | `WalletKit` | ✔ |
| `coin_purchase_fail` | `product_id`, `error_domain`, `error_code`, `stage: "storekit"\|"verification"\|"wallet"` | Herhangi bir aşamada hata | `WalletKit` | ✔ |
| `coin_purchase_cancel` | `product_id` | StoreKit `userCancelled` | `WalletKit` | |
| `iap_family_shared_rejected` | `product_id` | `Transaction.updates` akışında Family Sharing KAPALIyken gelen family-shared transaction reddedilip `finish()` edildiğinde | `WalletKit` | |
| `subscription_view` | `source: "unlock_sheet"\|"profil"\|"onboarding"\|"deeplink"` | `VIPAbonelik` görünür olduğunda | `WalletKit` | ✔ |
| `subscription_start` | `product_id` (`vip_weekly`/`vip_monthly`/`vip_yearly`), `price_usd`, `has_intro_offer: bool` | `purchase()` çağrılmadan hemen önce | `WalletKit` | ✔ |
| `subscription_success` | `product_id`, `price_usd`, `is_intro: bool`, `transaction_id` | Doğrulanmış abonelik entitlement'ı aktifleştiğinde | `WalletKit` | ✔ |
| `subscription_fail` | `product_id`, `error_domain`, `error_code`, `stage` | Hata durumunda | `WalletKit` | ✔ |
| `subscription_cancel_intent` | `product_id` | Kullanıcı `Ayarlar` → hesap yönetiminden "aboneliği yönet"e gittiğinde | `ProfileKit` | |

**Not:** Yenileme (renewal), iade (refund), grace period ve churn event'leri **istemciden gönderilmez**; App Store Server Notifications V2 ile backend'de üretilir (`06-monetizasyon.md`, `05-veri-modeli-api.md`). İstemci ve sunucu event'leri aynı `user_id` üzerinde birleşir.

### 3.5 Retention ve gamification (`RewardsKit`)

| Event | Parametreler | Tetiklenme anı | Sahip | 2° |
|---|---|---|---|---|
| `checkin_view` | `current_streak_day`, `can_claim_today: bool` | `OdulMerkezi` içindeki check-in takvimi görünür olduğunda | `RewardsKit` | |
| `checkin_claim` | `streak_day: 1..7`, `coin_reward`, `is_streak_bonus: bool` | Günlük ödül talebi backend'de onaylandığında | `RewardsKit` | ✔ |
| `checkin_streak_break` | `broken_at_day`, `previous_streak_length` | Backend streak sıfırlamasını istemci ilk gördüğünde (günde 1 kez) | `RewardsKit` | |
| `mission_view` | `mission_ids` (virgüllü), `mission_count` | Görev listesi görünür olduğunda | `RewardsKit` | |
| `mission_progress` | `mission_id`, `progress_pct` | Görev ilerlemesi %50'yi İLK geçtiğinde (hacim kontrolü: yalnız 50 checkpoint'i) | `RewardsKit` | |
| `mission_complete` | `mission_id`, `mission_type: "watch_time"\|"favorite"\|"share"\|"push_optin"` | Görev tamamlandı durumuna geçtiğinde | `RewardsKit` | ✔ |
| `mission_claim` | `mission_id`, `coin_reward`, `expires_at?` (earned coin son kullanma) | Ödül cüzdana yazıldığında | `RewardsKit` | ✔ |
| `rewarded_ad_start` / `rewarded_ad_complete` / `rewarded_ad_fail` | `placement: "unlock_sheet"\|"odul_merkezi"`, `ads_used_today`, `daily_cap` | AdMob callback'leri (Faz 2) | `RewardsKit` | ✔ (complete) |

### 3.6 Push ve bildirim

| Event | Parametreler | Tetiklenme anı | Sahip | 2° |
|---|---|---|---|---|
| `push_permission_prompt` | `source: "onboarding"\|"mission"\|"ayarlar"`, `action: "grant"\|"deny"` | Sistem diyaloğu kapandığında | `AppFoundation` | ✔ |
| `push_open` | `campaign_id`, `push_type: "new_episode"\|"continue"\|"coin_reward"\|"recommendation"`, `series_id?` | Push'a dokunularak uygulama açıldığında/öne geldiğinde | `AppFoundation` | ✔ |
| `push_disabled` | `source: "ayarlar"\|"os_settings_detected"` | Kullanıcı bildirim tercihini kapattığında veya OS düzeyinde kapandığı tespit edildiğinde | `ProfileKit` | |

**Not:** `push_received` (teslimat) istemciden güvenilir ölçülemez (iOS arka plan kısıtları); teslimat sayıları APNs yanıtlarından **backend'de** loglanır. İstemci yalnızca `push_open` gönderir; open-rate paydası backend teslimat logudur.

---

## 4. Player performans metrikleri

Bu bölüm `04-player-engine.md`'deki performans bütçelerinin ölçüm sözleşmesidir. Bütçeler kanoniktir: **TTFF < 500 ms**, **swipe-to-next < 100 ms**, **60 fps kaydırma**.

| Metrik | Normatif tanım (player-teknolojisi-bağımsız davranış) | Faz 1 AVFoundation implementasyon notu | Bütçe (p90) | Alarm eşiği |
|---|---|---|---|---|
| `ttff_ms` | Oynatma niyeti (hücre aktif hale geldi / `play()` istendi) → ilk video frame'i render | `AVPlayerItem` status `.readyToPlay` + `AVPlayerItemNewAccessLogEntry.startupTime` çapraz kontrol; niyet timestamp'i `PlayerFeedViewController`'dan | < 500 ms | p90 > 800 ms (24 saat pencere) |
| `swipe_latency_ms` | Kaydırma jesti bitti (paging animasyonu hedef hücreye kilitlendi) → hedef player'da oynatma başladı | `UICollectionView` paging callback → `PlayerPool` aktif player `timeControlStatus == .playing` | < 100 ms | p90 > 200 ms |
| `stall_count` / `stall_duration_ms` | Oynatma sırasında buffer kaynaklı ≥ 250 ms duraklamalar; sayı ve toplam süre | `AVPlayerItem.isPlaybackLikelyToKeepUp` geçişleri + access log `numberOfStalls` mutabakatı | Oturum başına stall'lı oynatma oranı < %1 | > %2.5 |
| `dropped_frames` / hang | Kaydırma sırasında düşen frame ve ana thread hang'leri | MetricKit (`MXAnimationMetric`, `MXAppResponsivenessMetric`); DEBUG'da `CADisplayLink` örnekleyici | 60 fps hedefi; hang rate MetricKit "iyi" bandında | MetricKit hang rate regresyonu sürümler arası > %20 |
| `cold_start_ms` | Process start → `Splash` sonrası ilk feed hücresi etkileşime hazır | MetricKit `MXAppLaunchMetric` + kendi işaretimiz (`app_open.cold_start_ms`) | < 2.000 ms | p90 > 3.000 ms |

**Ölçüm kaynağı kapsülleme:** "Faz 1 AVFoundation implementasyon notu" kolonundaki API referansları normatif tanımın parçası DEĞİLDİR. Ölçüm kaynağı, `PlayerKit` içindeki `PlayerMetricsCollector` arkasında kapsüllenir; `AnalyticsKit` ve event kataloğu yalnız normatif davranış tanımını bilir. Player teknolojisi değişirse yalnız collector implementasyonu ve bu kolon güncellenir; normatif tanımlar, event şeması ve bütçeler değişmez (modül sınırları: `03-mimari.md`, `04-player-engine.md`).

**Raporlama kuralları:**

- Bu metrikler event kataloğundaki taşıyıcılarıyla gider: `ttff_ms` → `video_start` içinde; `swipe_latency_ms` → `swipe_next`/`swipe_prev` içinde; stall → `video_stall`. Ayrı bir "performans event'i" yoktur; boyut kesişimi (cihaz modeli × ağ tipi × app version) ortak parametrelerden gelir.
- Dashboard'lar **p50/p90/p99** raporlar; ortalama KULLANILMAZ (uzun kuyruk maskeler).
- Her release için otomatik karşılaştırma: yeni sürümün ilk 48 saatindeki p90 değerleri önceki sürümle kıyaslanır; `ttff_ms` veya `swipe_latency_ms` p90'da > %15 regresyon, release'i durdurma (phased release pause) kriteridir.
- A/B deneylerinde `stall` oranı ve `ttff_ms` **guardrail metriği** olarak zorunludur (bkz. §7.5).

---

## 5. Funnel tanımları

Funnel'lar kendi pipeline'ımızda `session_id`/`user_id` + `session_seq` ile hesaplanır. Aşağıdaki tanımlar rapor sözleşmesidir; adım tanımı değişirse funnel'ın adı da değişir (sessiz redefinisyon yasak).

### 5.1 Aktivasyon funnel'ı (ilk oturum)

**Amaç:** yeni kullanıcının ilk videoya ne kadar hızlı ve ne oranda ulaştığı. Uygulama DOĞRUDAN video ile açıldığı için (Ana Sayfa = PlayerFeed) bu funnel kısa olmalıdır.

```
app_open (cold, ilk gün)
  → onboarding_complete VEYA onboarding_skip
  → video_start (ilk)
  → video_progress checkpoint=25        ← "AKTİVE OLDU" tanımı
```

- **Aktivasyon tanımı:** İlk oturumda en az bir bölümde `video_progress checkpoint=25`.
- Hedef: ilk `video_start`'a medyan süre **< 15 sn** (app_open'dan itibaren); aktivasyon oranı kurulumların **≥ %70**'i (iç hedef; benchmark verisi yok, ilk 4 haftada kalibre edilir).
- İzlenen kırılımlar: `onboarding_skip` vs `complete`, ATT izni verilmiş/verilmemiş, `network_type`.

### 5.2 Ödeme funnel'ı (bölüm kilidi → coin satın alma)

```
episode_unlock_prompt
  ├─ unlock_coin  (bakiye yeterli → doğrudan)
  └─ coin_store_view (source=unlock_sheet)
       → coin_purchase_start
       → coin_purchase_success
       → unlock_coin (dönüş)
```

- **Kritik oran 1 — prompt→unlock:** `unlock_coin / episode_unlock_prompt` (aynı `series_id+episode_id`, 24 saat atıf penceresi).
- **Kritik oran 2 — mağaza dönüşümü:** `coin_purchase_success / coin_store_view (source=unlock_sheet)`.
- **Sızıntı analizi:** prompt'tan sonra hiçbir seçenek seçmeden `UnlockSheet` kapatılıp uygulamadan çıkanlar = churn-at-paywall kohortu; `07-retention-gamification.md`'deki win-back push'unun hedef kitlesi.
- Atıf: satın alma, kullanıcının **son 24 saat içindeki son** `episode_unlock_prompt`'una bağlanır (last-touch).

### 5.3 Abonelik funnel'ı

```
unlock_vip_upsell VEYA subscription_view (diğer kaynaklar)
  → subscription_start
  → subscription_success
  → [backend] renewal_1, renewal_2, ... / churn
```

- İstemci tarafı dönüşüm: `subscription_success / subscription_view`, `source` kırılımıyla (`unlock_sheet` kaynağının en yüksek dönüşümü vermesi beklenir — cliffhanger anı).
- Intro teklif etkisi ayrı izlenir: `is_intro=true` kohortunun 2. hafta yenileme oranı backend event'iyle birleştirilir.

### 5.4 Check-in alışkanlık funnel'ı

```
checkin_claim (day 1)
  → checkin_claim (day 2) → ... → checkin_claim (day 7, döngü tamam)
```

- **7-gün tamamlama oranı:** day-1 claim yapanların kaçı aynı döngüde day-7'ye ulaşıyor.
- **Alışkanlık köprüsü metriği:** check-in yapan kullanıcıların D7 retention'ı vs yapmayanlar (korelasyon raporu; nedensellik iddiası için §8'deki ödül eğrisi deneyi kullanılır). Benchmark bağlamı: rewarded engagement kullanan kullanıcıların ~3x daha sık geri döndüğü raporlanmıştır (adjoe — https://adjoe.io/blog/short-drama-apps-rewarded-engagement/).
- `checkin_streak_break` sonrası 48 saat içinde geri dönüş oranı, win-back push metinleri deneyinin (bkz. §8) birincil metriğidir.

---

## 6. KPI sözlüğü ve hedefler

Hedefler kanon §5'ten; benchmark satırları yalnız doğrulanmış pazar verisinden.

| KPI | Tanım / formül | Hedef | Benchmark bağlamı |
|---|---|---|---|
| **D1 retention** | Kurulum gününden (D0) sonraki takvim gününde ≥1 `app_open` yapan kullanıcı / D0 kohortu | **≥ %30** | Kategori ortalaması D1 ~%27 (Sensor Tower/adjoe) |
| **D7 retention** | D0+7. takvim gününde aktif / kohort | **≥ %10** | Kategori D7 ~%8.6 |
| **D30 retention** | D0+30. günde aktif / kohort | **≥ %5** | Kategori D14 ~%5.6; DramaBox 6. ay %17 / 12. ay %15 (uzun vade referansı) |
| **Ödeme dönüşümü (payer conversion)** | Ömür boyu ≥1 `coin_purchase_success` VEYA `subscription_success` olan kullanıcı / tüm kullanıcılar (kohort bazlı, D30 penceresi ana rapor) | **≥ %3** | — |
| **ARPDAU** | Günlük net gelir (IAP + abonelik payı + Faz 2'de reklam) / DAU | Hedef lansman sonrası kalibre edilir; ilk 8 hafta trend takibi | ReelShort 2024'te kategorinin en yüksek ARPDAU'suna sahipti (Sensor Tower) — üst sınır referansı |
| **LTV (yaklaşım)** | Kohort bazlı kümülatif net gelir eğrisi (D7/D30/D90 kesitleri) + retention eğrisinden ekstrapolasyon. Formül dayatılmaz; ilk 90 gün ampirik eğri toplanır, sonra model seçilir | LTV(D90) > blended CAC (UA başladığında) | Kategori büyümesi ağırlıkla paid-UA (ReelShort/DramaBox indirmelerinin %60-70'i paid — Sensor Tower); LTV/CAC disiplini kritik |
| **Crash-free users** | Crashlytics crash-free user oranı, sürüm bazlı | **≥ %99.8** | — |
| **TTFF p90** | §4 | **< 500 ms** | — |
| **Swipe latency p90** | §4 | **< 100 ms** | — |
| **Stall'lı oynatma oranı** | `video_stall` içeren `video_start` / tüm `video_start` | **< %1** | — |
| **Binge derinliği** | Oturum başına medyan `video_progress checkpoint=100` sayısı | İzleme metriği; hedef trend ↑ | — |
| **Aktivasyon oranı** | §5.1 tanımı | ≥ %70 (kalibre edilecek iç hedef) | — |

**Rapor sahiplikleri:** retention/aktivasyon → `ShortSeriesApp` + ürün; ödeme/ARPDAU/LTV → `WalletKit` + ürün; performans/crash → `PlayerKit` + platform. Haftalık KPI raporu tek dashboard'dan çıkar; kaynak her zaman kendi pipeline'ımızdır, Firebase yalnızca doğrulama.

---

## 7. A/B deney altyapısı

### 7.1 Mimari

Deney altyapısı iki parçadır (kanon: "A/B için feature-flag/remote-config altyapısı"):

- **`AppFoundation` / feature flags + remote config:** Backend'den (`05-veri-modeli-api.md`'deki config endpoint'i) imzalı bir config yükü çekilir: flag'ler, deney tanımları (key, varyantlar, trafik yüzdeleri, salt, durum). Cache'lenir; app_open'da async yenilenir, **oturum ortasında varyant değişmez** (yeni config bir sonraki oturumda etkinleşir).
- **`AnalyticsKit` / deney istemcisi:** atama hesabı (deterministik bucketing), exposure event'i, `ab_variants` ortak parametresinin beslenmesi.

Firebase Remote Config bu mimaride **kullanılmaz**; tek doğruluk kaynağı kendi backend config'imizdir (atama ve analiz aynı pipeline'da kalsın diye). Firebase A/B testing yalnızca acil push-metni denemeleri gibi istemci-dışı senaryolar için opsiyon olarak açık bırakılır.

### 7.2 Deterministik bucketing

Atama sunucu çağrısı gerektirmez, offline çalışır ve cihazlar arasında tutarlıdır çünkü `user_id`'ye bağlıdır:

```swift
import CryptoKit

public struct ExperimentAssigner: Sendable {
    /// 0..9999 arası deterministik bucket.
    /// Aynı user_id + experiment_key + salt her zaman aynı sonucu verir.
    public static func bucket(userID: String, experimentKey: String, salt: String) -> Int {
        let input = Data("\(experimentKey):\(salt):\(userID)".utf8)
        let digest = SHA256.hash(data: input)
        let value = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Int(value % 10_000)
    }

    public static func variant(for experiment: ExperimentConfig, userID: String) -> String? {
        guard experiment.status == .running else { return nil }
        let b = bucket(userID: userID, experimentKey: experiment.key, salt: experiment.salt)
        guard b < experiment.trafficBasisPoints else { return nil } // deneye dahil değil
        var cumulative = 0
        let scaled = b * experiment.variants.map(\.weight).reduce(0, +) / experiment.trafficBasisPoints
        for v in experiment.variants {
            cumulative += v.weight
            if scaled < cumulative { return v.name }
        }
        return experiment.variants.last?.name
    }
}
```

**Kurallar:**

- Her deneyin kendi `salt`'ı vardır → deneyler arası atama korelasyonu yoktur (bir deneyin control'ü diğerinin de control'ü olmaz).
- **Yapışkanlık (stickiness):** Atama `user_id`'ye bağlı olduğu ve anonim misafir `user_id`'si hesap bağlandığında korunduğu için (kanon §2, kimlik modeli) varyant değişmez. Edge case: kullanıcı **farklı bir cihazdaki mevcut hesaba giriş yaparsa** `user_id` değişebilir → varyant değişimi meşrudur, analiz `user_id` bazlıdır.
- Trafik artırma (ramp) yalnızca `trafficBasisPoints` yükselterek yapılır; salt değişmez → mevcut kullanıcılar varyant değiştirmez, yeni trafik eklenir.
- Aynı yüzeyi hedefleyen deneyler backend'de "çakışma grubu" ile işaretlenir; bir kullanıcı aynı gruptan yalnızca 1 deneye girer.

### 7.3 Exposure (maruz kalma) event'i

```
ab_exposure  |  exp_key, variant, first_exposure: bool  |  Varyantın davranışı İLK KEZ gerçekten
tetiklendiğinde (ör. UnlockSheet deneyi için sheet ilk açıldığında; atama anında DEĞİL)  |  AnalyticsKit  |  2° ✔
```

Analiz popülasyonu **exposure alanlar**dır, atananlar değil — hiç `UnlockSheet` görmemiş kullanıcı UnlockSheet deneyinin analizine girmez (dilution önlenir). `ab_variants` ortak parametresi yine tüm event'lerde taşınır (kesişim analizleri için).

### 7.4 Deney yaşam döngüsü

1. **Draft:** Deney dokümanı (hipotez, birincil metrik, guardrail'ler, MDE, süre, örneklem hesabı) yazılır; şablon repo'da.
2. **QA:** `Ayarlar` içindeki gizli debug menüsünden (yalnız internal build) varyant zorlama (`force_variant`) ile her varyant test edilir. Zorlanmış atamalar `ab_exposure` göndermez.
3. **Ramp:** %5 → 24-48 saat guardrail kontrolü (crash-free, stall, TTFF) → %50 (control %50) hedef örnekleme kadar.
4. **Karar:** Önceden yazılmış süre/örneklem dolmadan durdurma yok (peeking yasağı, aşağıda). Sonuç: ship / iterate / kill.
5. **Rollout & temizlik:** Kazanan varyant remote config'de %100'e alınır; **2 sürüm içinde** deney kodu silinip kalıcı koda çevrilir. Ölü flag bırakmak lint ihlalidir.

### 7.5 Minimum örneklem ve istatistik yaklaşımı

- **Test:** İki oranın karşılaştırması için two-tailed z-testi, α = 0.05, güç = 0.8. Sürekli metriklerde (watch_time) Welch t-testi; çarpık dağılımlarda log-dönüşüm veya bootstrap.
- **Hızlı örneklem formülü (Lehr):** varyant başına `n ≈ 16 · p(1−p) / Δ²`. Örnek: ödeme dönüşümü baseline %3, MDE +0.5 puan (mutlak) → `n ≈ 16 · 0.0291 / 0.005² ≈ 18.600` kullanıcı/varyant. Bu, düşük DAU'lu lansman döneminde ödeme deneylerinin **haftalar süreceği** anlamına gelir → lansman başında yüksek-trafikli yüzeylerde (aktivasyon, player) deney yapılır, ödeme deneyleri DAU büyüyünce açılır.
- **Peeking yasağı:** Süre dolmadan p-değerine bakıp durdurmak yok. Erken durdurma ihtiyacı öngörülüyorsa deney dokümanında **sequential test** (ör. sabit bakış noktaları + O'Brien-Fleming düzeltmesi) baştan deklare edilir.
- **Guardrail metrikleri (her deneyde zorunlu):** crash-free, `video_stall` oranı, `ttff_ms` p90, D1 retention. Guardrail'de anlamlı kötüleşme = otomatik kill, birincil metrik ne derse desin.
- **Çokluk düzeltmesi:** ≥3 varyant veya ≥3 birincil metrik varsa Bonferroni (pratik ve muhafazakâr) uygulanır; ideal tasarım tek birincil metriktir.

---

## 8. Başlangıç deney backlog'u

Öncelik sırasıyla; her satır §7.4'teki şablonla ayrı deney dokümanına açılır. Fiyat/paket içerikleri `06-monetizasyon.md` kanonuna bağlıdır.

| # | Deney | Hipotez | Varyantlar | Birincil metrik | Guardrail'e ek | Sahip |
|---|---|---|---|---|---|---|
| E1 | **Ücretsiz bölüm sayısı** | Daha fazla ücretsiz bölüm, prompt anına daha bağlanmış kullanıcı getirir; dönüşüm × hacim çarpımı artar | 5 / 8 / 10 ücretsiz bölüm (API `unlockPrice` şeması üzerinden seri bazında; kilit cliffhanger kuralı korunur) | Kullanıcı başına D14 net gelir | D1 retention, prompt→unlock oranı | `WalletKit` + içerik |
| E2 | **UnlockSheet varyantları** | Seçenek sıralaması/vurgusu dönüşümü değiştirir | control: coin birincil · v1: VIP birincil vurgu · v2: reklam seçeneği görünür ama ikincil (Faz 2 ile) | prompt→unlock (herhangi bir yolla) | Abonelik funnel'ı dönüşümü (yamyamlaşma kontrolü) | `WalletKit` |
| E3 | **CoinMagazasi vitrini** | İlk yükleme 2x bonus teklifinin konumu ve paket sıralaması ilk satın almayı hızlandırır | control: fiyat artan sırada · v1: "en popüler" rozeti $9.99'da · v2: ilk-yükleme teklifi sheet'in en üstünde sabit | İlk `coin_purchase_success`'e medyan süre + mağaza dönüşümü | ARPDAU (paket aşağı kayması riski) | `WalletKit` |
| E4 | **Check-in ödül eğrisi** | Öne yüklü eğri (erken günler daha cömert) 7-gün tamamlamayı artırır | control: doğrusal artan (10→50) · v1: öne yüklü · v2: day-7 jackpot vurgulu | 7-gün döngü tamamlama oranı | Earned coin enflasyonu (günlük earned/purchased oranı), D7 | `RewardsKit` |
| E5 | **Push metin varyantları** | Cliffhanger-referanslı kişisel metin, jenerik metinden daha yüksek açılma alır | continue-watching push'unda: control jenerik · v1 dizi adı + bölüm no · v2 merak boşluğu (cliffhanger tease) | `push_open` oranı (payda: backend teslimat) | `push_disabled` oranı (yorulma sinyali) | `AppFoundation` + CRM |

Backlog'un devamı (Faz 2+): rewarded ad günlük cap değeri (5 vs 10, remote config'te hazır), `Onboarding` tür seçimi zorunlu/atlanabilir, `Kesfet` raf sıralaması.

---

## 9. Gizlilik ve uyumluluk

### 9.1 ATT (App Tracking Transparency) akışı

- **Ne zaman:** Kanon gereği ATT istemi `Onboarding` içinde, **değer önerisi gösterildikten SONRA** sorulur (dil/tür adımlarının ardından, bildirim izniyle aynı adımda ama ayrı diyalog olarak). Soğuk açılışta ilk saniyede ATT diyaloğu göstermek yasaktır.
- **Nasıl:** Sistem diyaloğundan önce tek ekranlık pre-prompt açıklaması gösterilir ("daha isabetli öneriler ve reklam deneyimi için"); pre-prompt sistem diyaloğunu taklit edemez ve "İzin ver"e yönlendiren manipülatif tasarım içeremez (App Review 5.1.1/5.1.2 uyumu). Sonuç `onboarding_att_prompt` event'iyle loglanır.
- **Kapsam gerçeği:** Faz 1'de üçüncü taraf reklam SDK'sı yoktur (AdMob Faz 2). Firebase Analytics IDFA toplamayacak şekilde yapılandırılır (`isAdIdCollectionEnabled = false` karşılığı config). Bu nedenle Faz 1'de ATT'nin pratik faydası sınırlıdır; **karar:** ATT istemi Onboarding akışında remote config bayrağıyla kapatılabilir tutulur ve Faz 2 (AdMob) öncesinde açılır. Bayrak kapalıyken `onboarding_att_prompt` hiç üretilmez.
- ATT reddi hiçbir özelliği kısıtlamaz; iç analitik (kendi pipeline) ATT kapsamında "tracking" değildir çünkü üçüncü taraflarla kullanıcı/cihaz düzeyinde veri birleştirmesi yapılmaz — bu sınır korunmalıdır (ör. event verisini reklam ağlarına audience olarak göndermek bu beyanı bozar ve ayrı hukuki inceleme gerektirir).

### 9.2 IDFA'sız ölçüm: SKAdNetwork / AdAttributionKit

- Paid UA başladığında kurulum atıfı **SKAdNetwork 4.x + AdAttributionKit** (iOS 17.4+) ile IDFA'sız yapılır. Kategori büyümesinin paid-UA ağırlıklı olduğu doğrulanmış veridir (ReelShort/DramaBox indirmelerinin %60-70'i paid — Sensor Tower); bu yüzden conversion value tasarımı lansmandan ÖNCE hazır olmalıdır.
- **Conversion value şeması (ilk sürüm, 64 değerlik fine grain):** ilk 24-48 saatteki en güçlü LTV sinyallerini kodlar — aktivasyon (`video_progress 25`), izlenen bölüm sayısı bandı, `episode_unlock_prompt` görüldü mü, `coin_purchase_success`/`subscription_success` gerçekleşti mi ve gelir bandı. Coarse grain (low/medium/high): high = ödeme, medium = unlock prompt + derin izleme, low = yalnız kurulum/açılış.
- Postback pencereleri (SKAN 4: 3 postback) şemasıyla birlikte `AnalyticsKit` içinde tek bir `ConversionValueEncoder` tipinde yönetilir; şema değişikliği `events.yaml` gibi versiyonlanır.

### 9.3 GDPR / CCPA — silme ve erişim talepleri

- **Giriş noktası:** `Ayarlar` → hesap yönetimi → "Hesabımı ve verilerimi sil". Apple gereksinimi: hesap oluşturma sunan uygulama, uygulama İÇİNDEN hesap silme sunmak zorundadır — misafir hesap dahil.
- **Davranış:** Silme talebi backend'e iletilir; istemci onay sonrası local state'i temizler (SwiftData store, Keychain token, UserDefaults, analitik disk kuyruğu). Backend: kullanıcı kaydı + event verisinde `user_id` anahtarlı kayıtların silinmesi/anonimleştirilmesi, **30 gün SLA**. Analitik tarafında istemci YALNIZ `AnalyticsClient.deleteUserData()` çağırır; bu çağrı kayıtlı tüm sink'lere yayılır (bkz. §1.3). Vendor'a özgü silme API'leri (ör. Firebase instance ID reset + `deleteData`, Crashlytics kayıt temizliği) ilgili sink implementasyonlarının İÇİNDEDİR — ürün kodu ve `ProfileKit` hiçbir vendor silme API'si görmez.
- **Veri erişim/taşınabilirlik (GDPR Art. 15/20, CCPA):** Faz 1'de destek e-postası üzerinden manuel süreç; `Ayarlar` → yasal bölümünde açık talimat. Uygulama içi otomatik export Faz 3 adayı.
- **Consent yönetimi:** ABD öncelikli lansmanda GDPR banner'ı zorunlu değildir; AB'ye açılım (EN zaten destekli) öncesinde bölge bazlı consent katmanı remote config ile devreye alınacak şekilde `AppFoundation`'da soyutlanır (analitik sink'leri consent state'ine göre açılıp kapanabilir olmalı — kabul kriteri: consent kapalıyken kendi pipeline'a yalnızca anonim, oturum bazlı zorunlu teknik telemetri gider veya hiçbir şey gitmez; karar hukuk danışmanlığıyla netleştirilir).

### 9.4 App Privacy "nutrition label" beyanları

App Store Connect beyanı (Faz 1 gerçek durumu; her SDK eklemesinde güncellenir ve `PrivacyInfo.xcprivacy` manifest'leriyle tutarlı olmalıdır):

| Veri türü | Toplanıyor mu | Kullanıcıyla ilişkili mi | Tracking mi | Amaç |
|---|---|---|---|---|
| E-posta (hesap bağlanırsa) | Evet | Evet | Hayır | Hesap yönetimi |
| Kullanıcı ID (opak) | Evet | Evet | Hayır | Uygulama işlevi, analitik |
| Satın alma geçmişi | Evet | Evet | Hayır | Uygulama işlevi, analitik |
| İzleme geçmişi / ürün etkileşimi | Evet | Evet | Hayır | Uygulama işlevi, analitik, kişiselleştirme |
| Arama geçmişi (`search_query`) | Evet | Evet | Hayır | Uygulama işlevi, analitik |
| Crash & performans verisi | Evet | Evet (Crashlytics user-linked) | Hayır | Uygulama işlevi |
| Cihaz ID (IDFA) | Faz 1: Hayır · Faz 2 (AdMob + ATT izni): Evet | Evet | **Evet** (yalnız izinli kullanıcılar) | Üçüncü taraf reklam |
| Konum, kişiler, fotoğraflar, sağlık vb. | Hayır | — | — | — |

Üçüncü taraf SDK'lar (Firebase, Crashlytics, Faz 2'de AdMob) Apple'ın zorunlu kıldığı privacy manifest'leri ve imzalarıyla eklenir; her SDK sürüm yükseltmesinde manifest diff'i release checklist'ine dahildir.

### 9.5 Çocuk gizliliği ve yaş derecelendirmesi

- **Hedef derecelendirme: 17+.** İçerik türü (yoğun romantik/dramatik temalar) ve reklam/IAP baskısı nedeniyle App Store yaş derecelendirme anketi 17+ sonuç verecek şekilde doldurulur. Bu bilinçli bir konumlandırmadır: hedef demografi 25-45 kadın (kanon §5), çocuklara yönelik bir uygulama DEĞİLDİR.
- Uygulama "Made for Kids" kategorisinde olmadığı ve 17+ hedeflendiği için COPPA'nın "çocuklara yönelik hizmet" yükümlülükleri tetiklenmez; yine de yaş beyanı toplanmaz, çocuklara yönelik pazarlama yapılmaz ve Faz 2 reklam entegrasyonunda AdMob "child-directed" işareti kapalı, içerik derecelendirme filtresi (max ad content rating) uygulamanın 17+ profiliyle tutarlı ayarlanır.
- IAP koruması: sistem düzeyinde Ask to Buy / Screen Time kısıtlarına müdahale edilmez; `CoinMagazasi` fiyatları her zaman StoreKit'ten okunur (lansman öncesi güncel App Store fiyatlarının doğrulanması notu: rakip fiyat kıyasları kaynaklar arasında tutarsızdır, `06-monetizasyon.md`'deki tablo lansman öncesi App Store'dan doğrulanmalıdır).

### 9.6 Saklama ve minimizasyon

- Ham event verisi backend'de 13 ay saklanır (yıllık sezonluk kıyas + 1 ay); sonrasında toplulaştırılmış tablolara indirgenir. `search_query` ham metni 90 gün.
- İstemci disk kuyruğu yalnızca gönderilmemiş event'leri tutar; başarılı upload sonrası silinir.
- DEBUG/internal build'lerin event'leri `environment: "internal"` parametresiyle işaretlenir ve üretim metriklerinden hariç tutulur.

---

## 10. Kabul kriterleri (özet checklist)

- [ ] `AnalyticsKit.track()` ana thread'i bloklamaz; PlayerFeed'de 60 fps korunur (Instruments ile doğrulanır).
- [ ] Uygulama öldürülüp açıldığında gönderilmemiş event'ler diskte durur ve ilk fırsatta yüklenir; backend'de `event_id` çift kaydı yoktur.
- [ ] §3 kataloğundaki her event, `events.yaml` registry'sinde tanımlıdır ve DEBUG şema doğrulamasından geçer.
- [ ] `coin_purchase_success` yalnızca server-side doğrulama sonrası atılır; StoreKit başarısı tek başına yeterli değildir.
- [ ] Aynı `user_id` iki cihazda aynı deney için aynı varyantı alır (bucketing birim testi + cihazlar arası manuel doğrulama).
- [ ] `ab_exposure` yalnızca varyant davranışı ilk tetiklendiğinde, kullanıcı başına deneyde 1 kez `first_exposure=true` ile gider.
- [ ] ATT istemi yalnız Onboarding'de, değer önerisinden sonra ve remote config bayrağı açıkken gösterilir.
- [ ] Hesap silme akışı: istemci local temizlik + backend silme talebi + `AnalyticsClient.deleteUserData()` çağrısı (vendor silme API'leri sink implementasyonlarında kalır — bkz. §1.3/§9.3); QA senaryosu yazılıdır.
- [ ] Release checklist'i: privacy manifest diff kontrolü + §4 performans regresyon karşılaştırması içerir.
