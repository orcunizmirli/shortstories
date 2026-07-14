# PlayerKit — Dikey Video Player Engine Tasarımı

**Amaç:** Bu doküman, ShortSeries iOS istemcisinin kalbi olan `PlayerKit` modülünün — dikey tam ekran video feed'i, AVPlayer havuzu, prefetch/cache katmanı ve oynatma UI'ının — eksiksiz teknik spesifikasyonudur. Kuzey yıldızımızın birinci maddesi "akıcı, kesintisiz izleme deneyimi" olduğundan, buradaki her karar ölçülebilir performans bütçelerine bağlanmıştır; doküman geliştirme ekibinin doğrudan implementasyona çevireceği davranış tanımları, edge case'ler, Swift kod iskeletleri ve kabul kriterlerini içerir.

**İlgili dokümanlar:** 03-mimari.md (genel mimari, MVVM + Coordinator, DI), 01-ozellik-envanteri.md (özellik fazları), 02-ekran-haritasi-navigasyon.md (PlayerFeed, BolumListesi, UnlockSheet akışları), 05-veri-modeli-api.md (Episode modeli, imzalı URL, progress API), 06-monetizasyon.md (kilitli bölüm ekonomisi, UnlockSheet), 07-retention-gamification.md (binge döngüsü, devam et), 08-analitik-deney.md (event şeması, A/B), 09-yol-haritasi-tasklar.md (faz planı), 10-arastirma-raporu.md (kaynaklı araştırma bulguları).

---

## 1. Tasarım hedefleri ve performans bütçeleri

`PlayerKit`'in tek görevi vardır: kullanıcı parmağını kaydırdığı anda sonraki bölümün oynuyor olması. Aşağıdaki bütçeler kanoniktir (bkz. 03-mimari.md) ve her PR bu bütçelere karşı ölçülür; bütçeyi aşan değişiklik merge edilmez.

| Metrik | Bütçe | Ölçüm yöntemi |
|---|---|---|
| Time-to-first-frame (TTFF) | **< 500 ms** (soğuk başlangıç dahil) | `AVPlayerItemAccessLog.startupTime` + kendi işaretleyicimiz (§13) |
| Swipe-to-next oynatma | **< 100 ms** (kaydırma yerleşince ilk kare) | Swipe-settle → `rate > 0 && ilk kare` arası süre (§13) |
| Kaydırma akıcılığı | **60 fps**, dropped frame < %1 | MetricKit hang/hitch + CADisplayLink örnekleme |
| Stall (rebuffering) | Oturum başına ort. **< 0.2 stall**; stall süresi / izleme süresi **< %0.5** (bu dokümanla tanımlanan mühendislik hedefi) | `AVPlayerItemPlaybackStalled` + access log (§13) |
| Player havuzu | **3–5 AVPlayer** instance, asla daha fazla | `PlayerPool` assert + debug HUD |
| Sonraki bölüm prefetch | **~500 KB veya ilk 2 sn** (hangisi önce) | `PrefetchController` sayaçları |
| Buffer | Aktif player `preferredForwardBufferDuration = 0` (otomatik); idle player = **1 sn** | Kod incelemesi + ağ trafiği testi |
| Disk video cache | **~200 MB LRU** | Cache katmanı metriği |
| Hücresel veri tasarrufu | **480p tavan + prefetch durdur** | Ayar bayrağı davranış testi |

TTFF < 500 ms ve 2–6 sn HLS segment + 300 kbps–2.5 Mbps portrait merdiveni hedefleri sektör mühendislik kaynağıyla uyumludur (https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack). Player havuzu (3–5), ~500 KB / 2 sn prefetch ve ~200 MB LRU cache bütçeleri TikTok-tarzı feed sistem tasarımı kaynaklarından gelir (https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/, https://www.mux.com/blog/building-tiktok-smooth-scrolling-on-ios).

**Kabul kriterleri (bölüm 1):**
- iPhone 12 / iOS 17, orta kalite LTE simülasyonunda (2 Mbps, 100 ms RTT): TTFF p90 < 500 ms, swipe-to-next p90 < 100 ms.
- 30 bölümlük kesintisiz binge testinde bellek < 350 MB, havuz boyutu hiç 5'i aşmaz, stall oranı < %0.5.

---

## 2. Genel mimari

### 2.1 Neden UIKit feed + SwiftUI kabuk?

Uygulama kabuğu SwiftUI'dir (tab bar, sheet'ler, ayarlar); ancak **player feed UIKit'tir**: `UICollectionView` (dikey paging, tam ekran hücreler) + AVPlayer havuzu. Gerekçe kanoniktir: 60 fps kaydırma + player pooling için savaşta test edilmiş kalıp budur (Mux/TikTok kalıbı — https://www.mux.com/blog/building-tiktok-smooth-scrolling-on-ios). SwiftUI `ScrollView`/`TabView` tabanlı feed'ler hücre yeniden kullanımı, prefetch API'ı (`UICollectionViewDataSourcePrefetching`) ve kaydırma fizik kontrolü konusunda bu kalıbın gerisindedir.

### 2.2 Bileşen haritası

```
ShortSeriesApp (SwiftUI, Ana Sayfa sekmesi)
   └─ PlayerFeedView (UIViewControllerRepresentable)          ← SwiftUI köprüsü
        └─ PlayerFeedViewController (UIKit)                    ← PlayerKit
             ├─ UICollectionView (dikey paging, tam ekran hücre)
             │    └─ EpisodeCell (AVPlayerLayer + overlay UI)
             ├─ PlayerPool (actor, 3–5 AVPlayer)               ← oynatıcı yaşam döngüsü
             ├─ PrefetchController                             ← sonraki bölüm ön-yükleme
             ├─ PlaybackProgressTracker                        ← periodic time observer → event
             ├─ AudioSessionCoordinator                        ← AVAudioSession + kesintiler
             └─ PlayerMetricsCollector                         ← TTFF/stall/swipe → AnalyticsKit
```

