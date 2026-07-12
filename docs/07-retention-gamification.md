# Retention, Gamification ve Bildirim Stratejisi

**Amaç:** Bu doküman, ShortSeries iOS istemcisinin kullanıcıyı platformda tutan tüm mekaniklerini — binge döngüsü, günlük check-in, görev sistemi, push bildirim stratejisi, deep link entegrasyonu, winback akışları ve Live Activities konseptini — geliştirme ekibinin doğrudan uygulayabileceği düzeyde spesifiye eder. Kuzey yıldızımızın 2 numaralı maddesi ("kullanıcının platformdan çıkmak istememesi") bu dokümanın konusudur. Retention'ın birincil motoru gamification değil, içeriğin kendisi ve kesintisiz izleme deneyimidir; buradaki mekanikler o motoru destekleyen ikincil katmandır ve hiçbir mekanik izleme deneyimini kesintiye uğratamaz.

**İlgili dokümanlar:** `00-genel-bakis.md` (hedefler ve KPI'lar), `01-ozellik-envanteri.md` (özellik fazları), `02-ekran-haritasi-navigasyon.md` (ekran haritası, deep link şeması, Coordinator route'ları), `03-mimari.md` (RewardsKit/AppFoundation modül sınırları, DI), `04-player-engine.md` (otomatik sonraki bölüm ve player davranışı), `05-veri-modeli-api.md` (Mission, CheckIn, Wallet, Notification API sözleşmeleri), `06-monetizasyon.md` (coin ekonomisi, earned/purchased ayrımı, UnlockSheet), `08-analitik-deney.md` (event şeması, A/B deney altyapısı), `09-yol-haritasi-tasklar.md` (faz planı), `10-arastirma-raporu.md` (kaynaklar).

---

## 1. Retention hedefleri ve benchmark

### 1.1 Kategori gerçeği

Short-drama kategorisi çok dik bir retention decay eğrisine sahiptir. Kullanıcı bir diziyi bitirdiğinde veya paywall'a çarptığında büyük oranda kaybedilir. Doğrulanmış kategori verileri (Sensor Tower; adjoe — https://adjoe.io/blog/short-drama-apps-rewarded-engagement/):

| Metrik | Kategori ortalaması | DramaBox | ShortSeries hedefi |
|---|---|---|---|
| D1 retention | ~%27 | ~%27.5 | **≥ %30** |
| D7 retention | ~%8.6 | ~%7.8 | **≥ %10** |
| D14 retention | ~%5.6 | ~%5.0 | (ara metrik, hedef bağlanmaz) |
| D30 retention | — | — | **≥ %5** |
| Ay 6 retention | — | %17 | (uzun vadeli referans) |
| Ay 12 retention | — | %15 | (uzun vadeli referans) |

