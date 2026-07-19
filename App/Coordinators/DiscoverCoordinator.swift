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

    /// Keşfet stack'i (Arama/DiziDetay push hedefleri `AppRoute`).
    var path = NavigationPath()

    /// Arama tekrar-önleme durumu: Arama push edildiğindeki stack derinliği. NavigationPath içeriği
    /// introspect edilemediğinden Arama'nın stack'te olup olmadığını bununla izleriz. `nil` → Arama
    /// yok. Sistem geri (edge-swipe) Arama'yı pop edince `path.count` bu derinliğin altına düşer;
    /// `showSearch` bunu tembel uzlaştırır (aksi halde bayrak eskir, tekrar açılmaz).
    @ObservationIgnored private var searchStackDepth: Int?

    /// Oturum-içi filtre kalıcılığı: Kesfet modeli sekme ömrünce tek instance (tür çipi seçimi
    /// stack derinliklerinden geri dönünce korunur).
    @ObservationIgnored private let session = DiscoverSessionStore()
    @ObservationIgnored private(set) lazy var kesfetModel: KesfetModel =
        composition.makeKesfetModel(session: session, delegate: self)

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
    }

    // MARK: - Deep link / cross-tab yardımcıları (TabCoordinator.handle çağırır)

    func showDetail(_ seriesID: SeriesID, source: DiziDetaySource) {
        path.append(AppRoute.diziDetay(seriesID: seriesID, source: source))
    }

    /// Arama'yı push eder — zaten stack'teyse TEKRAR ETMEZ (çift Arama bug'ı). `query` doluysa Arama
    /// ön-doldurulmuş sonuç modunda açılır (02 §8.2 `search?q=`).
    func showSearch(query: String? = nil) {
        // Uzlaştırma: kayıtlı Arama frame'i sistem-geri ile pop edildiyse (path.count derinliğin
        // altında) bayrağı temizle → yeniden açılabilir.
        if let depth = searchStackDepth, path.count < depth {
            searchStackDepth = nil
        }
        guard searchStackDepth == nil else { return } // Arama zaten açık → tekrar push etme
        path.append(AppRoute.arama(query: query))
        searchStackDepth = path.count
    }

    func applyGenre(_ genre: String?) {
        path = NavigationPath() // filtre için köke dön (02 §4.10 çip filtresi kökte)
        searchStackDepth = nil // stack köke sıfırlandı → Arama artık yok
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
        if !path.isEmpty {
            path.removeLast()
        }
        searchStackDepth = nil // Arama kapandı → bayrağı temizle (yeniden açılabilir)
    }
}

// DiziDetayDelegate stack-bağımsızdır ve TabCoordinator'da merkezîdir (oynat/unlock/paylaş/Keşfet
// hiçbiri Keşfet stack'ine push etmez) — burada tekrarlanmaz.