- Veri: `ContentKit` feed API istemcisi bölüm listesini (Episode modelleri + imzalı HLS URL'leri) sağlar (bkz. 05-veri-modeli-api.md).
- Kilit durumu: bölümün erişim sözleşmesi `Episode.access` alanıdır (`access.kind == .locked` + `access.unlockPrice`, bkz. 05-veri-modeli-api.md §2.2); entitlement, R8 protokolü `EntitlementChecking` üzerinden çözülür — protokol AppFoundation'da tanımlıdır, canlı uygulama `WalletKit`'tedir (§9, bkz. 03-mimari.md §4, 06-monetizasyon.md).
- Navigasyon: `PlayerFeedViewController` hiçbir ekran açmaz; tüm geçişler (DiziDetay, BolumListesi, UnlockSheet) Coordinator'a delegate/closure ile bildirilir (bkz. 03-mimari.md).

### 2.3 SwiftUI köprüsü

```swift
public struct PlayerFeedView: UIViewControllerRepresentable {
    let viewModel: PlayerFeedViewModel   // @Observable, ContentKit feed'ini sarar
    let playerPool: PlayerPool           // kompozisyon kökünde (ShortSeriesApp) kurulur,
    let prefetch: PrefetchController     // init-injection ile gelir — Dependencies'e KONMAZ (§2.4)

    public func makeUIViewController(context: Context) -> PlayerFeedViewController {
        PlayerFeedViewController(
            viewModel: viewModel,
            playerPool: playerPool,
            prefetch: prefetch
        )
    }

    public func updateUIViewController(_ vc: PlayerFeedViewController, context: Context) {
        vc.apply(state: viewModel.feedState)   // diff'li uygulama; reloadData YASAK (§14)
    }
}
```

`UICollectionView` yapılandırması: `isPagingEnabled = true`, hücre boyutu = ekran boyutu (safe area dahil tam ekran, overlay'ler safe area'ya hizalı), `contentInsetAdjustmentBehavior = .never`, `prefetchDataSource` aktif. Sekme Ana Sayfa'dır ve uygulama Splash sonrası **doğrudan video ile açılır** — Splash, ilk feed sayfasını ve ilk bölümün player'ını arka planda hazırlar ki ilk kare TTFF bütçesine sığsın (bkz. 02-ekran-haritasi-navigasyon.md).

### 2.4 PlayerKit dış yüzeyi (modül sınırı)

`PlayerKit`'in public API'ı **kapalı bir listedir**; bu listenin dışına public tip açmak modül sınırı değişikliğidir ve mimari karar kaydı gerektirir (bkz. 03-mimari.md):

| Public tip | Rol |
|---|---|
| `PlayerFeedView` | SwiftUI köprüsü — feed'in tek giriş noktası (§2.3) |
| `PlayerFeedViewController` | Yalnız köprünün gerektirdiği asgari yüzey: `init(viewModel:playerPool:prefetch:)` + `apply(state:)` |
| `PlayerFeedViewModel` (+ `FeedState` value tipi) | Feed durumu; `ContentKit` modellerini sarar |
| `PlayerFeedDelegate` | Ray aksiyonları ve `lockedEpisodeReached` dahil tüm navigasyon niyetlerinin Coordinator'a aktığı protokol (§2.2, §8.4, §9) |
| `PlayerPool` | Yalnız kompozisyon kökünün gördüğü `public init`; operasyonlar (`activate`/`prepareNext`/`recycle`/`acquire`/`Lease`/`advanceWindow`/`drain`) internal'dır — feed VC aynı modülde yaşar (§3.3) |
| `PrefetchController` | Yalnız `public init`; pencere yönetimi internal'dır (§5.4) |
| `PlaybackControlling` + `PlaybackHandle` | Aktif oynatmanın kontrol sözleşmesi ve havuz aktivasyonunun döndürdüğü value-tipi tutamaç; imzalarda yalnız value tipleri + `AsyncStream` (kural 1) |
| `PlayerEngineState` | Motorun dışa görünen durum enum'u; `PlaybackControlling.statusUpdates()` akışının value tipi |
| `NetworkCondition` + `NetworkConditionProviding` | Ağ koşulu anlık görüntüsü ve portu (§5.3); canlısı NWPathMonitor sarmalayıcısıdır (SS-026) |
| `PlaybackPreferencesProviding` | Oynatma tercihleri portu (veri tasarrufu — §5.3); canlısı Ayarlar/ProfileKit tarafından beslenir |
| `EntitlementChecking` | PlayerKit'te tanımlı DEĞİLDİR — R8 portunun evi `AppFoundation`'dır (03 §4 R8, `SharedTypes/`); PlayerKit yalnız tüketir (§9.1) |

`EpisodeCacheStore`, `PlayerAssetFactory`, `AudioSessionCoordinator`, `PlaybackProgressTracker`, `PlayerMetricsCollector` internal'dır; dış dünyadan yalnız protokol bağımlılıkları enjekte edilir (ör. `AssetCacheIndexing`, §7.2).

Kurallar:

1. **AVFoundation tipleri (`AVPlayer`, `AVPlayerItem`, `AVPlayerLayer`, `AVAudioSession`...) PlayerKit-internal'dır** ve public API imzalarında (parametre, dönüş tipi, public property) görünemez. AVFoundation seçimi implementasyon kararıdır; player teknolojisi değişikliğinin etki alanı PlayerKit (+ kompozisyon için ShortSeriesApp) ile sınırlı kalır (bkz. KANON.md §2).
2. `playerPool`/`prefetchController` AppFoundation `Dependencies` konteynerine **konmaz**; kompozisyon kökünde (ShortSeriesApp) kurulur ve `PlayerFeedView`'a init-injection ile verilir (§2.3; bkz. 03-mimari.md §5.1).
3. Kural CI bağımlılık lint'ine bağlıdır: (a) PlayerKit dışındaki modüllerde `import AVFoundation` / `import AVKit` build'i kırar; (b) PlayerKit'in public interface dökümünde AVFoundation tipi geçen imza build'i kırar. Bu lint **F1 (PlayerKit iskeleti) başlamadan** devrededir (bkz. 09-yol-haritasi-tasklar.md).

---

## 3. PlayerPool tasarımı

### 3.1 Neden havuz?

Her hücre için yeni `AVPlayer` yaratmak iki bütçeyi birden patlatır: instance yaratma + ilk `replaceCurrentItem` maliyeti onlarca milisaniyedir ve swipe anında yapılırsa < 100 ms hedefi tutmaz (https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/). Çözüm: uygulama açılışında **3–5 AVPlayer** yaratıp yeniden kullanmak. Player'lar hücrelere değil, **feed indeksine** bağlanır; hücreler yeniden kullanılırken player'lar havuzda yaşar.

### 3.2 İndex-etrafı pencere

Havuz her an aktif indeksin etrafındaki pencereyi hazır tutar:

| Slot | İçerik | Durum |
|---|---|---|
| `index - 1` | Önceki bölüm | Item yüklü, paused, buffer 1 sn (geri kaydırma anında hazır) |
| `index` | Aktif bölüm | Oynuyor, buffer otomatik |
| `index + 1` | Sonraki bölüm | Item yüklü, paused, buffer 1 sn, prefetch tamam |
| (4.–5. slot) | Kaydırma yönünde `index + 2` (veya hız yüksekse `index - 2`) | Item yüklü, paused |

Minimum konfigürasyon 3 slot (önceki/aktif/sonraki); 4.–5. slot, hızlı ardışık swipe'larda pencerenin kaydırma yönünde bir adım önde gitmesi içindir. Havuz boyutu remote config ile 3–5 arasında ayarlanabilir (düşük RAM'li cihazlarda 3'e düşürme — `ProcessInfo.physicalMemory` eşiği).

### 3.3 Yaşam döngüsü: acquire / release / reuse

`PlayerPool` kanonik olarak **actor**'dür (bkz. 03-mimari.md): tüm slot mutasyonları serileşir, veri yarışı derleyici tarafından engellenir.

```swift
public actor PlayerPool {
    /// PlayerKit-internal: AVPlayer modül dışına sızmaz (§2.4). Havuzun public
    /// yüzeyi yalnız kompozisyon kökünün gördüğü init'tir.
    struct Lease: Sendable {
        let player: AVPlayer
        let episodeID: Episode.ID
        let slot: Int
    }

    private struct Slot {
        let player: AVPlayer
        var episodeID: Episode.ID?
        var role: Role
        enum Role { case active, warm, idle }
    }

    private var slots: [Slot]
    private let assetFactory: PlayerAssetFactory   // imzalı URL → AVURLAsset (async yükleme)

    public init(size: Int = 3, assetFactory: PlayerAssetFactory) {
        precondition((3...5).contains(size), "Havuz bütçesi 3–5 (kanon)")
        self.assetFactory = assetFactory
        self.slots = (0..<size).map { _ in
            let p = AVPlayer()
            p.automaticallyWaitsToMinimizeStalling = true
            p.actionAtItemEnd = .pause          // auto-next'i biz yönetiyoruz (§8.6)
            return Slot(player: p, episodeID: nil, role: .idle)
        }
    }

    /// Bölüm için player kirala. Bölüm zaten bir slot'ta hazırsa (prefetch/warm)
    /// aynı player'ı döndürür — cold start yok. (internal — §2.4)
    func acquire(for episode: Episode, role: Slot.Role = .warm) async throws -> Lease {
        if let i = slots.firstIndex(where: { $0.episodeID == episode.id }) {
            slots[i].role = role
            return Lease(player: slots[i].player, episodeID: episode.id, slot: i)
        }
        let i = try reclaimableSlotIndex()               // en uzak idle slot'u geri al
        let slot = slots[i]
        slot.player.pause()
        // Asset yüklemesi actor DIŞINDA, arka planda: main thread ve actor bloke edilmez.
        let item = try await assetFactory.makeItem(for: episode)   // §4 buffer ayarlarıyla
        slot.player.replaceCurrentItem(with: item)
        slots[i].episodeID = episode.id
        slots[i].role = role
        return Lease(player: slot.player, episodeID: episode.id, slot: i)
    }

    /// Aktif bölüm değişti: pencereyi kaydır, rolleri güncelle, tavana kaydet.
    func advanceWindow(activeEpisodeID: Episode.ID, direction: ScrollDirection) { ... }

    /// Feed'den çıkışta / bellek uyarısında: item'ları bırak, player'ları KORU.
    func drain(keepPlayers: Bool = true) {
        for i in slots.indices {
            slots[i].player.replaceCurrentItem(with: nil)   // item gider, player kalır
            slots[i].episodeID = nil
            slots[i].role = .idle
        }
    }
}
```

Kurallar:

1. **Player asla deallocate edilmez** (feed yaşadığı sürece). `replaceCurrentItem(with: nil)` ile item bırakılır; instance yeniden kullanılır.
2. **`AVPlayerItem` asla iki player arasında paylaşılmaz** — bir item tek bir player'a bağlanabilir; yeniden kullanım gereken her durumda aynı asset'ten yeni item yaratılır (§14, tuzak T1).
3. `reclaimableSlotIndex()` aktif indekse **en uzak** slot'u seçer (LRU-benzeri); aktif slot asla geri alınmaz.
4. Hücre `prepareForReuse`'da yalnızca `AVPlayerLayer.player = nil` yapar; havuz slot'una dokunmaz. Layer bağlama, hücre `willDisplay`'de lease üzerinden yapılır.
5. Bellek uyarısında (`didReceiveMemoryWarning`): pencere dışı slot'lar boşaltılır, havuz 3'e küçülür.

**Kabul kriterleri (bölüm 3):**
- 100 ardışık swipe boyunca yaratılan toplam `AVPlayer` sayısı ≤ havuz boyutu (Instruments Allocations ile doğrulanır).
- Geri kaydırmada (index-1) oynatma < 100 ms'de başlar (item zaten yüklü).
- Feed arka plana alınıp geri gelindiğinde aynı player instance'ları kullanılır; yeni allocation olmaz.

---

## 4. Buffer politikası

### 4.1 Aktif ve idle player ayrımı

Havuzdaki paused player'lar serbest bırakılırsa AVFoundation varsayılan olarak agresif buffer doldurur ve ağ bandını aktif player'dan çalar — hem stall riski hem hücresel veri maliyeti. Politika:

| Player rolü | `preferredForwardBufferDuration` | `automaticallyWaitsToMinimizeStalling` | Davranış |
|---|---|---|---|
| **Aktif** (oynayan) | `0` (= AVFoundation otomatik yönetir) | `true` | Sistem, ağa göre ideal ileri buffer'ı kendisi seçer |
| **Warm/idle** (havuzda paused) | `1.0` sn | `true` | En fazla ~1 sn ileri veri tutar; bandı işgal etmez |

Bu ayrımın ölçülmüş etkisi kaynaklıdır: çoklu-video feed'inde paused item'lara `preferredForwardBufferDuration = 1` verilmesi, ekran dışı videoların ağ yükünü **37.8 MB'dan 0.2 MB'a** düşürmüştür (https://medium.com/@sojik/avplayer-video-optimization-part-1-2a45ea002ea2). API referansı: https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration

Bölüm aktif hale gelince item'ın buffer ayarı yerinde güncellenir (yeni item yaratmaya gerek yok):

```swift
func promoteToActive(_ lease: PlayerPool.Lease) {
    lease.player.currentItem?.preferredForwardBufferDuration = 0   // otomatik moda geç
    lease.player.playImmediately(atRate: playbackRate)             // buffer dolmasını bekleme
}

func demoteToIdle(_ lease: PlayerPool.Lease) {
    lease.player.pause()
    lease.player.currentItem?.preferredForwardBufferDuration = 1.0
}
```

### 4.2 `automaticallyWaitsToMinimizeStalling` kararı

- Tüm player'larda **`true` (varsayılan) bırakılır.** HLS'de bu bayrağı `false` yapmak progressive içerikteki gibi davranmaz ve erken `play()` çağrılarında anında stall üretebilir.
- Swipe anında beklemeden başlatma ihtiyacı `playImmediately(atRate:)` ile çözülür: bu çağrı, waiting davranışını o oynatma için devre dışı bırakıp eldeki veriyle ilk kareyi basar — < 100 ms hedefinin anahtarı budur.
- Araştırma kaynağındaki `false` + düşük buffer kombinasyonu (Mingalev) progressive MP4 feed'leri için ölçülmüştür; bizim HLS hattımızda birebir uygulanmaz, yalnızca idle buffer sınırı (1 sn) devralınır.
- `canUseNetworkResourcesForLiveStreamingWhilePaused` `false` bırakılır; paused item'ların ağ kullanımı QA'de ağ trafiği kaydıyla doğrulanır (kaynak, bayrağın VOD'da da etkili olabildiğini ama test edilmesi gerektiğini not eder).

**Kabul kriterleri (bölüm 4):**
- Charles/Instruments ağ kaydında: aktif bölüm oynarken idle slot'ların toplam indirmesi, item başına ~1 sn'lik segment hacmini aşmaz.
- `playImmediately(atRate:)` sonrası ilk kare gecikmesi, prefetch tamamlanmış bölümde p90 < 100 ms.

---

## 5. Prefetch politikası — PrefetchController

### 5.1 Bütçe ve tetikleyiciler

- **Bütçe:** sonraki bölüm için **~500 KB veya ilk 2 sn** — hangisi önce dolarsa (kanon; kaynak: https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/). HLS'de bu pratikte master playlist + ilk media playlist + ilk 1–2 segmentin indirilmesi demektir (2–6 sn segmentlerle ilk segment çoğu zaman 2 sn'yi tek başına karşılar).
- **Tetik 1 — aktif bölüm başladı:** aktif bölümün ilk karesi geldikten ve ilk ~2 sn'lik buffer oturduktan sonra `index + 1` prefetch'i başlar. Aktif oynatmadan önce prefetch başlatmak TTFF'i riske atar; sıralama katıdır: önce aktif, sonra komşular.
- **Tetik 2 — `UICollectionViewDataSourcePrefetching`:** collection view'ın `prefetchItemsAt` çağrısı, pencere dışına taşan indeksler için yalnızca **metadata + imzalı URL** ısındırır (manifest indirme yok); gerçek segment prefetch'i pencere yönetimindedir.
- **İptal:** kullanıcı bölümü atlarsa (swipe ile geçti) bekleyen prefetch task'ları iptal edilir (`URLSession` task cancel + `AVAssetDownloadTask` cancel); bant genişliği yeni pencereye verilir.

### 5.2 Kaydırma yönü farkındalığı

`PrefetchController`, `UIScrollViewDelegate` üzerinden yön ve hız sinyali alır:

- **Aşağı kaydırıyor (sonraki bölüm):** öncelik `index + 1`, sonra `index + 2` (havuz 4–5 slotluysa). `index - 1` yalnızca item olarak tutulur, yeni segment indirilmez.
- **Yukarı kaydırıyor (önceki bölüm):** öncelik tersine döner; `index - 1` ve `index - 2` ısındırılır.
- **Hızlı flick serisi:** iki swipe arası < 300 ms ise ara indekslerin prefetch'i atlanır; yalnızca hedef indeks + yönündeki komşu ısındırılır (bant israfını önler).

Yön farkındalıklı prefetch, Mux'un TikTok feed kalıbının parçasıdır (https://www.mux.com/blog/building-tiktok-smooth-scrolling-on-ios).

### 5.3 Hücresel / veri tasarrufu davranışı

| Koşul | Davranış |
|---|---|
| Wi-Fi | Tam prefetch (pencere + bütçe) |
| Hücresel (normal) | Prefetch açık; `preferredPeakBitRateForExpensiveNetwork` ile 720p tavanı (remote config) |
| **Hücresel + veri tasarrufu modu** (Ayarlar → oynatma tercihleri) | **480p tavan + prefetch tamamen durdurulur** (kanon); yalnızca aktif bölüm buffer'lanır |
| iOS Low Data Mode (`allowsExpensiveNetworkAccess`) | Veri tasarrufu modundaki davranışa otomatik düşülür |

Veri tasarrufu modunda kullanıcı deneyimi bilinçli olarak "swipe'ta kısa spinner görebilir" seviyesine iner; bu, veri maliyeti tercihinin doğal sonucudur ve onboarding'de değil Ayarlar'da yaşar (bkz. 02-ekran-haritasi-navigasyon.md).

### 5.4 Kod iskeleti

```swift
public final class PrefetchController {
    enum Priority { case next, previous, extended }

    private let pool: PlayerPool
    private let network: NetworkConditionMonitor   // AppFoundation: NWPathMonitor sarmalayıcı
    private var tasks: [Episode.ID: Task<Void, Never>] = [:]

    func windowChanged(active: Int, episodes: [Episode], direction: ScrollDirection) {
        guard network.prefetchAllowed else { cancelAll(); return }   // veri tasarrufu: dur
        let targets = prefetchTargets(active: active, direction: direction, in: episodes)
        cancelTasks(notIn: targets.map(\.id))
        for episode in targets where tasks[episode.id] == nil && !episode.isLockedForCurrentUser {
            tasks[episode.id] = Task(priority: .utility) { [pool] in
                _ = try? await pool.acquire(for: episode, role: .warm)  // item yüklü + 1sn buffer
            }
        }
    }
}
```

**Kabul kriterleri (bölüm 5):**
- Prefetch tamamlanmış sonraki bölüme swipe: p90 < 100 ms'de oynatma.
- Veri tasarrufu modunda ağ kaydında aktif bölüm dışında sıfır video isteği.
- Kilitli bölüm (entitlement yok) prefetch edilmez (§9).

---

## 6. HLS yapılandırması

### 6.1 Format kararı

Kanonik format **HLS**'dir (CDN üzerinden), **2–6 sn segment**, H.264 + HEVC varyantları. Kısa bölümlerde (1–3 dk) kısa segmentler (2 sn'ye yakın) TTFF'i düşürür; encoding hattıyla segment süresi 2–4 sn bandında kalibre edilir. FairPlay DRM Faz 2'dir; Faz 1'de erişim kontrolü imzalı URL iledir (bkz. 05-veri-modeli-api.md).

### 6.2 Portrait bitrate merdiveni

Kanonik merdiven 240p→1080p, ~300 kbps→2.5 Mbps'dir. Temsili rung tablosu (kesin değerler AI üretim hattının encoding çıktısıyla birlikte kalibre edilir; istemci merdiveni manifest'ten okur, hard-code etmez):