Ek doğrulanmış veri: **rewarded engagement (ödül döngüsüne giren) kullanıcılar, girmeyenlere göre ~3x daha sık geri dönüyor** (adjoe, https://adjoe.io/blog/short-drama-apps-rewarded-engagement/). Bu, OdulMerkezi'nin ve görev sisteminin varlık sebebidir: ödül döngüsüne alınan her kullanıcı, dönüş sıklığı açısından farklı bir kohorta geçer.

> Not: Rakip fiyat/limit ayrıntıları (ör. rewarded ad cap'leri, coin fiyatları) kaynaklar arasında tutarsız raporlanmaktadır; bu dokümandaki rakip verileri yalnız yukarıdaki doğrulanmış set ile sınırlıdır. Rakip fiyatlandırma detayları lansman öncesi güncel App Store listelemelerinden doğrulanmalıdır.

### 1.2 Hedeflerin sahiplenilmesi ve ölçümü

- Retention kohort tanımı, event şeması ve dashboard'lar `08-analitik-deney.md`'de tanımlıdır. Bu dokümandaki her mekanik, o şemadaki event'leri üretir (bkz. §10).
- D1 hedefi ağırlıkla **ilk oturum deneyimine** bağlıdır (Splash → PlayerFeed doğrudan video açılışı, `04-player-engine.md` performans bütçeleri). D7/D30 hedefleri bu dokümandaki mekaniklerin alanıdır.
- Her mekanik lansmanı bir A/B deneyi olarak çıkar (holdout grubu zorunlu); "mekanik retention'ı gerçekten artırıyor mu?" sorusu varsayım değil ölçümdür.

### 1.3 Retention katmanları (öncelik sırası)

1. **İçerik + binge döngüsü** (§2) — birincil motor. Cliffhanger, otomatik sonraki bölüm, "devam et" yüzeyleri.
2. **Yeni bölüm takvimi** — diziler bölüm bölüm yayınlanabilir (release schedule API'den, `05-veri-modeli-api.md`); "yarın yeni bölüm" başlı başına dönüş sebebidir.
3. **Gamification** (§3–§4) — check-in, streak, görevler; ödeme yapmayan kullanıcıyı coin döngüsüne alır (`06-monetizasyon.md` earned coin ekonomisi).
4. **Push + deep link** (§5–§6) — kullanıcı uygulamadayken değil, dışındayken çalışan tek kanal.
5. **Winback** (§7) — churn'e giden kullanıcıya son müdahale.

---

## 2. Binge döngüsü tasarımı — retention'ın birincil motoru

### 2.1 Döngünün anatomisi

```
Bölüm izlenir → cliffhanger'da biter → otomatik sonraki bölüm (<100 ms)
      ↑                                        │
      │                              kilitli bölüm ise → UnlockSheet
      │                                        │
"Devam et" yüzeyleri  ←── oturum biter ──← (aç / reklam / VIP / çık)
(PlayerFeed, Listem, DiziDetay, push)
```

- **Cliffhanger** içerik ekibinin işidir; istemci açısından görünümü, kilit noktasının cliffhanger'a denk gelmesidir (kilit konumu ve `unlockPrice` API'den okunur, `06-monetizasyon.md`).
- **Otomatik sonraki bölüm**: PlayerFeed'de bölüm bittiğinde aynı dizinin sonraki bölümü otomatik oynar; dizi bitince/atlanınca yeni dizi önerisi gelir. Geçiş bütçesi < 100 ms (prefetch ve player havuzu davranışı `04-player-engine.md`'de). Otomatik oynatma Ayarlar'dan kapatılabilir; kapalıysa bölüm sonunda "Sonraki Bölüm" kartı gösterilir, akış otomatik ilerlemez.
- Bu döngü, gamification'dan bağımsız olarak D1'in ana belirleyicisidir. Gamification yüzeyleri (rozet, toast) bu döngüyü asla kesemez (bkz. §3.4, §9).

### 2.2 "Devam et" yüzeyleri (sözleşme)

Kaldığı yer (`progress`: seriesId, episodeNumber, positionSec) her oynatmada lokal olarak (SwiftData) ve periyodik olarak backend'e yazılır (`05-veri-modeli-api.md`). Tüm yüzeyler aynı kaynaktan okur:

| Yüzey | Davranış | Öncelik kuralı |
|---|---|---|
| **PlayerFeed** (Ana Sayfa) | Soğuk açılışta, kullanıcının yarım kalmış bir dizisi varsa feed'in ilk öğesi "kaldığın yer"den devam eden bölümdür; yoksa For You önerisi. | Son izlenen ve bitmemiş dizi > For You. Remote config ile kapatılabilir (A/B). |
| **Listem → Devam Et** segmenti | İzleme geçmişi + her dizide kaldığı bölüm/saniye; hücrede ilerleme çubuğu ve "Devam Et" CTA. | Son izlenme zamanına göre sıralı. |
| **DiziDetay** | CTA metni duruma göre: hiç izlenmemişse "İzlemeye Başla", yarım kalmışsa "Devam Et — B{n}". | Progress varsa her zaman "Devam Et". |
| **Push** | "Kaldığın yerden devam" kampanyası (§5.2) deep link ile doğrudan ilgili bölüme, kaldığı saniyeden açar. | Frekans limitine tabidir. |

**Edge case'ler:**
- Bölüm %90+ izlendiyse "bitti" sayılır; devam noktası bir sonraki bölümün başıdır (eşik remote config: `progress.completedThreshold = 0.9`).
- Devam edilecek bölüm kilitliyse yüzeyler yine o bölümü hedefler; oynatma girişiminde UnlockSheet açılır (kullanıcıdan kilidi saklamak karanlık kalıptır, göstermemek değil erken göstermek doğrudur — hücrede kilit ikonu görünür).
- Cihazlar arası senkron: backend progress'i kazanır; lokal daha yeniyse (timestamp karşılaştırması) lokal push edilir.
- Dizi yayından kaldırıldıysa Devam Et hücresi "Bu dizi artık yayında değil" durumuna düşer ve bir sonraki açılışta listeden temizlenir; feed bu diziyi atlar.

**Kabul kriterleri:**
- [ ] Uygulama soğuk açılışta yarım dizi varsa ilk video kaldığı bölüm+saniyeden başlar (Splash ön-yüklemesi bunu hazırlar).
- [ ] Aynı progress dört yüzeyde de tutarlıdır (tek repository, `LibraryKit`).
- [ ] Otomatik sonraki bölüm geçişi < 100 ms (kilitsiz, prefetch tamamlanmış durumda).
- [ ] Otomatik oynatma kapalıyken hiçbir otomatik geçiş olmaz.

---

## 3. Günlük check-in ve streak

### 3.1 Ödül takvimi

7 günlük artan döngü, 10–50 coin (kanonik aralık). **Tüm değerler remote config'ten gelir**; aşağıdaki tablo lansman varsayılanıdır:

| Gün | Ödül (earned coin) | Not |
|---|---|---|
| 1 | 10 | |
| 2 | 15 | |
| 3 | 20 | |
| 4 | 25 | |
| 5 | 30 | |
| 6 | 40 | |
| 7 | 50 | + "7 gün" streak rozeti/animasyonu |

Döngü toplamı 190 coin ≈ 2–4 bölüm kilidi (bölüm kilidi 50–100 coin, `06-monetizasyon.md`). 7. günden sonra döngü 1. günden yeniden başlar (streak sayacı artmaya devam eder; ödül takvimi 7'lik döngüdür).

Check-in ödülleri **earned coin**'dir: harcama önceliği earned-önce, son kullanma tarihi olabilir (`06-monetizasyon.md`, cüzdan kuralları). İstemci bakiyeyi asla lokal hesaplamaz; `claim` yanıtındaki cüzdan durumunu gösterir.

### 3.2 Streak kuralları

- **Gün tanımı:** Server-otoritatif. Gün sınırı, kullanıcının cihaz saat diliminde 00:00'dır; istemci her istekte IANA timezone gönderir, backend doğrular ve karar verir. Cihaz saati manipülasyonu bu yüzden işe yaramaz (fraud kontrolleri `05-veri-modeli-api.md` cüzdan bölümünde).
- **Kaçırılan gün (Faz 1):** Streak sıfırlanır; kullanıcı ertesi gün 1. günden başlar. Sıfırlama cezalandırıcı bir dille sunulmaz ("Yeni bir seri başlat!" çerçevesi).
- **Streak koruma jetonu (Faz 2):** Ayda 1 otomatik koruma hakkı: tek gün kaçıran kullanıcının streak'i korunur, kullanıcıya "Streak'in korundu" bilgisi verilir. Kural parametreleri (ay başına hak, VIP'e ek hak) remote config. Faz 1'de bu mekanik YOKTUR ve mevcut API sözleşmesinde (`05-veri-modeli-api.md` §2.10 `CheckInState`) karşılığı olan bir alan da yoktur; Faz 2'de gereken alan (ör. `streakProtectionAvailable`), sözleşmenin sahibi olan `05-veri-modeli-api.md`'ye eklenmelidir.
- **Timezone değişikliği:** Kullanıcı saat dilimi değiştirirse aynı takvim günü içinde ikinci check-in yapılamaz (server, son check-in'in UTC anını da tutar; 20 saatten kısa aralıkla ikinci claim reddedilir — `RETRY_TOMORROW`).
- **Offline:** Check-in yalnız online yapılabilir. Offline durumda takvim son bilinen durumu gösterir, buton devre dışı + "Bağlantı gerekli" etiketi.

### 3.3 Claim akışı ve API sözleşmesi

Endpoint sözleşmesinin sahibi `05-veri-modeli-api.md`'dir; davranışsal beklenti:

- `GET /rewards/checkin` → `CheckInState = { cycleDay, todayClaimed, todayReward, schedule[7], streakDays, streakBonusAt?, streakBonusCoins? }` (`05-veri-modeli-api.md` §2.10)
- `POST /rewards/checkin/claim` (`Idempotency-Key` header zorunlu) → `{ reward: { coins, bucket: "earned", expiresAt? }, checkin: CheckInState, wallet: Wallet }` (`05-veri-modeli-api.md` §4.7)
- Çifte claim (aynı gün) → `409 ALREADY_CLAIMED`; istemci `CheckInState`'i yanıttaki `details.checkin` ile senkronlar, hata toast'ı göstermez (durumu sessizce düzeltir).
- Claim yanıtı güncel cüzdan durumunu (`wallet`) içerir; `WalletStore` (actor, `WalletKit`) bakiyeyi bu yanıtla günceller.

### 3.4 UI davranışı

- **OdulMerkezi (Ödüller sekmesi):** Sayfanın en üstünde 7 günlük takvim şeridi: geçmiş günler işaretli, bugün vurgulu + coin miktarı + "Ödülü Al" butonu, gelecek günler soluk. Claim animasyonu coin bakiyesine uçan parçacık; bakiye başlıkta canlı güncellenir. Altında görev listesi (§4) ve rewarded ad kartı.
- **PlayerFeed'de rozet:** Check-in yapılmamış günlerde Ödüller sekme ikonunda kırmızı nokta (badge). PlayerFeed'in kendi UI'ında ek olarak, oturumun **ilk bölümü bittiğinde bir kez**, alt kenarda 3 sn'lik dismissible bir çip gösterilebilir ("Günlük ödülün hazır — 20 coin"). Kurallar: oynatmayı asla duraklatmaz, video üzerine modal açmaz, oturum başına en fazla 1 kez, remote config ile tamamen kapatılabilir. Tıklanırsa Ödüller sekmesine geçilir.
- Check-in **hiçbir zaman** uygulama açılışında otomatik modal olarak dayatılmaz (bkz. §9 — açılış modal'ı hem binge döngüsünü keser hem karanlık kalıba yaklaşır).

### 3.5 Swift iskeleti (RewardsKit)

```swift
// RewardsKit — CheckInStore.swift
import Observation

@Observable
public final class CheckInStore {
    public private(set) var state: CheckInViewState = .loading
    public private(set) var isClaiming = false

    private let api: RewardsAPIClient          // AppFoundation networking üzerinden
    private let wallet: WalletStore            // actor, WalletKit
    private let analytics: AnalyticsTracking   // AppFoundation protokolü (canlı impl: AnalyticsKit — 03 §5.1)

    public init(api: RewardsAPIClient, wallet: WalletStore, analytics: AnalyticsTracking) { ... }

    public func refresh() async {
        state = await (try? api.checkInStatus(timezone: TimeZone.current.identifier))
            .map(CheckInViewState.loaded) ?? .failed
    }

    public func claimToday() async {
        guard case .loaded(let s) = state, !s.todayClaimed, !isClaiming else { return }
        isClaiming = true; defer { isClaiming = false }
        do {
            let result = try await api.claimCheckIn(idempotencyKey: UUID().uuidString,
                                                    timezone: TimeZone.current.identifier)
            await wallet.apply(result.wallet)
            analytics.track(.checkinCompleted(day: result.checkin.cycleDay,
                                              streak: result.checkin.streakDays,
                                              coins: result.reward.coins))
            await refresh()
        } catch RewardsError.alreadyClaimed {
            await refresh()                    // sessiz senkron, toast yok
        } catch {
            state = .failed                    // retry CTA'lı hata durumu
        }
    }
}

public enum CheckInViewState { case loading, loaded(CheckInState), failed } // CheckInState: 05 §2.10 modeli
```

**Kabul kriterleri:**
- [ ] Aynı takvim gününde ikinci claim UI'dan tetiklenemez; API'den 409 gelirse UI sessizce senkronlanır.
- [ ] Streak kaçırma sonrası takvim 1. günden gösterilir, streak sayacı 0'dan başlar (Faz 1).
- [ ] Timezone değişikliğiyle çifte claim server tarafından engellenir; istemci bunu hata olarak değil "yarın tekrar gel" olarak gösterir.
- [ ] Ödüller sekme rozeti, check-in yapılınca aynı oturumda kaybolur.
- [ ] Claim edilen coin'ler cüzdanda "earned" olarak işaretlenir ve earned-önce harcanır (`06-monetizasyon.md` ile entegrasyon testi).

---

## 4. Görev sistemi

### 4.1 Görev kataloğu

Görevler backend'ten gelir (istemcide hardcode görev YOKTUR); aşağıdaki tablo lansman kataloğu önerisidir. Alan adları ve enum değerleri `05-veri-modeli-api.md` §2.9 `Mission` modelinindir (`kind`, `rewardCoins`, `resetPolicy`); haftalık görevler ayrı bir tip değil, aynı `kind`'ın `resetPolicy: weekly` örneğidir. Ödüller earned coin'dir ve remote config/backend'ten ayarlanır:

| Görev | `kind` | Hedef (örnek) | `rewardCoins` (örnek) | `resetPolicy` | İlerleme kaynağı |
|---|---|---|---|---|---|
| İzleme süresi (günlük) | `watchMinutes` | 10 dk izle | 20 | `daily` | Player heartbeat (`04-player-engine.md`) |
| Bölüm bitir (günlük) | `completeEpisodes`* | 3 bölüm bitir | 20 | `daily` | `episode_completed` event'i |
| Favorile | `favoriteSeries` | 1 dizi favorile | 10 | `daily` | Listem/Favoriler aksiyonu |
| Paylaş | `shareSeries` | 1 dizi paylaş | 15 | `daily` | Paylaşım sheet'i tamamlanınca |
| İzleme süresi (haftalık) | `watchMinutes` | 60 dk izle | 60 | `weekly` (Pzt 00:00) | Player heartbeat |
| Bölüm bitir (haftalık) | `completeEpisodes`* | 15 bölüm bitir | 50 | `weekly` | `episode_completed` |
| Bildirim izni ver | `enableNotifications` | İzin ver | 30 | `oneTime` | APNs authorization callback |
| Hesap bağla | `linkAccount` | Apple/Google/e-posta hesabı bağla | 30 | `oneTime` | ProfileKit |

\* `completeEpisodes`, `05-veri-modeli-api.md` §2.9'daki `Mission.Kind` enum'unda henüz tanımlı değildir; lansman kataloğuna girecekse sözleşmenin sahibi olan 05'e eklenmelidir. İstemci o zamana kadar bilinmeyen `kind` değerlerini `.unknown` olarak yok sayar (`UnknownDecodable`).

Notlar:
- `enableNotifications` görevi izin **verildiğinde** ödenir; kullanıcı sistem diyaloğunu reddederse görev açık kalır ve daha sonra Ayarlar üzerinden izin verilirse tamamlanır. Ödül vaadi pre-permission ekranında değil yalnız OdulMerkezi'nde sunulur (§9 — sistem diyaloğunu ödülle manipüle etme sınırı).
- Paylaşım görevi `UIActivityViewController` completion'ında `completed == true` ise sayılır; iptal sayılmaz. Aynı diziyi aynı gün tekrar paylaşmak ilerletmez (backend dedupe).
- Rewarded ad izleme OdulMerkezi'nde ayrı bir karttır ve görev değil doğrudan kazanç kanalıdır (günde 5–10 cap, remote config, 30 sn tamamlama şartı — `06-monetizasyon.md`).

### 4.2 Yenilenme ve durum makinesi

Görev durumları (`05-veri-modeli-api.md` §2.9 `Mission.State`): `inProgress → claimable → claimed`. `progress >= target` olduğunda `state`'i `claimable` yapan sunucudur.

- **Günlük** (`resetPolicy: daily`) görevler kullanıcının cihaz saat diliminde 00:00'da sıfırlanır (check-in ile aynı gün-sınırı kuralı, server-otoritatif).
- **Haftalık** (`weekly`) görevler Pazartesi 00:00'da sıfırlanır.
- **Tek seferlik** (`oneTime`) görevler claim sonrası listeden düşer (veya "tamamlandı" bölümüne iner).
- `claimable` durumundaki ödül **otomatik verilmez**; kullanıcı OdulMerkezi'nde "Al" butonuna basar (claim). Gerekçe: kullanıcıyı Ödüller sekmesine döndürmek (rewarded engagement döngüsü) + cüzdan işlemlerinin bilinçli olması. Gün sonunda claim edilmemiş günlük görev ödülü yanar; bu, görev kartında "bugün sona erer" etiketiyle açıkça gösterilir (sessizce yakmak karanlık kalıptır).

### 4.3 Backend sözleşmesi (Mission modeli)

Model ve endpoint'lerin sahibi `05-veri-modeli-api.md`'dir (Mission modeli). Bu dokümanın davranışsal beklentileri:

- `GET /missions` → `{ missions: [{ id, kind, title, rewardCoins, target, progress, state: inProgress|claimable|claimed, resetPolicy: daily|weekly|oneTime, expiresAt? }] }` (`05-veri-modeli-api.md` §2.9)
- `POST /missions/{id}/claim` (`Idempotency-Key` zorunlu) → check-in claim ile aynı kalıp: `reward` + güncel mission durumu + `wallet` (`05-veri-modeli-api.md` §4.7). `state != claimable` ise `409 MISSION_NOT_CLAIMABLE`.
- **İlerleme raporlama:** İstemci izleme ilerlemesini görev sistemi için ayrıca raporlamaz; backend, analitik/progress event'lerinden (player heartbeat, `episode_completed`) ilerlemeyi kendisi türetir. Bu, istemciden sahte ilerleme basılmasını zorlaştırır (anormal kazanç hızı fraud kontrolü backend'te).
- İstemci mission listesini OdulMerkezi her açılışta ve claim sonrası tazeler; PlayerFeed oturumu sırasında polling YAPMAZ.

### 4.4 Swift iskeleti (RewardsKit)

```swift
// RewardsKit — MissionStore.swift
@Observable
public final class MissionStore {
    public private(set) var missions: [Mission] = []
    public var claimableCount: Int { missions.filter { $0.state == .claimable }.count }

    private let api: RewardsAPIClient
    private let wallet: WalletStore

    public func refresh() async { missions = (try? await api.missions()) ?? missions }

    public func claim(_ mission: Mission) async throws {
        let result = try await api.claimMission(id: mission.id,
                                                idempotencyKey: UUID().uuidString)
        await wallet.apply(result.wallet)
        await refresh()
    }
}
```

Ödüller sekme rozeti sayısı = (check-in bekliyor ? 1 : 0) + `claimableCount`; `ShortSeriesApp` tab bar'ı bu değeri `RewardsKit`'ten okur.

**Kabul kriterleri:**
- [ ] Görev listesi tamamen backend'ten gelir; istemci bilinmeyen `kind` değerini `.unknown` olarak güvenle yok sayar (`UnknownDecodable`, ileri uyumluluk).
- [ ] İlerleme, izleme event'lerinden backend'te türetilir; istemcide görev-özel sayaç tutulmaz.
- [ ] Claim idempotent'tir; çevrimdışı kuyruklanmaz (buton offline'da devre dışı).
- [ ] Gün/hafta sıfırlanması sonrası eski `claimable` görevler claim edilemez ve UI'da süre uyarısı önceden gösterilmiştir.
- [ ] `enableNotifications` görevi, izin Ayarlar üzerinden sonradan verilse bile tamamlanır.

---

## 5. Push bildirim stratejisi

Altyapı: APNs + rich push (görselli) — `AppFoundation` push servisi; Notification Service Extension görsel indirme için. Kampanya orkestrasyonu backend'tedir; istemcinin sorumluluğu izin akışı, token yönetimi, tercih senkronu ve deep link işlemedir.

### 5.1 İzin isteme zamanlaması

Sistem izni diyaloğu **iOS'ta tek atımlıktır**; reddedilirse tekrar gösterilemez (kullanıcı Ayarlar'a gitmek zorunda kalır). Bu yüzden:

1. **Onboarding'de, değer önerisinden SONRA** (kanon: Onboarding 3. adım, ATT istemiyle birlikte ama ayrı ekranlarda): kullanıcı dil ve tür tercihini geçtikten sonra **pre-permission ekranı** gösterilir. İçerik: "Takip ettiğin dizide yeni bölüm çıkınca ve coin hediyeleri geldiğinde haber verelim" + görsel + iki buton: "Bildirimlere izin ver" / "Şimdi değil".
2. Kullanıcı pre-permission'da olumlu yanıt verirse **ancak o zaman** sistem diyaloğu (`UNUserNotificationCenter.requestAuthorization`) tetiklenir. "Şimdi değil" derse sistem diyaloğu YAKILMAZ.
3. **Bağlamsal yeniden isteme:** "Şimdi değil" diyen kullanıcıya, değerin en yüksek olduğu anlarda pre-permission tekrar sunulabilir: (a) bir diziyi favorileyince ("Yeni bölüm çıkınca haber verelim mi?"), (b) bölüm-bölüm yayınlanan bir dizide son yayınlanmış bölüme gelince. Frekans: en erken 3 gün arayla, toplam en fazla 3 kez (remote config).
4. Sistem izni reddedilmişse bağlamsal noktalarda "Ayarlar'dan aç" yönlendirmesi gösterilir (deep link: `UIApplication.openNotificationSettingsURLString`).
5. Onboarding atlanabilir; izin akışı hiçbir özelliği rehin almaz (bkz. §9, App Store Guideline 4.5.4: bildirimler uygulamanın çalışması için şart koşulamaz).

### 5.2 Kampanya tipleri

| Kampanya | Tetikleyici | Kategori | Örnek frekans kuralı |
|---|---|---|---|
| **Yeni bölüm** | Takip edilen/izlenen dizide release schedule'a göre yeni bölüm yayınlandı | İçerik | Dizi başına günde 1 |
| **Kaldığın yerden devam** | Yarım dizi + X saat inaktivite (varsayılan 48s, remote config) | İçerik | 72 saatte en fazla 1 |
| **Coin hediyesi** | Backend kampanyası (ör. hafta sonu bonusu) veya winback (§7) | Pazarlama | Haftada en fazla 1 |
| **Streak hatırlatma** | Aktif streak ≥ 3 gün ve gün bitimine ~3 saat kala check-in yapılmamış | Etkileşim | Günde en fazla 1; yalnız aktif streak varken |
| **Kişisel öneri** | Öneri motorundan yüksek skorlu yeni dizi; kullanıcı ≥ 24s inaktif | Pazarlama | Haftada en fazla 2 |
| **Süresi dolan coin** | Earned coin'lerin son kullanma tarihine ≤ 48 saat | İşlemsel | Coin partisi başına 1 (bkz. §7) |

### 5.3 Frekans limiti ve sessiz saatler (backend guardrail'leri)

- **Global tavan:** Kullanıcı başına günde en fazla **2** push (tüm kampanyalar toplamı), haftada en fazla **8**. İşlemsel kategori (süresi dolan coin, satın alma makbuzu vb.) tavana dahil değildir ama günde 1'i geçemez.
- **Sessiz saatler:** Kullanıcının yerel saatinde **22:00–09:00** arası gönderim yok; pencereye denk gelen kampanyalar 09:00 sonrasına kayar veya düşer (kampanya tipine göre; streak hatırlatma kayamaz, düşer).
- **Öncelik çözümü:** Aynı gün birden çok aday varsa öncelik: işlemsel > yeni bölüm > kaldığın yerden devam > streak > coin hediyesi > kişisel öneri.
- Tüm limitler remote config'tedir; A/B deneyleri limitleri kullanıcı segmenti bazında değiştirebilir (`08-analitik-deney.md`).
- **Tercihler:** Ayarlar → bildirim tercihleri, kategori bazında aç/kapa sunar (İçerik / Ödüller & pazarlama / İşlemsel-hesap). Tercihler backend'e senkronlanır; pazarlama kategorisi kapalıysa backend o kategoriden hiç göndermez. Uygulama içi kopyaları Faz 2'de BildirimMerkezi'nde listelenir.

### 5.4 Örnek metinler (EN/TR)

Metinler backend/CMS'ten lokalize gelir; ton: merak uyandıran ama dürüst — içerikte olmayan bir şey vaat etmek yasak (§9).

| Kampanya | EN | TR |
|---|---|---|
| Yeni bölüm | "Episode 12 of *Midnight Heir* just dropped. The secret's out. 👀" | "*Gece Varisi* 12. bölüm yayında. Sır ortaya çıkıyor. 👀" |
| Kaldığın yerden devam | "You left *Midnight Heir* at the worst possible moment. Pick up where you left off." | "*Gece Varisi*'ni tam o anda bıraktın. Kaldığın yerden devam et." |
| Coin hediyesi | "A little something from us: 30 coins just landed in your wallet. 🎁" | "Bizden küçük bir hediye: 30 coin cüzdanında. 🎁" |
| Streak hatırlatma | "Your 5-day streak ends at midnight. Today's check-in: 30 coins." | "5 günlük serin gece yarısı bitiyor. Bugünkü ödül: 30 coin." |
| Kişisel öneri | "Loved *Midnight Heir*? *The CEO's Secret Bride* starts free — first episodes on us." | "*Gece Varisi*'ni sevdiysen: *CEO'nun Gizli Gelini* seni bekliyor — ilk bölümler ücretsiz." |
| Süresi dolan coin | "80 coins in your wallet expire in 48 hours. Use them on your next episode." | "Cüzdanındaki 80 coin 48 saat içinde sona eriyor. Sonraki bölümünde kullan." |

Rich push: yeni bölüm ve kişisel öneri kampanyaları dizi kapak görseli taşır (`mutable-content: 1`, Notification Service Extension görseli indirir; indirme başarısızsa metin-only düşer).

**Kabul kriterleri:**
- [ ] Sistem izin diyaloğu yalnız pre-permission onayından sonra tetiklenir; "Şimdi değil" sistem diyaloğunu tüketmez.
- [ ] APNs token her açılışta ve izin değişiminde backend'e senkronlanır; logout/hesap değişiminde token backend'te eski kullanıcıdan ayrılır.
- [ ] Kategori tercihleri Ayarlar'da değiştirilince tek RTT ile backend'e yazılır; pazarlama kapalıyken pazarlama push'u gelmez (backend testi).
- [ ] Sessiz saat ve frekans tavanı backend'te uygulanır; istemci tarafında ek koruma olarak aynı `campaignId` ile gelen duplicate bildirim gösterilmez.

---

## 6. Deep link entegrasyonu

URL şemasının ve route tablosunun sahibi `02-ekran-haritasi-navigasyon.md`'dir; push payload'ları o şemayı taşır. Buradaki örnek path'ler o dokümandaki tanıma birebir uymak zorundadır.

### 6.1 Push payload sözleşmesi

```json
{
  "aps": { "alert": { "title": "...", "body": "..." }, "sound": "default", "mutable-content": 1 },
  "campaignId": "newep_2026w28_a",
  "campaignType": "new_episode",
  "deeplink": "shortseries://series/srs_123/episode/12?t=0",
  "imageURL": "https://cdn.../cover_srs_123.jpg"
}
```

### 6.2 Kampanya → hedef ekran eşlemesi

| Kampanya | Deep link hedefi | Davranış |
|---|---|---|
| Yeni bölüm | `series/{id}/episode/{n}` | PlayerFeed, ilgili bölümden oynatmaya başlar |
| Kaldığın yerden devam | `series/{id}/episode/{n}?t={sec}` | PlayerFeed, kaldığı saniyeden devam |
| Coin hediyesi | `rewards` | OdulMerkezi (Ödüller sekmesi) |
| Streak hatırlatma | `rewards/checkin` | OdulMerkezi, check-in şeridine scroll + vurgu (`02-ekran-haritasi-navigasyon.md` §8.2) |
| Kişisel öneri | `series/{id}` | DiziDetay |
| Süresi dolan coin | `store/coins` | CoinMagazasi (`02-ekran-haritasi-navigasyon.md` §8.2; `06-monetizasyon.md`) |

### 6.3 İşleme kuralları ve edge case'ler

- **Cold start:** Deep link Splash ön-yüklemesinden sonra, Onboarding tamamlanmışsa doğrudan işlenir; Onboarding tamamlanmamışsa link saklanır, Onboarding sonunda işlenir.
- **Warm/foreground:** Uygulama öndeyken gelen push sistem banner'ı olarak gösterilir (`UNUserNotificationCenterDelegate` → `.banner`); oynatma sırasında ses/oynatma kesilmez. Tıklanırsa route işlenir.
- **Kilitli bölüm hedefi:** Route yine bölüme gider; oynatma girişimi UnlockSheet'i açar. Push, kilidi açılmış gibi gösteremez (§9).
- **Geçersiz/yayından kalkmış içerik:** İlgili dizi bulunamazsa kullanıcı Ana Sayfa'ya (PlayerFeed) düşer, sessiz bir "İçerik artık mevcut değil" toast'ı gösterilir; hata event'i loglanır.
- **Navigasyon durumu:** Route işlenirken mevcut modal'lar (UnlockSheet, BolumListesi sheet'i vb.) kapatılır; Coordinator temiz bir hedef durum kurar (`02-ekran-haritasi-navigasyon.md` route reset kuralları).

