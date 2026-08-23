# Kod Kalitesi/Güvenlik Audit Bulguları — Backlog

Kaynak: kapsamlı adversarial sweep (10 subsystem × risk-lens finder → şüpheci verify).
Durum tarihi: 2026-08-21 · Tam senaryo/verify: sweep transcript (wf_ad2c2af6-bff).

**Toplam 41 bulgu** · HIGH=3 · MEDIUM=18 · LOW=20 · CONFIRMED=33

Kanon: server-otoriter para (istemci kredi vermez); bu bulguların ÇOĞU para-invaryantını İHLAL ETMEZ 
(server düşer + store rollback) ama bozuk-UX / veri-izolasyon (stale display) / crash-robustness / 
state-tutarlılığı kusurlarıdır. Öncelik: HIGH → MEDIUM(CONFIRMED) → LOW.

Durum: ☐ açık · ☑ düzeltildi (commit ile) · ⊘ kabul-edildi/won't-fix (gerekçeyle)

## HIGH (3)

- ☑ **[WalletKit/unlock-integrity]** Packages/WalletKit/Sources/WalletKit/UI/UnlockSheet/UnlockSheetModel.swift:232 — DÜZELTİLDİ (Option A: WalletStore iyimser yayın lastUnlocked taşımaz, yalnız onaylı unlock taşır; WalletKit 287 test + gerçek-store entegrasyon testi yeşil)
  - Sheet'in entitlement gozlemcisi, WalletStore'un KENDI iyimser unlock yayinini disaridan-unlock zannedip performUnlock'un 402/409 sonuc islemesini olu-koda cevirir.
- ☑ **[PlayerKit/wrong-state-on-transition]** Packages/PlayerKit/Sources/PlayerKit/Engine/PlaybackEngine.swift:179 — DÜZELTİLDİ (clearEndedLatch + reuseWarmSlot wiring; PlayerKit 237 test yeşil)
  - Tamamlanmis (playedToEnd) bir bolume warm-hit ile geri donuldugunde `endedForCurrentLoad` latch'i sifirlanmadigindan yeniden aktivasyon aninda auto-advance ANINDA tekrar tetiklenir; kullanici o bolumde duramaz/yeniden izleyemez.
- ☑ **[App/singleton-state-leak]** App/DI/AppComposition+Account.swift:25 — DÜZELTİLDİ (WalletStore.reset() + koordinatör resetWallet/refreshWallet wiring; WalletKit 284 + App 212 test yeşil)
  - Hesap-değişiminde (switchToExistingAccount) yerel-store reset yalnız izleme-geçmişi + favori repository'lerini siler; paylaşılan WalletStore singleton'ı (bakiye/entitlement/unlockedEpisodes/version) ne resetlenir ne refresh edilir → §575 cross-account sızıntısı.

## MEDIUM (18)