| Rung | Çözünürlük (portrait) | Hedef bitrate | Codec |
|---|---|---|---|
| 1 | 240p (416×240 dikey eşdeğeri) | ~300 kbps | H.264 |
| 2 | 360p | ~550 kbps | H.264 |
| 3 | 480p | ~800 kbps | H.264 / HEVC |
| 4 | 720p | ~1.4 Mbps | H.264 / HEVC |
| 5 | 1080p | ~2.5 Mbps | HEVC (H.264 fallback) |

Kaynak (merdiven aralığı + segment süresi): https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack — çok-runglu ladder pratiği ayrıca https://www.fastpix.io/tutorials/how-to-build-a-micro-drama-video-app-like-reelshort-or-dramabox benzeri mühendislik kaynaklarında standarttır.

### 6.3 `preferredPeakBitRate` kullanımı

```swift
func applyBitratePolicy(to item: AVPlayerItem, settings: PlaybackSettings, network: NetworkCondition) {
    if settings.dataSaverEnabled {
        item.preferredPeakBitRate = 800_000            // 480p rung tavanı (kanon)
    } else if network.isCellular {
        item.preferredPeakBitRateForExpensiveNetwork = 1_400_000   // 720p tavanı (remote config)
    } else {
        item.preferredPeakBitRate = 0                  // sınırsız; ABR karar versin
    }
}
```

