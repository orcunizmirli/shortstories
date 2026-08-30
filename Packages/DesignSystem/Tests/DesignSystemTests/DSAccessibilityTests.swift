import SwiftUI
import Testing
@testable import DesignSystem

/// DesignSystem erişilebilirlik türetimleri (audit): VoiceOver kullanıcısı için durum/seçim sinyalleri.
/// SwiftUI a11y trait'leri (DSChip `.isSelected`) bu kurulumda (ViewInspector yok) unit-test edilemez;
/// burada test edilebilir a11y DEĞERLERİ (DSButton yükleme durumu) doğrulanır.
@MainActor
@Suite("DesignSystem erişilebilirlik")
struct DSAccessibilityTests {
    @Test func dsButtonYuklemeDurumuErisilebilirlikDegeriDuyurulur() {
        // Audit LOW: isLoading'de buton disabled + başlık gizli (opacity 0) + spinner etiketsiz →
        // VoiceOver yalnız "sönük" okur, "işleniyor mu / kalıcı devre dışı mı" ayırt edilemez. Yükleme
        // durumu erişilebilirlik DEĞERİYLE duyurulur (boşta nil → değer eklenmez).
        #expect(DSButton("Aç", isLoading: true, action: {}).accessibilityStatusLabel == "Yükleniyor")
        #expect(DSButton("Aç", isLoading: false, action: {}).accessibilityStatusLabel == nil)
    }
}
