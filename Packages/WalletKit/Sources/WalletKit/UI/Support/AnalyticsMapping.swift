import AppFoundation

/// `AppError` → analitik parametre eşlemesi (08 §3.4 `coin_purchase_fail`/`subscription_fail`
/// `error_domain`/`error_code`, `unlock_failed` `reason`). Tek yerde: UI modelleri aynı kaba
/// sınıflandırmayı paylaşır.
enum AnalyticsMapping {
    /// Kaba tek etiketli sebep (`unlock_failed.reason`).
    static func reason(_ error: AppError) -> String {
        domainCode(error).code
    }

    /// `(error_domain, error_code)` — teknik ayrıntı loglanır, analitikte kaba tutulur.
    static func domainCode(_ error: AppError) -> (domain: String, code: String) {
        switch error {
        case let .network(network):
            switch network {
            case .offline: ("network", "offline")
            case .timeout: ("network", "timeout")
            case let .server(status): ("network", "server_\(status)")
            case .decoding: ("network", "decoding")
            }
        case let .wallet(wallet):
            ("wallet", walletCode(wallet))
        case .auth:
            ("auth", "auth")
        case .storage:
            ("storage", "storage")
        case let .featureDisabled(flag):
            ("feature", flag)
        default:
            ("unexpected", "unexpected")
        }
    }

    private static func walletCode(_ error: WalletError) -> String {
        switch error {
        case .insufficientCoins: "insufficient_coins"
        case .priceChanged: "price_changed"
        case .receiptAlreadyProcessed: "already_processed"
        case .receiptInvalid: "receipt_invalid"
        case let .purchaseFailed(status): "purchase_\(status.rawValue)"
        case .receiptValidationFailed: "validation_failed"
        case .transactionConflict: "conflict"
        @unknown default: "wallet"
        }
    }
}
