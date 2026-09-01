import Foundation
import Testing
@testable import AppFoundation

@Suite("AnalyticsRecorder")
struct AnalyticsRecorderTests {
    @Test("Kapasite aşılınca en eski olaylar düşer")
    func ringBufferEvictsOldest() async {
        let recorder = AnalyticsRecorder(capacity: 3)
        for index in 0 ..< 5 {
            await recorder.record("event_\(index)")
        }
        let names = await recorder.snapshot().map(\.name)
        #expect(names == ["event_2", "event_3", "event_4"])
    }

    @Test("Olaylar enjekte edilen saati kullanır")
    func usesInjectedClock() async {
        let clock = MutableDateProvider()
        let recorder = AnalyticsRecorder(dateProvider: clock)
        await recorder.record("first")
        clock.advance(by: 60)
        await recorder.record("second")

        let events = await recorder.snapshot()
        #expect(events.count == 2)
        #expect(events[1].timestamp.timeIntervalSince(events[0].timestamp) == 60)
    }

    @Test("Sıfırlama tamponu boşaltır")
    func resetClearsBuffer() async {
        let recorder = AnalyticsRecorder()
        await recorder.record("x")
        await recorder.reset()
        #expect(await recorder.snapshot().isEmpty)
    }
}
