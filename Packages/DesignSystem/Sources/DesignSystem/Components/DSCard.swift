import SwiftUI

/// Yüzey konteyneri — raf kartları ve OdulMerkezi kartlarının tabanı.
public struct DSCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(padding: CGFloat = DSSpacing.l, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(DSColors.surfaceElevated, in: RoundedRectangle(cornerRadius: DSRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.card)
                    .strokeBorder(DSColors.borderSubtle, lineWidth: DSStroke.hairline)
            }
    }
}
