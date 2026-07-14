import AppFoundation

/// Tasarım kararı (SS-092): WalletKit KENDİ `WalletError`'ını YENİDEN TANIMLAMAZ. Kanonik
/// cüzdan hata tipi `AppFoundation.WalletError`'dır ve zaten `AppError.wallet(...)` ile katman
/// sınırından geçen TEK hata tipine (03 §10.1) gömülüdür. İkinci bir `WalletError` tanımlamak
/// hem "tek hata tipi" mimarisini bozar hem de import ambiguity üretir. Bu dosya onun yerine
/// StoreKit satın alma sonuçlarını kanonik `WalletError`'a çeviren yardımcıları taşır.
public extension WalletError {
    /// Satın alma akışında iptal/pending/doğrulama-hatası → tipli cüzdan hatası.
    static func purchase(_ status: StoreKitStatus) -> WalletError {
        .purchaseFailed(status)
    }
}

extension PurchaseResult {
    /// Başarısız (success olmayan) satın alma sonucunu `StoreKitStatus`'a indirger.
    var failureStatus: StoreKitStatus? {
        switch self {
        case .success:
            nil
        case .userCancelled:
            .userCancelled
        case .pending:
            .pending
        }
    }
}
