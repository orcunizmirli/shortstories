import AppFoundation
import ContentKit
import Foundation
import Testing
@testable import PlayerKit

/// `FeedCellBindPolicy` testleri (bulgu 4/6): aktif lease'in hücreye bağlanma kararı
/// ham indeksle DEĞİL bölüm-id ile verilir — snapshot kayması yanlış karta bağlamaz,
/// ekran dışına çıkıp dönen aktif hücre yeniden bağlanır.
struct FeedCellBindPolicyTests {
    private let active = EpisodeID("e5")

    @Test("Ekran dışına çıkıp dönen AKTİF hücre yeniden bağlanır (siyah kare+ses önlenir)")
    func returningActiveCellRebinds() {
        // Bulgu 6: hücre unbind oldu (boundEpisodeID = nil), aynı bölüm-id ile geri döndü.
        let shouldBind = FeedCellBindPolicy.shouldBindActiveHandle(
            cellEpisodeID: active,
            cellBoundEpisodeID: nil,
            activeEpisodeID: active
        )
        #expect(shouldBind)
    }

    @Test("Zaten aktif bölüme bağlı hücre yeniden bağlanmaz (idempotans)")
    func alreadyBoundActiveCellDoesNotRebind() {
        let shouldBind = FeedCellBindPolicy.shouldBindActiveHandle(
            cellEpisodeID: active,
            cellBoundEpisodeID: active,
            activeEpisodeID: active
        )
        #expect(!shouldBind)
    }

    @Test("Bölüm-id uyuşmayan hücreye aktif handle bağlanmaz (yanlış karta sızma yok)")
    func mismatchedEpisodeDoesNotBind() {
        // Bulgu 4: snapshot kayması sonrası bu koleksiyon indeksinde FARKLI bölüm var.
        let shouldBind = FeedCellBindPolicy.shouldBindActiveHandle(
            cellEpisodeID: EpisodeID("e9"),
            cellBoundEpisodeID: nil,
            activeEpisodeID: active
        )
        #expect(!shouldBind)
    }

    @Test("Bölüm taşımayan hücre (episode nil) aktif handle bağlamaz")
    func nilEpisodeCellDoesNotBind() {
        let shouldBind = FeedCellBindPolicy.shouldBindActiveHandle(
            cellEpisodeID: nil,
            cellBoundEpisodeID: nil,
            activeEpisodeID: active
        )
        #expect(!shouldBind)
    }

    @Test("Aktif bağlama yoksa hiçbir hücre bağlanmaz")
    func noActiveBindingBindsNothing() {
        let shouldBind = FeedCellBindPolicy.shouldBindActiveHandle(
            cellEpisodeID: active,
            cellBoundEpisodeID: nil,
            activeEpisodeID: nil
        )
        #expect(!shouldBind)
    }
}