### 6.4 Swift iskeleti (ShortSeriesApp)

```swift
// ShortSeriesApp — PushDeepLinkHandler.swift
final class PushDeepLinkHandler: NSObject, UNUserNotificationCenterDelegate {
    private let router: AppRouter          // Coordinator kökü, 02-ekran-haritasi-navigasyon.md
    private let analytics: AnalyticsTracking

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let raw = info["deeplink"] as? String,
              let route = AppRoute(deepLink: raw) else { return }
        analytics.track(.pushOpened(campaignId: info["campaignId"] as? String ?? "unknown",
                                    campaignType: info["campaignType"] as? String ?? "unknown"))
        await router.handle(route)         // pending ise Onboarding sonrası işler
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions { [.banner, .badge] } // ses yok: oynatmayı bozmaz
}
```

**Kabul kriterleri:**
- [ ] §6.2'deki altı hedefin tümü cold start ve foreground senaryolarında doğru ekrana ulaşır (UI test matrisi).
- [ ] Geçersiz link crash üretmez; PlayerFeed'e düşer ve `deeplink_failed` event'i atılır.
- [ ] `push_opened` event'i her açılışta `campaignId` ile atılır (kampanya ROI ölçümü, `08-analitik-deney.md`).

---

## 7. Winback / churn önleme