- İlk açılışta (Splash → ilk bölüm) `preferredPeakBitRate` geçici olarak orta rung'a (≈800 kbps) sabitlenip ilk kare geldikten ~2 sn sonra serbest bırakılabilir: ABR'nin yüksek rung araması TTFF'i geciktirmesin diye. Bu "start-low, climb-fast" taktiği A/B ile doğrulanır (bkz. 08-analitik-deney.md).
- `preferredPeakBitRateForExpensiveNetwork` görece az kullanılan bir API'dır; davranışı cihaz matrisinde QA edilir (kaynak notu: https://medium.com/@sojik/avplayer-video-optimization-part-1-2a45ea002ea2).

### 6.4 İmzalı URL yenileme

İçerik erişimi imzalı URL iledir (kanon; desen: https://www.fastpix.io/tutorials/how-to-build-a-micro-drama-video-app-like-reelshort-or-dramabox). Kurallar:

1. `ContentKit`, her bölüm için `playbackURL` + `expiresAt` döner (bkz. 05-veri-modeli-api.md).
2. `PlayerAssetFactory`, item yaratmadan önce `expiresAt - now < 60 sn` ise URL'yi yeniler (tek uçuşlu, coalesced istek).
3. **Oynatma sırasında süre dolarsa:** CDN 403 döner → `AVPlayerItem.status == .failed` / error log event. Kurtarma akışı: mevcut `currentTime()` kaydedilir → yeni imzalı URL alınır → yeni item yaratılır → `seek(to: savedTime)` → `playImmediately`. Kullanıcıya spinner dışında hiçbir şey gösterilmez; kurtarma p90 < 1.5 sn hedeflenir.
4. Prefetch edilmiş ama henüz oynatılmamış item'ların URL'si pencere her kaydığında tazelik kontrolünden geçer.
5. Aynı 403-kurtarma yolu, CDN kaynaklı geçici hatalar için de kullanılır (1 otomatik deneme; ikinci hatada hücre içi hata durumu + "Tekrar dene").

**Kabul kriterleri (bölüm 6):**
- Süresi dolmuş URL senaryosunda (mock CDN) oynatma, kullanıcı aksiyonu olmadan kaldığı kareden < 1.5 sn'de devam eder.
- Veri tasarrufu modunda access log'daki `indicatedBitrate` hiçbir örnekte 480p rung'ını aşmaz.

---

## 7. Cache stratejisi

### 7.1 Neden basit URL interception HLS'de çalışmaz

Progressive MP4'te yaygın kalıp — `AVAssetResourceLoaderDelegate` ile özel scheme üzerinden byte-range isteklerini yakalayıp diske yazmak (CachingPlayerItem deseni) — **HLS'de çalışmaz**: AVFoundation, HLS playlist'ini resource loader'a verdiğinizde içindeki segment isteklerini delegate'e düşürmez; segmentler AVFoundation'ın kendi media stack'i tarafından indirilir ve araya girilemez. HLS'de Apple'ın desteklediği yol `AVAssetDownloadTask`'tir. Bu ayrım birincil kaynaklıdır: https://developer.apple.com/forums/thread/649810

Ek pratik sorunlar: playlist'i yeniden yazıp segment URL'lerini özel scheme'e çevirmek (a) imzalı URL parametrelerini bozar, (b) ABR rung geçişlerini üstlenmenizi gerektirir, (c) her iOS sürümünde kırılgandır. Bu yol **yasaktır**.

### 7.2 Seçilen yol: `AVAssetDownloadTask` + ~200 MB LRU

- **Ön-indirme (Faz 1 kapsamı):** `AVAssetDownloadURLSession` + `AVAssetDownloadTask` ile bölümün tek bir rung'ı (480p, `AVAssetDownloadTaskMinimumRequiredMediaBitrateKey` ile seçilir) diske indirilir. Kullanım alanları: (a) aktif dizinin sonraki 1–2 bölümünü Wi-Fi'da sessizce indirme (binge hızlandırma, remote config bayraklı), (b) tekrar izlenen bölümlerin cache'ten oynaması.
- **Offline / İndirilenler:** Listem sekmesinin İndirilenler segmenti **Faz 3**'tür (bkz. 01-ozellik-envanteri.md); aynı `AVAssetDownloadTask` altyapısını kullanır, bu dokümandaki cache katmanı onun temelini döşer.
- **Disk bütçesi: ~200 MB LRU** (kanon; kaynak: https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/). Cache metadata'sı (episodeID, yerel asset konumu, boyut, lastAccessAt) AppFoundation'da tanımlı `AssetCacheIndexing` protokolü üzerinden kalıcılaştırılır — kayıt tipi `CachedAssetRecordEntity` (bkz. 05-veri-modeli-api.md), kalıcılık katmanı AppFoundation'daki SwiftData'dır (bkz. 03-mimari.md); **PlayerKit SwiftData import etmez** (CI lint, §2.4 ile aynı mekanizma). Eviction, toplam boyut 200 MB'ı aşınca `lastAccessAt` en eski kayıttan başlar. İzlenmiş (tamamlanmış) bölümler eviction'da önceliklidir.
- Oynatmada karar: `CacheStore.localAsset(for: episodeID)` varsa `PlayerAssetFactory` yerel asset'ten item yaratır (TTFF pratikte ~anlık); yoksa ağdan imzalı URL ile oynatır. Yerel asset'in imza süresiyle işi yoktur; kilit kontrolü her durumda entitlement üzerinden yapılır (§9).

```swift
final class EpisodeCacheStore {
    private let session: AVAssetDownloadURLSession
    private let cacheIndex: any AssetCacheIndexing   // AppFoundation protokolü — PlayerKit SwiftData import etmez
    private let budgetBytes: Int64 = 200 * 1024 * 1024   // ~200 MB LRU (kanon)

    init(session: AVAssetDownloadURLSession, cacheIndex: any AssetCacheIndexing) {
        self.session = session
        self.cacheIndex = cacheIndex
    }

    func preload(_ episode: Episode) {
        guard networkMonitor.isWiFi, !episode.isLockedForCurrentUser else { return }
        let task = session.makeAssetDownloadTask(
            asset: AVURLAsset(url: episode.playbackURL),
            assetTitle: episode.id.rawValue,
            assetArtworkData: nil,
            options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 800_000]  // 480p rung
        )
        task?.resume()
    }
    func evictIfNeeded() { /* cacheIndex LRU sorgusu (lastAccessAt) → FileManager.removeItem + cacheIndex kaydı silinir */ }
}
```

### 7.3 Değerlendirilen alternatif ve neden seçilmedi

**Alternatif:** progressive **MP4 fast-start** (moov atomu dosya başında) + `AVAssetResourceLoaderDelegate` ile tam kontrol edilebilir byte cache. Kısa videolar için savunulan bir yaklaşımdır ve HEVC ile ~%30 bant tasarrufu notuyla birlikte anılır (https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/).

**Neden seçilmedi (kanonik karar HLS):**
1. ABR yok: tek bitrate'lik MP4, 300 kbps–2.5 Mbps yelpazesindeki ağ koşullarına uyum sağlayamaz; ya düşük kaliteye sabitlenir ya stall üretir.
2. FairPlay DRM (Faz 2) HLS gerektirir; MP4 yolu Faz 2'de mimari değişiklik demektir.
3. CDN ve AI üretim hattı çıktısı HLS merdivenine göre kurgulanmıştır; çift format çift maliyettir.
4. Kısa segmentli HLS + doğru prefetch, TTFF hedefini zaten karşılar; MP4'ün tek somut avantajı (basit byte cache) `AVAssetDownloadTask` ile HLS'de de elde edilir.

Bu alternatif yalnızca "değerlendirilen alternatif" statüsündedir; yeniden açılması mimari karar kaydı gerektirir (bkz. 03-mimari.md).

**Kabul kriterleri (bölüm 7):**
- Cache'lenmiş bölüm uçak modunda baştan sona oynar (Faz 1'de UI'da offline vaadi verilmez; bu teknik doğrulamadır).
- Cache 200 MB'ı 24 saatten uzun süre aşamaz (eviction job'ı uygulama açılışında + indirme tamamlanınca koşar).
- Resource loader tabanlı HLS interception kodu repo'da bulunmaz (lint kuralı / kod incelemesi).