- ☑ **[WalletKit/entitlement-flip-race]** Packages/WalletKit/Sources/WalletKit/UI/UnlockSheet/UnlockSheetModel.swift:232 — DÜZELTİLDİ (aynı kök: HIGH unlock-integrity Option A fix'i bunu da kapatır)
  - Optimistik coin-unlock'ın kendi `markUnlocked` yayını (lastUnlockedEpisode == episodeID) sheet'in entitlement gözlemcisini server yanıtından ÖNCE `completeUnlock()`'a sürükler; server unlock'u reddedince rollback olur ama sheet zaten 'açıldı' der ve red bastırılır.
- ☐ **[AppFoundation/session-invalidation-race]** Packages/AppFoundation/Sources/AppFoundation/Session/SessionManager.swift:255
  - SessionStateBroadcaster.stream() delivers its initial snapshot OUTSIDE the lock, so a concurrent yield() can be observed before the (now stale) replay — a new subscriber can end on a stale state, undoing session invalidation.
- ☑ **[AppFoundation/keychain-error-handling]** Packages/AppFoundation/Sources/AppFoundation/Session/TokenRefreshCoordinator.swift:107 — DÜZELTİLDİ (try? → try; geçici keychain hatası yüzer, yıkıcı logout yok)
  - performRefresh uses `try?` on the refresh-token keychain read, so a transient keychain failure (device locked before first unlock under afterFirstUnlockThisDeviceOnly, or a transient securityd/errSecMissingEntitlement glitch) is indistinguishable from an absent token and routes straight to the destructive recoverViaFallback path.
- ☑ **[AppFoundation/crash-robustness]** Packages/AppFoundation/Sources/AppFoundation/Networking/APIClient.swift:266 — DÜZELTİLDİ (isFinite guard + sayısal clamp Duration'dan önce; AppFoundation 287 test yeşil)
  - 429 Retry-After basliginda sonsuz/asiri buyuk sayisal deger .seconds(seconds) yapiminda trap ederek uygulamayi cokertiyor — 30 sn ust siniri (min) construct'tan SONRA uygulaniyor.
- ☐ **[AppFoundation/actor-reentrancy-toctou]** Packages/AppFoundation/Sources/AppFoundation/Push/DeviceTokenRegistering.swift:51
  - LiveDeviceTokenRegistrar reads the last-sent snapshot and decides the registration plan BEFORE the network await, but the snapshot is only persisted AFTER the await (saveSnapshot at line 73). The actor does not serialize load->decide->POST->save as an atomic unit, so a second call that interleaves at the `await apply` suspension point decides against a stale snapshot and can drop the user's latest opt-in intent — contradicting the class comment (line 17-18) that claims the actor serializes concurrent token/permission calls.
- ☑ **[RewardsKit/concurrency]** Packages/RewardsKit/Sources/RewardsKit/OdulMerkezi/OdulMerkeziModel.swift:251 — DÜZELTİLDİ (awaited guard exact-match → >=; RewardsKit 123 test yeşil)
  - awaitedBalance reconciliation guard clears ONLY on exact equality; a coalescing/newer balance stream value that skips the awaited number permanently freezes the coin header and swallows every subsequent live update.
- ☐ **[PlayerKit/resume-position-lost]** Packages/PlayerKit/Sources/PlayerKit/Pool/PlayerPool.swift:342
  - Henuz yuklenmekte olan (first-frame gelmemis) warm slot aktife terfi ederken reuseWarmSlot resumePosition'i dogrudan backend'e seek eder; item hazir olmadigindan seek yutulur ve pendingResumePosition ayarlanmadigindan ilk kare gelince tekrar seek edilmez -> devam konumu kaybolur, bolum bastan oynar.
- ☑ **[PlayerKit/state]** Packages/PlayerKit/Sources/PlayerKit/Pool/PlayerPool.swift:341 — DÜZELTİLDİ (aynı kök: warm-reuse latch clear)
  - Warm-slot reuse (healthy path) never re-prepares/resets the engine, so a just-completed episode keeps `endedForCurrentLoad = true`; re-subscribing replays playedToEnd and instantly re-fires auto-advance.
- ☑ **[PlayerKit/concurrency]** Packages/PlayerKit/Sources/PlayerKit/Engine/PlaybackEngine.swift:179 — DÜZELTİLDİ (aynı kök: warm-reuse latch clear)
  - playedToEndEvents() latch (endedForCurrentLoad) replays a stale 'ended' event to every new subscriber, but the latch is only reset in prepare()/reset() — not on a warm-slot reuse. Because FeedPlaybackDirector re-subscribes on each activation, returning to a previously-finished, warm-reused episode fires a spurious auto-advance.
- ☐ **[ProfileKit/data-isolation]** Packages/ProfileKit/Sources/ProfileKit/Profil/ProfilModel.swift:108
  - observeSession updates `account` from the session stream but never resets `wallet`, so the previous account's coin balance / VIP status stays displayed after a session-expiry (or guest/account transition) that emits no wallet-stream event.
- ☐ **[ProfileKit/reset-partial]** Packages/ProfileKit/Sources/ProfileKit/BildirimMerkezi/NotificationCenterModel.swift:114
  - pendingDeletedIDs mezar-tası temizligi yalnız İLK sayfaya (cursor:nil) bakar; sonraki sayfalardaki silinmis id'lerin mezar-tası erkenden düser ve öge diriler (kısmi reset).
- ☐ **[App/wrong-port-binding]** App/DI/AppComposition+FeatureModels.swift:96
  - KesfetModel(29)/AramaModel(44)/DiziDetayModel(64)/CoinShopModel(96)/VIPSubscriptionModel(111) fabrikaları BASE `dependencies.analytics` alır; oysa dokümante edilen tasarım (ExperimentDimensionTracker + AppComposition.swift:88-90) 'feature model'leri decoratedAnalytics'i dependencies.analytics YERİNE alır; tek istisna ExperimentClient.analytics' der.
- ☐ **[ContentKit/decode-robustness]** Packages/ContentKit/Sources/ContentKit/API/Wire/DiscoverWire.swift:14
  - Malformed banner or nested series element throws the entire /discover decode, blanking Keşfet — the documented banner/collection isolation only covers absent/null fields, not present-but-invalid elements.
- ☐ **[DiscoverKit/concurrency-race]** Packages/DiscoverKit/Sources/DiscoverKit/Arama/AramaModel.swift:100
  - queryChanged edits the search field but neither cancels the in-flight resultsTask (performSearch) nor bumps searchGeneration, so a late-returning search from an abandoned query overrides the browsing/suggesting phase the user is now in.
- ☐ **[LibraryKit/favorite-sync-loss]** Packages/LibraryKit/Sources/LibraryKit/Favorites/FavoritesService.swift:214
  - Telafi DELETE durumu (compensatingDeletes) yalnız bellekte tutulur ve kalıcı bir yerel kayda dayanmaz; telafi kesintiye uğrarsa sunucuda hayalet favori kalıcı olarak sızar.
- ☐ **[LibraryKit/concurrency-state]** Packages/LibraryKit/Sources/LibraryKit/Listem/ListemModel.swift:143
  - loadFavorites has no generation/cancellation guard; two overlapping loadFavorites can commit out of order and resurrect a just-removed favorite.
- ☐ **[LibraryKit/tombstone-dedup]** Packages/LibraryKit/Sources/LibraryKit/Favorites/FavoritesService.swift:205
  - Compensating-DELETE intent for an add that was removed mid-PUT is held only in the in-memory compensatingDeletes set and is never persisted; if flush is deferred (offline or app kill) the removal is lost and, because favorites sync has no server->local pull, a ghost favorite stays on the server permanently.
- ☐ **[DiscoverKit/pagination-dedup]** Packages/DiscoverKit/Sources/DiscoverKit/Arama/AramaModel.swift:183
  - loadMore sayfa birleştirmesi (results += page.items) hiçbir dedup yapmaz; cursor sayfalamada sayfa sınırında örtüşen dizi aynı SeriesID ile iki kez listeye girer.

## LOW (20)

- ☐ **[AppFoundation/single-flight-gap]** Packages/AppFoundation/Sources/AppFoundation/Session/SessionManager.swift:212
  - handleRefreshFailure's guest re-bootstrap calls performGuestBootstrap() directly, bypassing the bootstrapTask single-flight guard used by bootstrapGuestSessionIfNeeded, so two concurrent POST /auth/guest can run.
- ☐ **[RewardsKit/money-integrity]** Packages/RewardsKit/Sources/RewardsKit/OdulMerkezi/OdulMerkeziModel.swift:250
  - applyBalance 'awaitedBalance' guard, exact-match ile temizlendigi icin, claim sonrasi araya giren gercek bir bakiye degisimi (baska cihazdan satin alma / VIP bonusu / ad-coin kredisi) beklenen degeri ATLARSA baslik kalici olarak BAYAT/yanlis bakiyede kilitlenir.
- ☐ **[PlayerKit/playback-auth-recovery]** Packages/PlayerKit/Sources/PlayerKit/Engine/PlaybackEngine.swift:265
  - recoveryAttempts is reset only in prepare(), never after a successful signed-URL recovery, so a warm-retained/long-lived loaded item permanently loses its mandated 1 auto-retry after the first mid-play expiry.
- ☐ **[PlayerKit/stall-recovery]** Packages/PlayerKit/Sources/PlayerKit/Engine/AVPlayerBackend.swift:206
  - `isLikelyStalled` is cleared only when isPlaybackLikelyToKeepUp becomes true; pausing/resuming across a stall leaves it stuck true, so the next genuine stall's playbackStalledNotification is suppressed and no buffering state is emitted.
- ☐ **[PlayerKit/state]** Packages/PlayerKit/Sources/PlayerKit/Engine/PlaybackEngine.swift:275
  - Signed-URL recovery unconditionally sets pendingPlay from the buffer policy, discarding a user pause issued during the recovery window; the active slot auto-resumes against the user's intent.
- ☐ **[ProfileKit/linking-merge-desync]** Packages/ProfileKit/Sources/ProfileKit/Profil/ProfilModel.swift:108
  - observeSession() günceller yalnız `account`'u; hesap DEĞİŞİMİNDE (misafir→farklı bağlı hesap / conflict→switch) cüzdan yeniden çekilmez, iki bağımsız akış koordine edilmez.
- ☐ **[App/config-misread]** App/DI/AppComposition.swift:150
  - appAccountToken her composition/launch'ta `UUID()` ile TAZE üretilir (persist edilmez), ama alan dokümantasyonu (satır 79-80) 'F1: kurulum-kararlı UUID' der — StoreKit işlemine gömülen appAccountToken her açılışta değişir.
- ☐ **[App/field-mapping]** App/DI/Adapters/RewardedAdAdapters.swift:217
  - AdUnlockResponseWire reads a top-level `remainingToday` field that the documented POST /rewards/ad-unlock 200 zarf does not contain, so the post-watch 'Bugün N/M kaldı' counter can never be populated.
- ☐ **[App/field-mapping]** App/DI/Adapters/AccountServiceAdapters.swift:134
  - switchToExistingAccount falls back to provider `.apple` when the /auth/switch response omits `provider`, mislabeling the switched-to account when it is Google or email.
- ☐ **[App/deeplink-fidelity]** /Users/orcunizmirli/projects/shortseries/App/Coordinators/TabCoordinator.swift:110
  - `.home` (ve `.profile`) deep-link/push rotaları yalnız sekme değiştirir; hedef sekmenin NavigationStack'ini köke sıfırlamaz → kullanıcı beklenen sekme kökü yerine önceden push edilmiş bayat detay ekranında kalır.
- ☐ **[ContentKit/decode-robustness]** Packages/ContentKit/Sources/ContentKit/API/Wire/FeedWire.swift:22
  - A malformed required field inside one nested episode/series throws the whole feed page before compactMap runs, so the documented per-item resilience does not protect against bad required data — the entire page is lost with no retry.
- ☐ **[LibraryKit/history-sync-stale]** Packages/LibraryKit/Sources/LibraryKit/Listem/ListemModel.swift:153
  - Devam Et'te gizlenen bölüm, kullanıcı onu yeniden izleyip taze ilerleme kaydetse bile oturum boyunca kalıcı olarak gizli kalır; hiddenEpisodeIDs hiç temizlenmez.
- ☐ **[LibraryKit/tombstone-dedup]** Packages/LibraryKit/Sources/LibraryKit/Listem/ListemModel.swift:157
  - loadContinue filters hiddenEpisodeIDs at line 153 (right after the first await) but writes continueItems only after two more awaits; a concurrent hideContinueItem in that window resurrects the hidden (tombstoned) item.
- ☐ **[AppFoundation/torn-token-write]** Packages/AppFoundation/Sources/AppFoundation/Session/TokenRefreshCoordinator.swift:117
  - performRefresh writes accessToken and refreshToken as two separate, non-atomic Keychain setString calls with no rollback; a failure of the second leaves a new access token paired with the OLD (already-rotated-away) refresh token.
- ☐ **[ProfileKit/concurrency-reentrancy]** Packages/ProfileKit/Sources/ProfileKit/BildirimMerkezi/NotificationCenterModel.swift:105
  - Eşzamanlı iki load()'ta erken biten BAYAT load'un `defer { isLoading = false }`'ı, hâlâ uçuşta olan taze load sırasında paylaşılan isLoading guard'ını sıfırlar → loadMore tam-replace load'un içine sızar (aktör-reentrancy invariantı bozulur).
- ☐ **[ProfileKit/reset-race]** Packages/ProfileKit/Sources/ProfileKit/Profil/ProfilModel.swift:83
  - load() iki AYRI await arasında (session.state → walletSummary.currentSummary()) hesap değişimine açıktır; hesap ve cüzdan farklı hesaplardan okunabilir (çapraz-hesap geçici tutarsızlık).
- ☐ **[ContentKit/clock-skew]** Packages/ContentKit/Sources/ContentKit/Models/BannerCollection.swift:26
  - Banner.isActive gates purely on device clock (.now) with no server-time correction, so device clock skew shows expired promo banners or hides active ones.
- ☐ **[DiscoverKit/pagination-termination]** Packages/DiscoverKit/Sources/DiscoverKit/Arama/AramaModel.swift:176
  - loadMore, sunucu boş sayfa fakat non-nil nextCursor döndürdüğünde sonlanmaz; en-alt hücrede tekrar tetiklenip sınırsız boş-sayfa çekme döngüsü oluşturabilir.
- ☐ **[LibraryKit/offline-list-consistency]** Packages/LibraryKit/Sources/LibraryKit/Listem/ListemModel.swift:152
  - loadContinue, hidden filtresini DB fetchLimit'ten SONRA uygular; gizlenen öğeler limiti tüketip listeyi mevcut öğeler varken bile kısaltır/erken boşaltır.
- ☐ **[AnalyticsKit/size-truncation]** Packages/AnalyticsKit/Sources/AnalyticsKit/Experiment/ExperimentEvents.swift:22
  - ABVariants.format produces an unbounded comma-joined string with no length cap; as active experiments accumulate it exceeds Firebase/GA4's 100-char string-parameter limit and is silently truncated.