### 7.1 Segmentler ve tetikleyiciler

Churn riski backend'te inaktivite + davranış sinyalinden hesaplanır (basit kural tabanlı başlangıç, model Faz 3):

| Segment | Tanım (varsayılan, remote config) | Müdahale |
|---|---|---|
| Soğuyan | 3–7 gün inaktif, yarım dizisi var | "Kaldığın yerden devam" push (§5.2) |
| Churn adayı | 7–14 gün inaktif | **Dönüşe özel coin hediyesi**: push + dönüşte otomatik cüzdana yüklenen bonus (ör. 50 earned coin, 7 gün geçerli). Coin push tıklanınca değil, uygulama açılınca yüklenir ve OdulMerkezi'nde/toast'ta gösterilir. |
| Churned | 14+ gün inaktif | Haftada en fazla 1 kişisel öneri push'u; 30 günde yanıt yoksa pazarlama push'u tamamen durur (spam zararı, §9). |
| Coin'i yanacak | Earned coin partisinin son kullanma tarihi ≤ 48 saat | **Süresi dolan earned coin bildirimi** (işlemsel, §5.2). Amaç dürüst bilgilendirmedir; metin yalnız gerçek son kullanma tarihi olan coin'ler için gönderilir. |
| Eski VIP | VIP aboneliği sona ermiş / iptal etmiş, 7+ gün geçmiş | **VIP win-back teklifi (Faz 2):** indirimli dönüş fiyatı (StoreKit 2 win-back offer / offer code, `06-monetizasyon.md`); push + VIPAbonelik ekranında banner. |

