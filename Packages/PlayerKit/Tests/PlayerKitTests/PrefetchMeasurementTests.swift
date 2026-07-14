import AppFoundation
import Foundation
import Testing
@testable import PlayerKit

// MARK: - Prefetch bayt/süre ölçüm kancası (SS-047 devri; tam ağ sayacı SS-041)

@Suite("PrefetchController — ölçüm kancası")
struct PrefetchMeasurementTests {
    private func makeController(
        warmer: RecordingWarmer,
        measurer: RecordingPrefetchMeasurer
    ) -> PrefetchController {
        PrefetchController(
            warmer: warmer,
            network: FakeNetworkProvider(.wifi),
            preferences: FakePreferences(),
            poolSize: 3,
            measurer: measurer
        )
    }

    @Test("Tamamlanan ısındırma bütçe yaklaşığıyla kaydedilir (~500 KB / 2 sn)")
    func completedWarmupIsMeasured() async {
        let warmer = RecordingWarmer()
        let measurer = RecordingPrefetchMeasurer()
        let controller = makeController(warmer: warmer, measurer: measurer)
        let episodes = Fixture.episodes(count: 3)

        await controller.windowChanged(activeIndex: 0, episodes: episodes, direction: .forward)
        await controller.awaitPendingWarmups()

        let recorded = await eventually { measurer.records.count == 1 }
        #expect(recorded)
        let record = measurer.records.first
        #expect(record?.episodeID == EpisodeID("e1"))
        #expect(record?.approximateBytes == PrefetchBudget.standard.maxBytes)
        #expect(record?.approximateSeconds == PrefetchBudget.standard.maxSeconds)
    }

    @Test("İptal edilen ısındırma ölçüm KAYDETMEZ")
    func cancelledWarmupIsNotMeasured() async {
        let warmer = RecordingWarmer()
        warmer.setDelay(nanoseconds: 200_000_000)
        let measurer = RecordingPrefetchMeasurer()
        let controller = makeController(warmer: warmer, measurer: measurer)
        let episodes = Fixture.episodes(count: 3)

        await controller.windowChanged(activeIndex: 0, episodes: episodes, direction: .forward)
        await controller.cancelAll()
        await controller.awaitPendingWarmups()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(measurer.records.isEmpty)
    }
}
