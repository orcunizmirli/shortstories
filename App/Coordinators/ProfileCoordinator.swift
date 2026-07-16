import AppFoundation
import Foundation
import Observation
import ProfileKit
import SwiftUI
import UIKit

/// Profil koordinatörü (03 §3.1): `Profil → Ayarlar` push + hesap bağlama/silme sheet'leri. Dört
/// delegate'i (Profile/Settings/HesapBaglama/HesapSilme) karşılar; coin/VIP → WalletFlow, izleme
/// geçmişi → TabCoordinator (sekme değişimi), yasal/sistem link'leri → App URL çözümü.
@Observable
@MainActor
final class ProfileCoordinator {
    private let composition: AppComposition
    private let walletFlow: WalletFlowCoordinator
    weak var tabCoordinator: TabCoordinator?

    /// Profil stack'i — Ayarlar push hedefi (`AppRoute.ayarlar`).
    var path = NavigationPath()

    /// Sheet olarak sunulan hesap akışları (non-nil → sunulur).
    private(set) var hesapBaglamaModel: HesapBaglamaModel?
    private(set) var hesapSilmeModel: HesapSilmeModel?

    /// Profil modeli — oturum + cüzdan özeti + uygulama dili. `lazy`: delegate = self.
    @ObservationIgnored private(set) lazy var profilModel: ProfilModel =
        composition.makeProfilModel(delegate: self)

    init(composition: AppComposition, walletFlow: WalletFlowCoordinator) {
        self.composition = composition
        self.walletFlow = walletFlow
    }

    // MARK: - Cross-tab / deep link yardımcıları

    func showSettings() {
        path.append(AppRoute.ayarlar)
    }

    // MARK: - Sheet sunum durumu setter'ları (RootTabView okur)

    func dismissAccountSheets() {
        hesapBaglamaModel = nil
        hesapSilmeModel = nil
    }

    private func presentAccountLinking() {
        hesapBaglamaModel = composition.makeHesapBaglamaModel(
            anchor: { PresentationAnchorProvider.anchor() },
            delegate: self
        )
    }

    private func presentAccountDeletion() {
        hesapSilmeModel = composition.makeHesapSilmeModel(delegate: self)
    }

    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case .ayarlar:
            AyarlarView(model: composition.makeAyarlarModel(delegate: self))
        case .diziDetay, .arama:
            EmptyView() // Profil stack'inde bu hedefler push edilmez.
        }
    }
}

// MARK: - ProfileDelegate (02 §4.13)

extension ProfileCoordinator: ProfileDelegate {
    func profileRequestsAccountLinking() {
        presentAccountLinking()
    }

    func profileRequestsReauthentication(provider _: AuthProvider) {
        // F2: oturum düştü → yeniden giriş. F1'de bağlama akışını yeniden kullanırız (misafire dönülmez).
        presentAccountLinking()
    }

    func profileOpensCoinStore() {
        walletFlow.presentCoinStore(source: .profil)
    }

    func profileOpensVIP(isSubscribed _: Bool) {
        walletFlow.presentVIP(source: .profil)
    }

    func profileOpensWatchHistory() {
        // İzleme geçmişi → Listem/Devam Et segmenti (sekme değişimi, 02 §4.13).
        guard let tabCoordinator else { return }
        tabCoordinator.switchTab(.listem)
        tabCoordinator.library.selectSegment(.continueWatching)
    }

    func profileOpensSettings() {
        showSettings()
    }

    func profileOpensNotificationCenter() {
        // TODO(F2 / SS-144): BildirimMerkezi — satır flag ardında, ekran Faz 2.
    }

    func profileOpensSupport() {
        // TODO(02 §4.13.1 / SUP-XX): Destek/Yardım yüzeyi — ayrı task; şimdilik no-op.
    }
}

// MARK: - SettingsDelegate (02 §4.14)

extension ProfileCoordinator: SettingsDelegate {
    func settingsOpensAccountManagement() {
        presentAccountLinking()
    }

    func settingsRequestsSignOut() {
        // TODO(F2): `SessionManaging` protokolünde çıkış yok (mutasyon SessionManager'da); misafir
        // moduna dönüş akışı Faz 2 (02 §4.13). Cüzdan server'da, lokal veri cihazda kalır.
    }

    func settingsRequestsAccountDeletion() {
        presentAccountDeletion()
    }

    func settingsOpensLegalPage(_ page: LegalPage) {
        openURL(legalURL(page))
    }

    func settingsOpensSystemNotificationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private func legalURL(_ page: LegalPage) -> URL {
        let path = switch page {
        case .termsOfService: "/legal/terms"
        case .privacyPolicy: "/legal/privacy"
        case .eula: "/legal/eula"
        case .openSourceLicenses: "/legal/licenses"
        }
        return URL(string: "\(DeepLinkFactory.webHost)\(path)") ?? URL(string: DeepLinkFactory.webHost)!
    }

    private func openURL(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

// MARK: - HesapBaglamaDelegate (02 §4.13 hesap bağlama akışı)

extension ProfileCoordinator: HesapBaglamaDelegate {
    func hesapBaglamaDidLink(_: AccountSummary) {
        // Oturum bağlıya yükseldi → sheet kapanır; ProfilModel oturum yayınından kendini tazeler.
        hesapBaglamaModel = nil
    }

    func hesapBaglamaRequestsDismiss() {
        hesapBaglamaModel = nil
    }
}

// MARK: - HesapSilmeDelegate (02 §4.14 hesap silme)

extension ProfileCoordinator: HesapSilmeDelegate {
    func hesapSilmeDidComplete(_: AccountDeletionReceipt) {
        // TODO(F2): silme sonrası yeni misafir oturumu + köke dönüş (SessionManager mutasyonu).
        hesapSilmeModel = nil
    }

    func hesapSilmeRequestsDismiss() {
        hesapSilmeModel = nil
    }
}