### 7.2 Kurallar

- Winback coin hediyesi kullanıcı başına en fazla ayda 1; art arda churn-dönüş döngüsüyle coin farm edilmesine karşı backend velocity kontrolü (`05-veri-modeli-api.md` fraud bölümü).
- Winback push'ları global frekans tavanına dahildir (§5.3).
- VIP win-back fiyatlandırması ve StoreKit ayrıntıları `06-monetizasyon.md`'nin sahasıdır; bu doküman yalnız tetikleyici ve mesajlaşma davranışını tanımlar.
- Tüm winback kampanyaları holdout'lu ölçülür: hediye coin gerçekten dönüş sağlıyor mu, yoksa zaten dönecek kullanıcıya mı gidiyor (`08-analitik-deney.md`).

**Kabul kriterleri:**
- [ ] Winback coin'i yalnız uygulama gerçekten açılınca cüzdana işlenir ve kullanıcıya görünür şekilde bildirilir.
- [ ] Süresi dolan coin bildirimi yalnız gerçekten süreli coin partileri için ve parti başına 1 kez gider.
- [ ] 30+ gün yanıtsız kullanıcıya pazarlama push'u kesilir (backend kuralı test edilir).

---

## 8. Live Activities (Faz 3): yeni bölüm geri sayımı

