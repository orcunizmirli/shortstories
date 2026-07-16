import Foundation
import Observation
import SwiftUI

/// Paylaşım sheet sunum durumu (SS-063/SS-083). Koordinatör universal link'i üretir ve buraya
/// yazar; sahip sekme view'ı `.shareSheet(_:)` modifier'ıyla `UIActivityViewController`'ı sunar.
/// Feature'lar paylaşımı bilmez — yalnız `...Share`/`...didRequestShare` niyeti üretir (02 §8.1.1).
@Observable
@MainActor
final class SharePresenter {
    /// Non-nil olunca paylaşım sheet'i sunulur; kapanınca App nil'e çeker.
    var shareURL: URL?

    func share(_ url: URL) {
        shareURL = url
    }
}

extension View {
    /// Paylaşım sunum köprüsü — `presenter.shareURL` non-nil olunca sistem paylaşım sheet'i açılır.
    func shareSheet(_ presenter: SharePresenter) -> some View {
        modifier(ShareSheetModifier(presenter: presenter))
    }
}

private struct ShareSheetModifier: ViewModifier {
    @Bindable var presenter: SharePresenter

    func body(content: Content) -> some View {
        content.sheet(isPresented: presentBinding) {
            if let url = presenter.shareURL {
                ActivityView(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var presentBinding: Binding<Bool> {
        Binding(
            get: { presenter.shareURL != nil },
            set: {
                if !$0 {
                    presenter.shareURL = nil
                }
            }
        )
    }
}

/// `UIActivityViewController` SwiftUI köprüsü (paylaşım — 02 §4.4/§8.1.1).
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
