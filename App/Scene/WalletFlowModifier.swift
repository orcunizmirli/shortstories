import SwiftUI
import WalletKit

extension View {
    /// Çapraz monetizasyon sheet'lerini (UnlockSheet/CoinMagazasi/VIPAbonelik) kök seviyede sunar.
    /// `WalletFlowCoordinator` her sekmeden çağrılabildiği için tek noktadan (RootTabView) uygulanır.
    func walletFlow(_ coordinator: WalletFlowCoordinator) -> some View {
        modifier(WalletFlowModifier(coordinator: coordinator))
    }
}

/// UnlockSheet → (sheet-içi) CoinMagazasi/VIPAbonelik sunum köprüsü (02 §4.6/§5.3). Coin/VIP,
/// UnlockSheet açıkken onun ÜZERİNE (sheet-içi push davranışı), değilse doğrudan kökten sunulur.
private struct WalletFlowModifier: ViewModifier {
    @Bindable var coordinator: WalletFlowCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: unlockBinding) {
                if let model = coordinator.unlockModel {
                    UnlockSheetView(model: model)
                        .presentationDetents([.height(460), .large])
                        // Coin/VIP UnlockSheet üzerine (sheet-içi push):
                        .sheet(isPresented: childCoinBinding) { coinSheet }
                        .sheet(isPresented: childVIPBinding) { vipSheet }
                }
            }
            // Standalone (UnlockSheet yokken — Profil/Ödüller/deep link):
            .sheet(isPresented: standaloneCoinBinding) { coinSheet }
            .sheet(isPresented: standaloneVIPBinding) { vipSheet }
    }

    // MARK: - Sheet içerikleri

    @ViewBuilder private var coinSheet: some View {
        if let model = coordinator.coinShopModel {
            CoinShopView(model: model)
                .presentationDetents([.large])
        }
    }

    @ViewBuilder private var vipSheet: some View {
        if let model = coordinator.vipModel {
            VIPSubscriptionView(model: model)
                .presentationDetents([.large])
        }
    }

    // MARK: - Sunum binding'leri (kapatma → koordinatör delege niyeti)

    private var unlockBinding: Binding<Bool> {
        Binding(
            get: { coordinator.unlockModel != nil },
            set: {
                if !$0 {
                    coordinator.unlockSheetDidDismiss()
                }
            }
        )
    }

    private var childCoinBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isCoinStoreChildOfUnlock },
            set: {
                if !$0 {
                    coordinator.coinShopRequestsDismiss()
                }
            }
        )
    }

    private var standaloneCoinBinding: Binding<Bool> {
        Binding(
            get: { coordinator.coinShopModel != nil && coordinator.unlockModel == nil },
            set: {
                if !$0 {
                    coordinator.coinShopRequestsDismiss()
                }
            }
        )
    }

    private var childVIPBinding: Binding<Bool> {
        Binding(
            get: { coordinator.isVIPChildOfUnlock },
            set: {
                if !$0 {
                    coordinator.vipSubscriptionRequestsDismiss()
                }
            }
        )
    }

    private var standaloneVIPBinding: Binding<Bool> {
        Binding(
            get: { coordinator.vipModel != nil && coordinator.unlockModel == nil },
            set: {
                if !$0 {
                    coordinator.vipSubscriptionRequestsDismiss()
                }
            }
        )
    }
}