Konsept: Kullanıcının takip ettiği, bölüm-bölüm yayınlanan bir dizide, sonraki bölümün yayınına geri sayım gösteren bir Live Activity (kilit ekranı + Dynamic Island). Yayın anında "Yayında — İzle" durumuna geçer ve deep link ile bölüme açılır.

- **Başlatma:** Yalnız kullanıcı aksiyonuyla (DiziDetay'da "Hatırlat" CTA'sı). Kendiliğinden, izinsiz Live Activity başlatılmaz — ReelShort'un "kalıcı kilit ekranı varlığı" yaklaşımı bilinçli olarak kopyalanmaz (§9).
- **Yaşam döngüsü:** Geri sayım → yayında (push ile ActivityKit update) → kullanıcı izleyince veya 8 saat sonra otomatik sonlanır. Aynı anda en fazla 1 dizi için aktif.
- **Teknik:** ActivityKit + push-based update (APNs `liveactivity` push type); release schedule verisi `05-veri-modeli-api.md`'den. Widget extension `ShortSeriesApp` altında ayrı target.
- Bu özellik Faz 3'tür; Faz 1/2'de yalnız API'nin release schedule alanları hazırlanır.

---

## 9. Etik ve politika sınırları

Retention mekanikleri kısa vadede metrik şişirip uzun vadede güveni ve retention'ın kendisini yok edebilir. Aşağıdakiler tasarım kısıtıdır, öneri değildir:

