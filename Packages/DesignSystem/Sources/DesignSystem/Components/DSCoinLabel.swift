import SwiftUI

/// Coin miktarı etiketi: coinGold ikon + biçimlenmiş sayı. OdulMerkezi
/// bakiye kartı, CoinMagazasi ve UnlockSheet'in ortak yapı taşı.
public struct DSCoinLabel: View {
    public enum Size: Sendable {
        /// Satır içi kullanım (UnlockSheet bakiye satırı vb.).
        case regular
        /// Büyük bakiye gösterimi (OdulMerkezi bakiye kartı).
        case large
    }

    private let amount: Int
    private let size: Size

    public init(amount: Int, size: Size = .regular) {
        self.amount = amount
        self.size = size
    }

    /// Negatif miktarı 0'a kırpar, binlik ayraçla biçimler (test kancası).
    /// Cüzdan bakiyesi hiçbir zaman negatif gösterilmez.
    static func formattedAmount(_ amount: Int, locale: Locale = .current) -> String {
        let clamped = max(0, amount)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: clamped)) ?? "\(clamped)"
    }

    public var body: some View {
        HStack(spacing: size == .large ? DSSpacing.s : DSSpacing.xs) {
            // SS-014 özel coin ikonu gelene dek SF Symbols placeholder'ı.
            Image(systemName: "dollarsign.circle.fill")
                .foregroundStyle(DSColors.coinGold)
            Text(verbatim: Self.formattedAmount(amount))
                .foregroundStyle(DSColors.textPrimary)
                .monospacedDigit()
        }
        .font(size == .large ? DSTypography.display : DSTypography.bodyEmphasized)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(max(0, amount)) coin")
    }
}