---

## 8. Oynatma UI etkileşimleri

Tüm jestler `EpisodeCell` üzerindeki tek bir `PlayerGestureCoordinator`'da toplanır. Tek tap / çift tap çakışmasında `require(toFail:)` gecikmesi KULLANILMAZ — 250 ms bekleme yapılmaz: tek tap etkisi anında uygulanır; dokunuşun bir çift tap'in ilk yarısı olduğu anlaşılırsa tek tap etkisi geri alınıp çift tap davranışı uygulanır (kanonik tanıma stratejisi; aynı ifade 01-ozellik-envanteri.md PLR-01 ve 02-ekran-haritasi-navigasyon.md §4.3.3'te). Overlay UI, SwiftUI ile hücre içine gömülür (`UIHostingConfiguration`); jest katmanı UIKit'te kalır.

### 8.1 Jest tablosu

| Jest | Davranış | Edge case |
|---|---|---|
| Tek tap | **Play/pause** — anında uygulanır, 250 ms çift-tap beklemesi yoktur | Dokunuşun çift tap'in ilk yarısı olduğu anlaşılırsa play/pause geri alınır ve çift tap davranışı uygulanır |
| Herhangi bir dokunuş | Overlay görünürlüğünü tazeler (başlık, bölüm no, scrubber, sağ ray butonları gösterilir/açık tutulur); 3 sn hareketsizlikte otomatik gizlenir | Scrubbing sırasında otomatik gizleme askıya alınır |
| Çift tap (sağ yarı) | **+10 sn** seek (`tolerance: .zero` değil — hızlı segment sınırı seek'i; ikon animasyonu) | Bölüm sonuna < 10 sn kala → bölüm sonuna seek, auto-next tetiklenmez (kullanıcı bekletilir, §8.6 sayaç kuralı) |
| Çift tap (sol yarı) | **−10 sn** seek | Başa < 10 sn kala → 0'a seek |
| Uzun basma (basılı tut) | **2x hız** (basılı olduğu sürece); bırakınca önceki hıza döner | Kilitli bölüm önizlemesinde devre dışı; 2x sırasında ses pitch korunur (`AVAudioTimePitchAlgorithm.timeDomain`) |
| Dikey swipe | Önceki/sonraki bölüm (collection view paging) | Kilitli bölüme swipe → §9 akışı |
| Scrubber sürükleme | Canlı konum önizlemesi + zaman etiketi; bırakınca `seek(to:, toleranceBefore: .zero, toleranceAfter: .zero)` | Sürükleme sırasında oynatma durmaz, **ses susturulur** (parmak kalkınca geri açılır — 01-ozellik-envanteri.md PLR-05); yalnızca bırakınca seek edilir. **Thumbnail preview Faz 2** (trick-play/`AVAssetImageGenerator` şeridi) |

### 8.2 Hız menüsü

Sağ ray → "Hız": `0.75x / 1x / 1.25x / 1.5x / 2x`. Seçim `defaultRate` (iOS 16+) ile uygulanır ve **global tercihtir**: oturum boyunca ve bölümler/diziler arası korunur, **UserDefaults'a yazılır** ve uygulama yeniden başlatılınca da geçerlidir (kanonik karar — 01-ozellik-envanteri.md PLR-04; Ayarlar → oynatma tercihleriyle senkron). Uzun basma 2x'i, menü hızının üzerine geçici olarak biner.

### 8.3 Altyazı seçimi — AVMediaSelection

Çok dilli altyapı kanoniktir (EN başta, TR/ES/PT ikinci dalga); altyazılar HLS manifest'inde `SUBTITLES` grubu olarak gelir.

```swift
func applySubtitle(languageCode: String?, to item: AVPlayerItem) async {
    guard let asset = item.asset as? AVURLAsset,
          let group = try? await asset.loadMediaSelectionGroup(for: .legible) else { return }
    if let code = languageCode {
        let options = AVMediaSelectionGroup.mediaSelectionOptions(
            from: group.options, with: Locale(identifier: code))
        item.select(options.first, in: group)
    } else {
        item.select(nil, in: group)   // altyazı kapalı
    }
}
```

- Varsayılan: Ayarlar'daki altyazı dili; yoksa uygulama dili; o da manifest'te yoksa EN.
- Seçim, sağ ray → "Altyazı" sheet'inden yapılır ve **global tercihtir** (tüm dizilere uygulanır, Ayarlar ile senkron).
- Havuzdaki warm item'lara da aynı seçim item yaratılırken uygulanır — swipe sonrası altyazı sıçraması olmaz.
- Stil: sistem `Media Accessibility` (kullanıcının sistem altyazı stili) devralınır; özel stil dayatılmaz.

### 8.4 Sağ ray ve alt bant (özet)

Sağ ray: favori (Listem/Favoriler'e), paylaş, bölüm listesi (BolumListesi sheet'i), hız, altyazı. Alt bant: dizi adı → DiziDetay, bölüm numarası, scrubber. Ayrıntılı yerleşim 02-ekran-haritasi-navigasyon.md'dedir; buradaki sözleşme, bu aksiyonların `PlayerFeedViewController` delegate'i üzerinden Coordinator'a akmasıdır.

**Genişleme prosedürü:** sağ ray buton listesi kanonik olarak **kapalıdır**. Yeni buton eklemek tek başına bir UI işi değil sözleşme değişikliğidir; üç doküman **aynı PR'da** güncellenir: bu bölüm (04 §8.4), 02-ekran-haritasi-navigasyon.md §4.3.2 ve 01-ozellik-envanteri.md FEED-04. Yeni buton şu kurallara uyar: (1) gösterim verisi feed payload'ından gelir — bölüm başına ek istek **yasaktır**; (2) aksiyon, diğer ray aksiyonları gibi delegate ile Coordinator'a akar (§2.4 `PlayerFeedDelegate`); (3) canlı güncelleme (sayaç, durum) gerekiyorsa veri R8 portu üzerinden okunur (bkz. 03-mimari.md §4); (4) buton remote flag arkasında açılır — flag kapalıyken ray eski düzenini korur.

### 8.5 BolumListesi kesişimi

BolumListesi player içinden sheet olarak açılır (kanon). Sheet açıkken oynatma **devam eder** (ses + video, sheet medium detent). Bölüm seçilince: sheet kapanır → feed o bölüme programatik scroll (animasyonsuz `scrollToItem`) → havuz penceresi yeni indekse kurulur → oynatma başlar. Kilitli bölüm seçilirse §9 akışı devreye girer.

### 8.6 Otomatik sonraki bölüm ve dizi sonu

- `AVPlayerItemDidPlayToEndTime` bildirimi (**yalnızca aktif item için** — bildirim `object` filtresi zorunlu, §14 T4) auto-next'i tetikler: feed bir sonraki hücreye programatik kaydırılır (kısa, 0.3 sn'lik animasyon), sonraki bölüm zaten warm olduğundan geçiş < 100 ms'de sese/kareye kavuşur. Cliffhanger + otomatik sonraki bölüm binge döngüsünün çekirdeğidir (bkz. 07-retention-gamification.md).
- Otomatik oynatma Ayarlar → oynatma tercihlerinden kapatılabilir; kapalıysa bölüm sonunda "Sonraki bölüm" kartı + geri sayım yerine statik buton gösterilir.
- **Dizi sonu → yeni dizi önerisi:** dizinin son bölümü bitince feed'in bir sonraki öğesi, feed API'ının döndürdüğü **yeni dizi önerisidir** (kanon: "dizi bitince/atlanınca yeni dizi önerisi"). Araya tam ekran bir "Dizi bitti" ara kartı (dizi kapağı + "Sıradaki dizi" başlığı + 3 sn otomatik geçiş) girer; kullanıcı swipe ile beklemeden geçebilir. Öneri mantığı sunucudadır; istemci yalnızca feed sırasını oynatır (bkz. 05-veri-modeli-api.md).
- Kullanıcı diziyi **atlarsa** — kanonik tanım: aynı diziden art arda 2 bölüm, izlenme eşiğinin altında kalıp swipe ile geçildiyse (**eşik remote config, varsayılan 10 sn**; aynı tanım 01-ozellik-envanteri.md FEED-03 ve 02-ekran-haritasi-navigasyon.md §4.3.1'de) — feed API'ına `skip` sinyali gönderilir ve sonraki sayfa yeni dizi önerisiyle gelir; `series_skipped` event tetiği de bu tanımı referans alır (bkz. 08-analitik-deney.md event şeması).

**Kabul kriterleri (bölüm 8):**
- Jest çakışma matrisi (tek/çift tap, uzun bas + swipe kombinasyonları) UI testlerinde yeşil.
- Auto-next geçişinde ses kesintisi < 100 ms; ara kart yalnızca dizi sonunda görünür.
- Altyazı tercihi, uygulama yeniden başlatılınca ve tüm warm player'larda korunur.

---

## 9. Kilitli bölüm kesişimi

Monetizasyon akışının player içindeki yüzeyi budur; ekonomi kuralları 06-monetizasyon.md'de, buradaki sözleşme davranıştır.

### 9.1 Akış

1. Feed verisi her bölüm için erişim sözleşmesini taşır: `Episode.access.kind == .locked` + `access.unlockPrice` (API'den dinamik; kanon: bölüm kilidi 50–100 coin; sözleşme 05-veri-modeli-api.md §2.2). Entitlement (VIP / daha önce açılmış) R8 protokolü `EntitlementChecking` üzerinden çözülür — protokol AppFoundation'da tanımlıdır, uygulaması `WalletKit`'tedir (bkz. 03-mimari.md §4): `isLockedForCurrentUser = access.kind == .locked && !entitlements.hasAccess(episodeID)`.
2. Kullanıcı kilitli bölüme swipe eder → hücre görünür olur ama **oynatma başlamaz**: aktif player pause edilir, hücre kilit durumunu gösterir (bulanık kapak karesi + kilit ikonu + fiyat).
3. Hücre yerleşir yerleşmez Coordinator'a `lockedEpisodeReached(episode)` bildirilir → **UnlockSheet** açılır: coin ile aç / reklam izle / VIP ol (kanon). Coin yetersizse akış CoinMagazasi'na, VIP seçeneği VIPAbonelik'e gider — tamamı WalletKit yüzeyleridir.
4. **Prefetch kilidi:** `PrefetchController` ve `EpisodeCacheStore`, entitlement olmayan kilitli bölümü ısındırmaz (§5.4, §7.2). Backend zaten imzalı URL vermez; istemci tarafındaki kontrol, boşa 403 istekleri ve UnlockSheet öncesi ağ gürültüsünü önler.
5. Kilidin cliffhanger noktasına denk geldiği unutulmamalıdır (kanon; desen kaynağı: https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop) — bu yüzden geçişin duygusu kesintisiz olmalıdır: önceki bölümün son karesi arkada donuk durur, UnlockSheet onun üzerine gelir.

### 9.2 Unlock sonrası akıcı devam

1. UnlockSheet başarıyla kapanır (coin harcandı / reklam tamamlandı / VIP oldu) → `WalletKit` entitlement'ı günceller ve `PlayerKit`'e `episodeUnlocked(episodeID)` yayınlanır.
2. `ContentKit` bölüm için imzalı URL'yi çeker (unlock yanıtı URL'yi taşıyorsa ekstra round-trip yoktur — API sözleşmesi 05-veri-modeli-api.md).
3. `PlayerPool.acquire` ile item hazırlanır ve **kullanıcı hâlâ o hücredeyse** `playImmediately` ile baştan (veya `resumePosition` varsa kaldığı yerden — yarım bırakılmış kilitli bölüm senaryosu) oynatma başlar. Hedef: sheet kapanışı → ilk kare p90 < 700 ms (URL round-trip dahil).
4. Unlock sonrası `index + 1` prefetch'i normal kurala döner (bir sonraki bölüm de kilitliyse ısındırılmaz).

### 9.3 Edge case'ler

- **Sheet'i kapatıp geri kaydırma:** kullanıcı UnlockSheet'i kapatırsa hücre kilit durumunda kalır; hücredeki "Kilidi Aç" butonu sheet'i yeniden açar. Yukarı swipe serbesttir.
- **Reklam yolu başarısız** (dolum yok / yarıda kapandı): sheet'te reklam seçeneği devre dışı kalır + kalan günlük hak gösterilir (kanon: günde 5–10 cap, remote config; bkz. 06-monetizasyon.md).
- **Arka planda unlock** (ör. başka cihazda VIP): feed görünür olduğunda entitlement yenilenir; kilit ikonlu hücreler yerinde güncellenir.
- **Auto-next kilide çarparsa:** otomatik geçiş kilitli bölümde durur ve UnlockSheet açılır — sonsuz otomatik harcama asla olmaz; unlock her zaman açık kullanıcı aksiyonudur.

**Kabul kriterleri (bölüm 9):**
- Kilitli bölüm hücresinde `AVPlayer.rate == 0` ve sıfır media isteği (ağ kaydı).
- Unlock → ilk kare p90 < 700 ms.
- UnlockSheet reddedilip 5 kez swipe yapılan stres testinde çift sheet açılmaz (idempotent tetik).

---

## 10. AVAudioSession yönetimi

`AudioSessionCoordinator` (PlayerKit içinde, `AppFoundation` yaşam döngüsü sinyallerini dinler) tek yetkilidir; başka hiçbir modül `AVAudioSession`'a dokunmaz.

### 10.1 Kategori ve aktivasyon

- Kategori: `.playback`, mode `.moviePlayback`, options: `[]` (mix yok — biz öndeyken başka ses çalmaz).
- **Sessiz mod davranışı:** `.playback` kategorisi gereği video sesi **sessiz anahtarını yok sayar ve çalar** (kategori standardı; TikTok/benzeri dikey video uygulamalarının beklenen davranışı). Kullanıcı sesi kapatmak isterse donanım volume tuşları geçerlidir; ayrıca oynatucu overlay'inde mute butonu yoktur (bilinçli karar — feed sesli deneyimdir).
- `setActive(true)` **arka plan kuyruğunda** çağrılır (bloklayıcı çağrı, main thread'de yasak — §14 T6) ve ilk oynatma anına ertelenir (Splash'ta değil).

### 10.2 Kesintiler (çağrı / Siri / alarm)

`AVAudioSession.interruptionNotification`:

- `.began` → aktif player pause; `PlaybackProgressTracker` checkpoint yazar; UI play butonuna döner.
- `.ended` + `.shouldResume` seçeneği **varsa** → otomatik resume (`playImmediately`).
- `.ended` + `.shouldResume` **yoksa** (ör. kullanıcı çağrıyı uzun tuttu) → paused kalır; kullanıcı tap ile devam eder.
- Kesinti sırasında gelen swipe'lar normal işler; yeni bölüm de paused başlar, kesinti bitince aktif hücre oynar.

### 10.3 Route değişimi (kulaklık çıkarma)

`AVAudioSession.routeChangeNotification`, reason `.oldDeviceUnavailable` → **pause** (Apple insan arayüzü standardı: kulaklık çıkınca içerik hoparlöre bağırmaz). Kulaklık takılması (`.newDeviceAvailable`) oynatmayı değiştirmez. Bluetooth kopması aynı kurala tabidir.

### 10.4 Ses odağı ve diğer uygulamalar

Feed görünür + oynuyorken session aktiftir; kullanıcı başka sekmeye geçince (Ana Sayfa dışı) player pause edilir ve session `setActive(false, options: .notifyOthersOnDeactivation)` ile bırakılır — arka planda müzik dinleyen kullanıcının müziği geri gelir.

**Kabul kriterleri (bölüm 10):**
- Sessiz anahtarı açıkken video sesli çalar; telefon çağrısı gelip kapanınca oynatma kaldığı milisaniyeden devam eder.
- AirPods çıkarıldığında ≤ 200 ms içinde pause.
- Keşfet sekmesine geçince arka plan müziği (Apple Music) otomatik geri gelir.

---

## 11. Uygulama yaşam döngüsü

| Olay | Davranış |
|---|---|
| `didEnterBackground` | Aktif player **pause**; progress checkpoint (§12) hemen flush; `AVPlayerLayer.player` bağlantısı korunur (iOS arka planda video kareyi zaten dondurur); prefetch task'ları askıya alınır |
| `willEnterForeground` | Entitlement + imzalı URL tazelik kontrolü → aktif bölüm `playImmediately` ile **resume** (otomatik oynatma ayarı kapalıysa paused + overlay ile döner); prefetch kaldığı yerden devam |
| Sekme değişimi (Ana Sayfa → diğer) | Pause + audio session bırakılır (§10.4); havuz item'ları korunur (geri dönüş anlık) |
| Uygulama sonlandırma | Progress checkpoint'ler zaten periyodik yazıldığından ek iş yok; son konum en fazla checkpoint aralığı kadar (≤ 5 sn) geriden gelir |
| Bellek uyarısı | Pencere dışı slot'lar boşaltılır (§3.3), görsel cache küçültülür |

**PiP (Picture-in-Picture) Faz 1'de KAPALIDIR:** `AVPictureInPictureController` kurulmaz, `canStartPictureInPictureAutomaticallyFromInline` kullanılmaz. Gerekçe: portrait-locked mikro-drama deneyiminde PiP, retention döngüsünü (tam ekran + overlay + UnlockSheet) baltalar ve kilitli bölüm kesişimini karmaşıklaştırır; yeniden değerlendirme **F2 kapısındadır** (bkz. 01-ozellik-envanteri.md, 09-yol-haritasi-tasklar.md). Arka planda ses devam ettirme de (audio-only background playback) aynı gerekçeyle kapalıdır — background mode yetkisi binary'ye eklenmez.

> **PiP açılırsa değişecek sözleşmeler (F2 kapısı değerlendirmesi için kayıt):**
> - `didEnterBackground` "aktif player pause" kuralı (yukarıdaki tablo) — PiP'te oynatma arka planda sürer; pause koşulu "PiP aktif değilse"ye daralır.
> - Sekme değişiminde `setActive(false)` (§10.4) — PiP sürerken audio session bırakılamaz; ses odağı sözleşmesi yeniden yazılır.
> - Hücredeki `AVPlayerLayer` sahipliği (§3.3 kural 4, §14 T8) — PiP controller layer'ı devralır; `prepareForReuse`/lease bağlama kuralları güncellenir.
> - Background entitlement — binary'ye background mode yetkisi eklenir; bu bölümdeki "eklenmez" kararı ve kabul kriteri ("PiP hiçbir cihazda tetiklenemez") kalkar.
> - Kilitli bölüme auto-next (§9.3) — PiP penceresinde UnlockSheet gösterilemez; otomatik geçiş kilide çarptığında PiP davranışı (durma / uygulamaya dönme) tanımlanmalıdır.

**Kabul kriterleri (bölüm 11):**
- Home'a çıkıp 10 sn sonra dönüşte: aynı kare + otomatik devam, yeni allocation yok.
- App Switcher'da video karesi donuk görünür, ses sızmaz.
- PiP hiçbir cihaz/iOS sürümünde tetiklenemez (yetki + kod yokluğu).

---

## 12. İlerleme takibi ve Devam Et senkronu

"Devam et her yüzeyde" retention kanonunun player tarafındaki üreticisi `PlaybackProgressTracker`'dır.

### 12.1 Gözlem ve event üretimi

```swift
final class PlaybackProgressTracker {
    private var timeObserverToken: Any?
    private weak var observedPlayer: AVPlayer?

    func attach(to player: AVPlayer, episode: Episode) {
        detach()   // önceki observer MUTLAKA kaldırılır (§14 T3)
        observedPlayer = player
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.handleTick(time, episode: episode)
        }
    }

    func detach() {
        if let token = timeObserverToken { observedPlayer?.removeTimeObserver(token) }
        timeObserverToken = nil
        observedPlayer = nil
    }
}
```

- **Tick (1 sn):** yerel state güncellenir; izleme süresi sayacı (görev sistemi "X dk izle" görevleri bunu tüketir — bkz. 07-retention-gamification.md) ilerler.
- **Checkpoint (5 sn'de bir + pause/kesinti/arka plan/bölüm değişiminde):** `resumePosition`, AppFoundation'da tanımlı progress repository protokolü üzerinden SwiftData'ya yazılır (anında, offline-safe; PlayerKit SwiftData import etmez — §2.4, §7.2).
- **Sunucu senkronu (10 sn'de bir + bölüm sonu + arka plana geçiş):** `ContentKit` progress API'ına `episodeID, position, duration, watchedSeconds` gönderilir (bkz. 05-veri-modeli-api.md). Ağ yoksa kuyruklanır, sıradaki fırsatta flush edilir.
- **Analitik event'leri** 08-analitik-deney.md §3.2 kataloğuyla birebir basılır: `video_start` (`ttff_ms` parametresiyle), `video_progress` (checkpoint `25|50|75|100`), `video_stall`, `swipe_next`/`swipe_prev` (`swipe_latency_ms` parametresiyle). Katalogda olmayan bir event gerekiyorsa önce event registry sürecinden geçirilip 08'e eklenir. Bölüm "tamamlandı" eşiği kanonik olarak **%90**'dır (`progress.completedThreshold = 0.9`; kapanış jeneriği payı — bkz. 05-veri-modeli-api.md §2.11, 07-retention-gamification.md §2.2).

### 12.2 Devam Et tüketimi

- Feed, `resumePosition > 3 sn && < %90` (`completedThreshold` altı) olan bölümü açarken o konumdan başlar (item hazırlanırken `seek`, ilk kareden önce — kullanıcı sıçrama görmez). "Continue watching = son konumu kaydet + başlangıçta uygula" deseni sektör standartıdır (https://www.fastpix.io/tutorials/how-to-build-a-micro-drama-video-app-like-reelshort-or-dramabox).
- Devam Et yüzeyleri (Listem/Devam Et segmenti, Ana Sayfa rafı, DiziDetay "Devam Et" CTA'sı, push) aynı SwiftData + sunucu kaydını okur; tek doğruluk kaynağı progress API'dır, yereldeki kayıt en-son-yazan-kazanır ile birleşir (cihazlar arası: sunucu zaman damgası üstündür).
- Bölüm %90+ izlendiyse (`completedThreshold = 0.9`) Devam Et kaydı **bir sonraki bölüme** işaret eder (kilitliyse kilitli bölümün kendisine — push/DiziDetay'dan gelen kullanıcı UnlockSheet ile karşılanır, §9).

**Kabul kriterleri (bölüm 12):**
- Uygulamayı öldürüp yeniden açınca konum kaybı ≤ 5 sn.
- İki cihaz senaryosunda (misafir → Apple ile bağlanmış hesap) en güncel konum kazanır.
- Uçak modunda 3 bölüm izlenip ağa dönülünce tüm progress event'leri sırayla flush edilir.

---

## 13. Performans ölçümü

İlke: **bütçe yalnızca ölçülüyorsa vardır.** İki katman: MetricKit (sistem sinyalleri) + kendi player metriklerimiz; ikisi de `AnalyticsKit` şemasına akar (bkz. 08-analitik-deney.md).

### 13.1 Kendi player metriklerimiz — PlayerMetricsCollector

| Metrik | Kaynak | Not |
|---|---|---|
| **TTFF** | İşaretleyici çifti: `t0` = oynatma niyeti (Splash'ta feed isteği yanıtı / swipe-settle), `t1` = ilk kare (`AVPlayerItem` `isPlaybackLikelyToKeepUp` + boundary observer'lı ilk kare sinyali). Çapraz doğrulama: `AVPlayerItemAccessLog.events.last?.startupTime` | p50/p90/p99 raporlanır; soğuk açılış ayrı boyut |
| **Swipe latency** | `t0` = `scrollViewWillEndDragging` hedef indeks belli olduğunda, `t1` = yeni aktif player ilk kare | Bütçe < 100 ms; prefetch isabet/kaçırma boyutuyla birlikte |
| **Stall count/duration** | `AVPlayerItemPlaybackStalled` bildirimi + `accessLog().events` (`numberOfStalls`, `durationWatched`) | Oturum ve bölüm bazında; stall oranı = stall süresi / izleme süresi |
| **İndirilen bitrate / rung dağılımı** | Access log `indicatedBitrate` / `observedBitrate` | Veri tasarrufu doğrulaması + ABR sağlığı |
| **Prefetch isabet oranı** | Swipe anında hedef bölüm warm mıydı? | Hedef ≥ %95 (normal ağ) |
| **Hata oranı** | `AVPlayerItem.status == .failed`, error log (`errorLog()`), 403-kurtarma sayacı | Kurtarma başarısı içeride loglanır; analitik event'i gerekirse registry süreciyle 08'e eklenir (§13.1 sonu) |

Ayrı performans event'i YOKTUR (08-analitik-deney.md §4): metrikler taşıyıcı event'lerin parametresi olarak akar — TTFF `video_start` event'inin `ttff_ms` parametresi, swipe gecikmesi `swipe_next`/`swipe_prev` event'lerinin `swipe_latency_ms` parametresi; stall'lar `video_stall` event'iyle raporlanır. Hata oranı ve prefetch isabet oranı için 08 kataloğunda event yoktur; gerekirse event registry sürecinden geçirilip 08'e eklenir. Örnekleme: bu taşıyıcı event'ler %100 toplanır (hacim düşük), access log dökümleri %10 örneklenir.

### 13.2 MetricKit

- `MXMetricManager` abonesi `AppFoundation`'da yaşar; `PlayerKit`'e düşen payloadlar: `MXAnimationMetric` (scroll hitch rate → 60 fps bütçesi), `MXAppResponsivenessMetric`/hang raporları (main thread blokajı, §14 T6), `MXMemoryMetric` (havuz + cache bellek ayak izi), `MXDiskIOMetric` (cache yazma sağlığı).
- Crash tarafı Firebase Crashlytics'tedir (kanon); MetricKit crash diagnostiği çapraz kontrol olarak saklanır. Crash-free hedefi ≥ %99.8 (kanon §5 hedefi; bkz. 08-analitik-deney.md).
- Hitch rate hedefi: scroll sırasında < 5 ms/s (Apple "iyi" bandı); regresyon CI perf koşusunda yakalanır.

### 13.3 Debug HUD ve CI

- Dahili build'lerde player HUD'u (TTFF, aktif rung, buffer sn, havuz durumu, prefetch durumu) feature flag ile açılır.
- CI'da her release adayı için otomatik perf koşusu: simüle ağ profillerinde (Wi-Fi / LTE / 3G) 30-swipe senaryosu; p90 bütçe aşımı build'i kırar (bkz. 09-yol-haritasi-tasklar.md).

---

## 14. Bilinen tuzaklar ve çözümleri

| # | Tuzak | Belirti | Çözüm / kural |
|---|---|---|---|
| T1 | **AVPlayerItem'ı ikinci bir player'a bağlamak** | `NSInvalidArgumentException: An AVPlayerItem cannot be associated with more than one instance of AVPlayer` crash'i | Item, player başına yaratılır; havuz slot geri alırken `replaceCurrentItem(with: nil)` sonrası yeni item. Aynı bölüme dönüşte aynı `AVURLAsset`'ten yeni item yaratmak ucuzdur (asset cache'i korunur) |
| T2 | **Senkron asset yükleme** (`asset.duration` vb. property'ye ana thread'de dokunmak) | Scroll sırasında donma, MetricKit hang raporları | Tüm asset anahtarları `load(.duration, .isPlayable, ...)` async API ile arka planda yüklenir; item ancak yükleme bitince player'a takılır (`PlayerAssetFactory` sözleşmesi) |
| T3 | **Periodic time observer sızıntısı / çift kayıt** | Bölüm değişiminde progress event'leri çoğalır; `removeTimeObserver` atlanınca crash | Token saklanır, `attach` her zaman önce `detach` çağırır (§12.1); observer closure'ları `[weak self]` |
| T4 | **`AVPlayerItemDidPlayToEndTime`'ı object filtresiz dinlemek** | Havuzdaki başka bir item bitince yanlış auto-next tetiklenir | `NotificationCenter` aboneliği her zaman `object: currentItem` ile; item değişince abonelik yenilenir |
| T5 | **KVO sızıntısı** (`status`, `isPlaybackLikelyToKeepUp` gözlemcileri) | Deallocation crash'leri, hayalet callback'ler | Blok tabanlı `NSKeyValueObservation` kullanılır, token'lar hücre/tracker yaşam döngüsüne bağlanır ve `invalidate()` edilir. Combine yasak (kanon); async gözlem gerekiyorsa AsyncStream sarmalayıcı `AppFoundation`'dan |
| T6 | **Main thread blokajı**: `AVAudioSession.setActive`, senkron `seek` beklemek, ağ üstünde `AVURLAsset` yaratıp hemen property okumak | Kaydırma hitch'leri, watchdog kill | Session aktivasyonu arka plan kuyruğu (§10.1); seek completion handler'lı asenkron form; asset işleri `PlayerAssetFactory`'de |
| T7 | **`reloadData` ile feed güncelleme** | Oynayan hücre yeniden yaratılır, video kararır | Diff'li güncelleme (`UICollectionViewDiffableDataSource`); aktif hücrenin identity'si korunur (§2.3) |
| T8 | **`prepareForReuse`'da player'ı durdurmak/boşaltmak** | Swipe sırasında ses kesilir, havuz state'i bozulur | Hücre yalnızca `playerLayer.player = nil` yapar; player yaşam döngüsü sadece `PlayerPool`'dadır (§3.3) |
| T9 | **Scrubber'da her sürükleme tick'inde precise seek** | Seek fırtınası, HLS'de segment thrash | Sürüklerken yalnız UI güncellenir; seek tek sefer, parmak kalkınca (§8.1). Ardışık seek'lerde öncekiler `cancelPendingSeeks` ile iptal |
| T10 | **`automaticallyWaitsToMinimizeStalling = false` + HLS** | Anında stall, titrek başlatma | Bayrak `true` kalır; anında başlatma `playImmediately(atRate:)` ile (§4.2) |
| T11 | **İmzalı URL'yi item içinde süresiz kullanmak** | Uzun oturumlarda ansızın 403 → siyah ekran | Tazelik kontrolü + 403-kurtarma akışı (§6.4) |
| T12 | **Bildirim/route callback'lerinin thread'ine güvenmek** | UI güncellemesi arka thread'de → crash | Tüm AVFoundation bildirim handler'ları `MainActor`'a hop eder; state mutasyonları `PlayerPool` actor'ünde |
| T13 | **Kesinti sırasında player'ı release etmek** | `.ended` callback'i ölü referansa gelir | `AudioSessionCoordinator` kesinti boyunca aktif lease'i güçlü tutar; kesinti bitmeden `drain` çağrılmaz |
| T14 | **Havuza sınırsız slot eklemek** ("bir slot daha çözer" refleksi) | Bellek şişmesi, arka plandaki decode yarışları | `precondition((3...5).contains(size))` — bütçe kanonik, istisna mimari karar gerektirir |

---

## 15. Faz kapsamı özeti

| Yetenek | Faz |
|---|---|
| UICollectionView feed, PlayerPool, PrefetchController, buffer/HLS politikaları, jestler, hız, altyazı, auto-next, UnlockSheet kesişimi, progress senkronu, metrikler | **Faz 1** |
| Scrubber thumbnail preview (trick-play), FairPlay DRM, rewarded ads kesişiminin reklam SDK'sı | **Faz 2** |
| İndirilenler (Listem segmenti, `AVAssetDownloadTask` altyapısı §7 üzerinde), Live Activities | **Faz 3** |
| PiP | Kapalı (Faz 1 kararı; yeniden değerlendirme F2 kapısında, §11'deki sözleşme kutusuyla birlikte — 09-yol-haritasi-tasklar.md) |

---

## Kaynaklar

- https://www.mux.com/blog/building-tiktok-smooth-scrolling-on-ios — UICollectionView + player havuzu + yön farkındalıklı prefetch kalıbı
- https://www.techinterview.org/post/3233474985/design-tiktok-video-feed-mobile/ — 3–5 player havuzu, ~500 KB / 2 sn prefetch, ~200 MB LRU, performans bütçeleri
- https://medium.com/@sojik/avplayer-video-optimization-part-1-2a45ea002ea2 — `preferredForwardBufferDuration` ölçülmüş etkisi (37.8 MB → 0.2 MB)
- https://developer.apple.com/documentation/avfoundation/avplayeritem/preferredforwardbufferduration — resmi API referansı
- https://developer.apple.com/forums/thread/649810 — HLS'in URL interception ile cache'lenememesi, `AVAssetDownloadTask` gerekliliği
- https://spyro-soft.com/blog/media-and-entertainment/microdrama-monetisation-models-why-the-real-innovation-isnt-the-content-its-the-payment-stack — TTFF < 500 ms, 2–6 sn segment, 300 kbps–2.5 Mbps portrait merdiveni
- https://www.fastpix.io/tutorials/how-to-build-a-micro-drama-video-app-like-reelshort-or-dramabox — mikro-drama video stack'i, imzalı URL + continue-watching deseni
- https://www.consumeourinternet.com/p/reelshort-and-the-rise-of-dramaslop — cliffhanger noktasında paywall UX teardown'ı