**Karanlık kalıplardan kaçınma ilkeleri:**
1. **Kesintisizlik önceliği:** Hiçbir gamification yüzeyi oynatmayı duraklatamaz, video üstüne otomatik modal açamaz (bkz. §3.4). Kuzey yıldızı 1 > gamification.
2. **Dürüst metin:** Push metinleri içerikte olmayan olay ima edemez; "coin hediyesi" gerçekten cüzdana giren coin olmadan gönderilemez; sahte aciliyet ("son şans!" — gerçek bir süre yokken) yasaktır.
3. **Sessiz yakma yok:** Süresi dolacak earned coin ve claim edilmemiş görev ödülleri, dolmadan önce görünür şekilde bildirilir (§4.2, §7).
4. **İzin manipülasyonu yok:** Pre-permission ekranı değer anlatır; sistem diyaloğu ödül vaadiyle süslenmez. `enableNotifications` görevi OdulMerkezi'nde şeffaf bir görevdir, izin ekranına iliştirilmez.
5. **Kilidi saklamak yok:** Kilitli bölümler her yüzeyde kilit ikonu + coin fiyatıyla önceden görünür (BolumListesi, Devam Et, deep link davranışı).
6. **Streak suçlaması yok:** Streak sıfırlanması kayıp/utanç diliyle sunulmaz; koruma jetonu (Faz 2) satın alınabilir bir ürün değildir, otomatik haktır.
7. **Çıkış serbest:** Bildirim kategorileri tek dokunuşla kapatılabilir; kapatan kullanıcıya "emin misin?" zinciri kurulmaz.

