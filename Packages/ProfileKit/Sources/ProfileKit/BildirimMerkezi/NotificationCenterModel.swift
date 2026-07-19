import AppFoundation
import Observation

/// `BildirimMerkezi` ekran modeli (SS-144; NTF-04, 02 §4.15). @Observable/@MainActor; SwiftUI View
/// ince kalır. Cursor sayfalı bildirim listesi (05 §7.1), okunmamış rozeti türevi, "tümünü okundu
/// say", sola-kaydır sil ve offline→cache+banner durum makinesini yönetir.
///
/// KURALLAR: DiscoverKit/Route enum'u İMPORT EDİLMEZ — rota ham String, çözüm App'te (R2). Coin/
/// hesap/bakiye MUTASYONU YOK (yalnız bildirim durum mutasyonu). Mutasyonlar OPTİMİSTİKtir: yerel
/// durum anında çevrilir, gateway hatasında telafi ile geri alınır (FavoritesService optimistik
/// yazma + telafi deseni).
@MainActor
@Observable
public final class NotificationCenterModel {
    /// Ana yükleme durumu (02 §4.15 durum tablosu): boş / yükleniyor-skeleton / hata-offline-cache.
    /// Cache gösterilirken revalidasyon başarısız olursa liste KORUNUR (`errorWithCache`), offline'da
    /// banner yükselir. `errorWithCache` boş cache'te de geçerlidir (View o hâlde tam-ekran offline/
    /// hata gösterir; ProfileKit ayrı bir "cache'siz hata" durumu tutmaz).
    public enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case emptyLoaded
        case errorWithCache
    }

    // MARK: - Durum (Observable)

    public private(set) var loadState: LoadState = .idle
    /// Bildirim listesi (en yeni önce; sunucu sıralar). Sayfalar `loadMore` ile eklenir (id'ye göre
    /// dedup). Mutasyonlar (okundu/sil) bunun üzerinde optimistik yürür.
    public private(set) var notifications: [AppNotification] = []
    /// Offline/hata nedeniyle bayat cache gösteriliyor → offline banner (02 §4.15 + §3 banner kuralı).
    public private(set) var showsOfflineBanner = false
    /// Sonraki sayfa isteği uçuşta mı (View footer spinner'ı; çift `loadMore` guard'ı).
    public private(set) var isLoadingMore = false

    // MARK: - Bağımlılıklar

    private let gateway: any NotificationsGateway
    private let analytics: any AnalyticsTracking
    private weak var delegate: (any NotificationCenterDelegate)?

    private var nextCursor: String?
    private var didTrackOpen = false
    private var loadTask: Task<Void, Never>?
    /// Sayfa isteklerinin kuşak jetonu — eşzamanlı `load`/`loadMore` sıra-dışı tamamlanınca geç
    /// dönen bayat yanıt taze durumu EZMESİN (en son BAŞLAYAN istek kazanır; AramaModel deseni).
    private var loadGeneration = 0
    /// Tam-replace `load` uçuşta mı (aktör-reentrancy guard'ı). `loadMore` bunu görürse başlamaz;
    /// AramaModel `isLoadingResults` deseni — replace vs paginate doğru ayrımı (F1).
    private var isLoading = false
    /// Authoritative listeyi (başarılı `load` tam-replace) her tazeleyişte artan çağ jetonu. Optimistik
    /// mutasyonlar `await` ÖNCESİ bunu yakalar; telafi ancak jeton hâlâ eşleşiyorsa uygulanır — araya
    /// giren bir `load` KAZANIR, bayat anlık görüntüye dayalı telafi ATILIR (F2/F3/F5).
    private var listEpoch = 0
    /// Başarıyla silinmiş ama sunucunun bayat bir sayfada hâlâ döndürebileceği kimlikler (mezar taşı).
    /// `load`/`appendPage` sayfa öğelerini bununla filtreler → başarıyla silinen öğe DİRİLMEZ (F5).
    /// Sunucu artık döndürmediğinde (başarılı load sonrası) mezar taşı temizlenir.
    private var pendingDeletedIDs: Set<NotificationID> = []

    public init(
        gateway: any NotificationsGateway,
        analytics: any AnalyticsTracking,
        delegate: (any NotificationCenterDelegate)?
    ) {
        self.gateway = gateway
        self.analytics = analytics
        self.delegate = delegate
    }

    // MARK: - Türevler

    /// Okunmamış bildirim sayısı — Profil girişindeki rozet + `notification_center_opened` bunu okur.
    /// @Observable grafiğinde `notifications`'tan türer (ayrı state tutulmaz → tutarsızlık olmaz).
    public var unreadCount: Int {
        notifications.reduce(0) { $0 + ($1.isRead ? 0 : 1) }
    }

    /// Sonraki sayfa var mı (View son hücrede `loadMore` tetikler).
    public var canLoadMore: Bool {
        nextCursor != nil
    }

    // MARK: - Yaşam döngüsü

    public func onAppear() {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in await self?.load() }
    }

    /// Testler için: askıdaki ilk yükleme görevini bekler (deterministik).
    func pendingWork() async {
        await loadTask?.value
    }

    // MARK: - Yükleme (ilk sayfa / yenile / retry)

    /// İlk sayfa (cursor'suz). Cache yoksa skeleton (`.loading`); cache varsa yenilerken cache'i
    /// KORUR (bayat-önce-göster). "Tekrar Dene" de bunu çağırır (retry). Boş sayfa → `.emptyLoaded`.
    public func load() async {
        loadGeneration += 1
        let token = loadGeneration
        isLoading = true
        defer { isLoading = false }
        if notifications.isEmpty {
            loadState = .loading
        }
        do {
            let page = try await gateway.fetch(cursor: nil)
            guard token == loadGeneration else { return } // üstü örtüldü: bayat yazma yok
            // Mezar taşlarını sunucunun HÂLÂ döndürdükleriyle sınırla (artık dönmeyen → silme yayıldı,
            // temizle); sonra sayfayı filtrele → başarıyla silinen öğe bayat snapshot'la dirilmez (F5).
            pendingDeletedIDs.formIntersection(page.items.map(\.id))
            let items = page.items.filter { !pendingDeletedIDs.contains($0.id) }
            notifications = items
            listEpoch += 1 // authoritative replace: uçuştaki optimistik telafileri geçersizle (F2/F3)
            nextCursor = page.nextCursor
            showsOfflineBanner = false
            loadState = items.isEmpty ? .emptyLoaded : .loaded
            trackOpenedIfNeeded()
        } catch let error as AppError {
            guard token == loadGeneration else { return }
            handleLoadError(error)
        } catch {
            guard token == loadGeneration else { return }
            handleLoadError(.unexpected(underlying: String(describing: error)))
        }
    }

    /// Sonsuz scroll sonraki sayfa (cursor sayfalama, 05 §7.1). Yeni sayfa mevcut listeye eklenir,
    /// id'ye göre DEDUP edilir (sunucu örtüşen sayfa dönerse tekrar satır olmaz).
    public func loadMore() async {
        // `!isLoading`: uçuştaki bir tam-replace load, pagination'ı BLOKLAR (bayat listeye ekleme yok).
        // Jetonu ARTIRMAZ, yalnız YAKALAR: sonradan başlayan bir load pagination'ı geçersizler (F1;
        // AramaModel deseni birebir).
        guard let cursor = nextCursor, !isLoadingMore, !isLoading else { return }
        let token = loadGeneration
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await gateway.fetch(cursor: cursor)
            guard token == loadGeneration else { return }
            appendPage(page)
        } catch let error as AppError {
            guard token == loadGeneration else { return }
            // loadMore hatası mevcut listeyi YIKMAZ; yalnız offline banner (varsa) + cursor korunur
            // (retry mümkün). Non-offline geçici hatada banner yükselmez (sessiz; kullanıcı tekrar dener).
            showsOfflineBanner = (error == .network(.offline))
        } catch {
            guard token == loadGeneration else { return }
        }
    }

    /// Sayfayı id'ye göre dedup ederek ekler; boş→dolu geçişinde durumu düzeltir.
    private func appendPage(_ page: NotificationsPage) {
        let existingIDs = Set(notifications.map(\.id))
        // Mevcut id'ye göre dedup + başarıyla silinmiş mezar taşlarını ele (F5): sayfalama silinen
        // öğeyi geri getirmesin. Mezar taşı temizliği yalnız authoritative `load`'a aittir.
        notifications += page.items.filter { !existingIDs.contains($0.id) && !pendingDeletedIDs.contains($0.id) }
        nextCursor = page.nextCursor
        showsOfflineBanner = false
        if loadState == .emptyLoaded, !notifications.isEmpty {
            loadState = .loaded
        }
    }

    /// Hata politikası (02 §4.15): cache (varsa) KORUNUR, `errorWithCache`'e geçilir; offline'da
    /// banner yükselir. Cache boşsa View bunu tam-ekran offline/hata olarak boyar.
    private func handleLoadError(_ error: AppError) {
        showsOfflineBanner = (error == .network(.offline))
        loadState = .errorWithCache
        trackOpenedIfNeeded()
    }

    // MARK: - Durum mutasyonları (optimistik + telafi; coin/hesap mutasyonu YOK)

    /// "Tümünü okundu say" (02 §4.15). Optimistik: hepsini anında okundu çevirir; gateway hatasında
    /// her öğenin ÖNCEKİ okunma durumunu (hâlâ listede olanlar için) geri yükler (telafi) — böylece
    /// await sırasında silinen öğe DİRİLMEZ.
    public func markAllRead() async {
        guard notifications.contains(where: { !$0.isRead }) else { return } // hepsi okundu → no-op
        let previousReadByID = Dictionary(
            notifications.map { ($0.id, $0.isRead) },
            uniquingKeysWith: { first, _ in first }
        )
        notifications = notifications.map { $0.withRead(true) }
        let epoch = listEpoch
        do {
            try await gateway.markAllRead()
        } catch {
            guard epoch == listEpoch else { return } // araya giren authoritative load kazandı (F3)
            notifications = notifications.map { $0.withRead(previousReadByID[$0.id] ?? $0.isRead) }
        }
    }

    /// Tek bildirimi okundu işaretle (satır okundu). Optimistik + telafi: hatada YALNIZ o öğe (hâlâ
    /// listedeyse) tekrar okunmamışa çevrilir.
    public func markRead(_ id: NotificationID) async {
        guard let index = notifications.firstIndex(where: { $0.id == id }),
              !notifications[index].isRead
        else { return }
        notifications[index] = notifications[index].withRead(true)
        let epoch = listEpoch
        do {
            try await gateway.markRead(ids: [id])
        } catch {
            guard epoch == listEpoch else { return } // araya giren authoritative load kazandı (F3)
            if let compensateIndex = notifications.firstIndex(where: { $0.id == id }) {
                notifications[compensateIndex] = notifications[compensateIndex].withRead(false)
            }
        }
    }

    /// Sola-kaydır → sil (02 §4.15). Optimistik: anında listeden çıkarır; gateway hatasında öğeyi
    /// ORİJİNAL konumuna geri ekler (telafi). Liste boşalırsa `.emptyLoaded`'a geçer, telafi geri alır.
    public func delete(_ id: NotificationID) async {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        let removed = notifications.remove(at: index)
        let previousLoadState = loadState
        // Son cache öğesi silinince boş-durum'a geç. `.errorWithCache` de dâhil (F4): aksi hâlde liste
        // boşalır ama state hata kalır → View tam-ekran hata boyar, "Henüz bildirimin yok" değil.
        if notifications.isEmpty, loadState == .loaded || loadState == .errorWithCache {
            loadState = .emptyLoaded
        }
        let epoch = listEpoch
        do {
            try await gateway.delete(id: id)
            // Başarı: mezar taşı ekle + araya giren bir load geri getirmişse idempotent çıkar (F5).
            pendingDeletedIDs.insert(id)
            notifications.removeAll { $0.id == id }
        } catch {
            guard epoch == listEpoch else { return } // araya giren authoritative load kazandı (F2)
            guard !notifications.contains(where: { $0.id == id }) else { return } // dedup: yineleme yok
            notifications.insert(removed, at: min(index, notifications.count)) // konum clamp'li
            loadState = previousLoadState // silme-öncesi duruma tam dön (F4 telafisi)
        }
    }

    // MARK: - Satır dokunuşu (navigasyon niyeti → delegate)

    /// Satır dokunuşu (02 §4.15). Rota push ile AYNI deep link'tir (NTF-04): dolu route → App çözer;
    /// YAPISAL geçersiz (boş) route → doğrudan `Kesfet` fallback'ine işaretlenir (§8.4). Okundu-
    /// çevirme AYRI `markRead` çağrısıdır (çağıran yürütür) — bu niyet yalnız route sınıflandırır +
    /// analitik atar.
    public func open(_ notification: AppNotification) {
        analytics.track(
            "notification_item_tapped",
            parameters: [
                "type": .string(notification.type.rawValue),
                "route": .string(notification.route)
            ]
        )
        if notification.hasRoute {
            delegate?.notificationCenterOpensRoute(notification.route)
        } else {
            delegate?.notificationCenterFallsBackToDiscover()
        }
    }

    // MARK: - İç (analitik, 02 §4.15)

    /// İlk yükleme çözülünce (loaded/emptyLoaded/errorWithCache) BİR kez `notification_center_opened`
    /// atar — okunmamış sayısı türevden okunur (05 §13 rozet).
    private func trackOpenedIfNeeded() {
        guard !didTrackOpen else { return }
        didTrackOpen = true
        analytics.track(
            "notification_center_opened",
            parameters: ["unread_count": .int(unreadCount)]
        )
    }
}
