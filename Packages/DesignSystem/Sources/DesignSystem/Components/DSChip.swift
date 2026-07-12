import SwiftUI

/// Tür filtresi / etiket chip'i (Kesfet filtreleri, Onboarding tür seçimi).
/// Her zaman kapsül biçimlidir (DSRadius.chip sözleşmesi).
public struct DSChip: View {

    private let title: LocalizedStringKey
    private let isSelected: Bool
    private let onTap: () -> Void

    public init(_ title: LocalizedStringKey, isSelected: Bool, onTap: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(isSelected ? DSTypography.captionEmphasized : DSTypography.caption)
                .foregroundStyle(isSelected ? .white : DSColors.textSecondary)
                .padding(.horizontal, DSSpacing.m)
                .padding(.vertical, DSSpacing.s)
                .background(isSelected ? DSColors.accent : DSColors.surfaceElevated, in: Capsule())
                .overlay {
                    if !isSelected {
                        Capsule()
                            .strokeBorder(DSColors.borderSubtle, lineWidth: DSStroke.hairline)
                    }
                }
        }
    }
}