**App Store politikası:**
- **Guideline 4.5.4:** Push bildirimleri uygulamanın çalışması için zorunlu tutulamaz; reklam/promosyon/pazarlama amaçlı push yalnız kullanıcının açık izniyle (opt-in) gönderilebilir ve uygulama içinden kapatma yolu sunulmalıdır. Bizim uygulamamız: pazarlama kategorisi Ayarlar'da ayrı anahtardır ve varsayılan davranış + metinler App Store incelemesine dayanacak şekilde tasarlanır.
- ATT istemi bildirim izninden ayrı ele alınır (Onboarding, kanon sırası); ikisi aynı ekrana sıkıştırılmaz.

**Bildirim spam'inin retention'a zararı:** Aşırı push, iOS'ta kullanıcının bildirimleri tamamen kapatması veya uygulamayı silmesiyle sonuçlanır — kanal kalıcı kaybedilir. Frekans tavanları (§5.3) ve 30 gün yanıtsızlıkta pazarlama kesme kuralı (§7) bu yüzden guardrail'dir; "daha çok push = daha çok dönüş" hipotezi ancak tavanlar içinde A/B ile test edilir. Push opt-out oranı ve bildirim kaynaklı uninstall proxy'leri `08-analitik-deney.md`'de izlenen sağlık metrikleridir.

---

## 10. Analitik bağlantısı (özet)

Event şemasının sahibi `08-analitik-deney.md`'dir; bu dokümandaki mekaniklerin ürettiği asgari event seti:

| Event | Kaynak | Kritik parametreler |
|---|---|---|
| `checkin_completed` | CheckInStore | cycleDay, streakCount, coins |
| `streak_broken` | backend → istemci senkronu | previousStreak |
| `mission_completed` / `mission_claimed` | MissionStore | missionId, type, reward |
| `push_permission_prompted` / `granted` / `denied` | Onboarding, bağlamsal istekler | surface (onboarding/contextual) |
| `push_opened` | PushDeepLinkHandler | campaignId, campaignType |
| `deeplink_failed` | AppRouter | rawLink, reason |
| `continue_watching_tapped` | PlayerFeed/Listem/DiziDetay | surface, seriesId |
| `winback_gift_granted` | backend + istemci gösterimi | coins, expiresAt |

Faz 1 lansman deney adayları: check-in ödül eğrisi (düz vs artan), PlayerFeed çipi (var/yok), devam-et push gecikmesi (24s vs 48s), pre-permission metni. Tümü `08-analitik-deney.md` altyapısıyla, D7 birincil metrikle koşar.
