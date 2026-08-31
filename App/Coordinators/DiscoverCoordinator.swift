import AppFoundation
import ContentKit
import DiscoverKit
import Foundation
import Observation
import SwiftUI

/// Keşfet koordinatörü (03 §3.1): `Kesfet → Arama → DiziDetay` push zinciri. DiscoverKit'in üç
/// delegate'ini (Kesfet/Arama/DiziDetay) burada karşılar; kilitli bölüm/deep link niyetlerini
/// WalletFlow ve TabCoordinator'a delege eder (R2 — DiscoverKit WalletKit/PlayerKit'i import etmez).
@Observable
@MainActor
final class DiscoverCoordinator {
    private let composition: AppComposition
    private let walletFlow: WalletFlowCoordinator
    weak var tabCoordinator: TabCoordinator?

    /// Keşfet stack'i — tipli `[AppRoute]` (ProfileCoordinator deseni). NavigationPath element-peek
    /// EDİLEMEDİĞİNDEN idempotency/query-forward derinlik-heuristiğiyle KIRILGANDI (sistem-geri path'i
    /// dışarıdan mutate eder → bayat marker → dead-tap/çoğaltma/yıkıcı-pop, self-review3). `[AppRoute]`
    /// gerçek `path.last` peek'iyle bunları kökten çözer; sistem-geri dizide DOĞRUDAN yansır.
    var path: [AppRoute] = []

    /// Oturum-içi filtre kalıcılığı: Kesfet modeli sekme ömrünce tek instance (tür çipi seçimi
    /// stack derinliklerinden geri dönünce korunur).
    @ObservationIgnored private let session = DiscoverSessionStore()
    @ObservationIgnored private(set) lazy var kesfetModel: KesfetModel =
        composition.makeKesfetModel(session: session, delegate: self)

    /// Hesap değişimi gözlemcisi — app ömrü boyunca canlı (Home/Rewards/Library ile simetrik): switch hangi
    /// sekmede olursa olsun (Profil'den) yakalanır.
    @ObservationIgnored private var accountObserver: Task<Void, Never>?

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
        startObservingAccountSwitch()
    }

    /// Hesap DEĞİŞİMİNDE (userID farklı bir hesaba geçince) uzun-ömürlü Kesfet oturum-durumunu (per-user
    /// `/discover` cache'i + tür filtresi) sıfırlar — model + session sekme ömrü boyu yaşar, switch'te yeniden
    /// yaratılmaz → cross-account state B'ye sızmasın (SS-132; Home/Rewards/Library ile simetrik). link
    /// (guest→AYNI userID) ve session-death/re-auth (nil-geçiş) reset TETİKLEMEZ; yalnız farklı-hesaba geçiş.
    private func startObservingAccountSwitch() {
        let sessionManaging = composition.dependencies.session
        accountObserver = Task { [weak self] in
            var lastUserID: String?
            for await state in sessionManaging.stateUpdates {
                // lastUserID YALNIZ non-nil'de güncellenir → nil-ara-durumdan (loggedOut) geçen switch yakalanır.
                guard let current = state.userID else { continue }
                if let previous = lastUserID, previous != current {
                    self?.kesfetModel.resetForAccountSwitch()
                }
                lastUserID = current
            }
        }
    }

    // MARK: - Deep link / cross-tab yardımcıları (TabCoordinator.handle çağırır)

    func showDetail(_ seriesID: SeriesID, source: DiziDetaySource) {
        // Idempotent (audit LOW): aynı dizi ZATEN tepedeyse özdeş DiziDetay'ı ÇOĞALTMA (deep-link/çift-tap).
        // Kimlik = seriesID (aynı ekran; source nav-dedup'ını etkilemez). Gerçek peek → bayat-marker yok.
        if case let .diziDetay(topID, _) = path.last, topID == seriesID {
            return
        }
        path.append(.diziDetay(seriesID: seriesID, source: source))
    }

    /// Arama'yı push eder — zaten stack'teyse TEKRAR ETMEZ (çift Arama bug'ı). `query` doluysa Arama
    /// ön-doldurulmuş sonuç modunda açılır (02 §8.2 `search?q=`).
    func showSearch(query: String? = nil) {
        // Arama stack'te mi? ([AppRoute] element-peek edilebilir → gerçek durum, derinlik-heuristiği yok.)
        if let aramaIndex = path.lastIndex(where: {
            if case .arama = $0 {
                true
            } else {
                false
            }
        }) {
            // Arama zaten açık. Yeni query (universal-link search?q=) geldiyse Arama frame'ini (ve üstündeki
            // DiziDetay'ları) query'li Arama ile DEĞİŞTİR (ön-doldurma); query yoksa no-op (çift-Arama önleme).
            guard let query, !query.isEmpty else { return }
            path.removeSubrange(aramaIndex...)
            path.append(.arama(query: query))
            return
        }
        path.append(.arama(query: query))
    }

    func applyGenre(_ genre: String?) {
        path = [] // filtre için köke dön (02 §4.10 çip filtresi kökte)
        kesfetModel.selectGenre(genre?.isEmpty == true ? nil : genre)
    }

    // MARK: - Push hedefi kurulumu (RootTabView navigationDestination'ı buraya delege eder)

    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case let .diziDetay(seriesID, source):
            // DiziDetay niyetleri stack-bağımsızdır (oynat/unlock/paylaş/Keşfet) → delegate TabCoordinator.
            DiziDetayView(model: composition.makeDiziDetayModel(seriesID: seriesID, source: source, delegate: tabCoordinator))
        case let .arama(query):
            AramaView(model: composition.makeAramaModel(delegate: self, source: .kesfet, initialQuery: query))
        case .ayarlar, .bildirimMerkezi:
            EmptyView() // Ayarlar/BildirimMerkezi Keşfet stack'inde push edilmez (Profil stack'i).
        }
    }
}

// MARK: - KesfetDelegate (02 §4.10)

extension DiscoverCoordinator: KesfetDelegate {
    func kesfetDidSelectSeries(_ seriesID: SeriesID, shelfID _: String?) {
        showDetail(seriesID, source: .kesfet)
    }

    func kesfetDidOpenRoute(_ route: DeepLinkRoute) {
        // Banner action'ı çözülmüş rota (dizi/koleksiyon veya kampanya deep link'i) → merkezi router.
        tabCoordinator?.handle(route)
    }

    func kesfetRequestsSearch() {
        showSearch() // dedup + bayrak tek yerden (doğrudan append çift Arama riski taşır)
    }

    func kesfetDidSelectSeeAll(collectionID _: String, title _: String) {
        // TODO(02 §4.10): raf "Tümü" → dikey ızgara sayfası — DiscoverKit'te public grid view yok (F1).
    }
}

// MARK: - AramaDelegate (02 §4.11)

extension DiscoverCoordinator: AramaDelegate {
    func aramaDidSelectSeries(_ seriesID: SeriesID) {
        showDetail(seriesID, source: .arama)
    }

    func aramaRequestsDismiss() {
        // Arama frame'ini pop et (stack'in tepesindedir). [AppRoute] → gerçek durum, ayrı bayrak yok.
        if !path.isEmpty {
            path.removeLast()
        }
    }
}

// DiziDetayDelegate stack-bağımsızdır ve TabCoordinator'da merkezîdir (oynat/unlock/paylaş/Keşfet
// hiçbiri Keşfet stack'ine push etmez) — burada tekrarlanmaz.
