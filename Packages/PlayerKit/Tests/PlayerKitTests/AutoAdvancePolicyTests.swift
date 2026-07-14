import Foundation
import Testing
@testable import PlayerKit

// MARK: - Otomatik sonraki bölüm kararı (04 §8.6, SS-062)

@Suite("AutoAdvancePolicy — bölüm sonu kararları")
struct AutoAdvancePolicyTests {
    @Test("Feed ortasında bölüm biterse sonraki karta geçilir")
    func advancesToNextIndex() {
        let decision = AutoAdvancePolicy.decision(activeIndex: 2, itemCount: 10, isAutoAdvanceEnabled: true)
        #expect(decision == .advance(toIndex: 3))
    }

    @Test("Son kartta bölüm biterse yeni sayfa/dizi önerisi istenir")
    func lastItemRequestsMore() {
        let decision = AutoAdvancePolicy.decision(activeIndex: 9, itemCount: 10, isAutoAdvanceEnabled: true)
        #expect(decision == .requestMoreItems)
    }

    @Test("Otomatik oynatma kapalıysa yerinde kalınır")
    func disabledStays() {
        let decision = AutoAdvancePolicy.decision(activeIndex: 2, itemCount: 10, isAutoAdvanceEnabled: false)
        #expect(decision == .stay)
    }

    @Test("Aktif indeks yoksa karar yok")
    func noActiveIndexStays() {
        let decision = AutoAdvancePolicy.decision(activeIndex: nil, itemCount: 10, isAutoAdvanceEnabled: true)
        #expect(decision == .stay)
    }

    @Test("Boş feed'de yerinde kalınır")
    func emptyFeedStays() {
        let decision = AutoAdvancePolicy.decision(activeIndex: 0, itemCount: 0, isAutoAdvanceEnabled: true)
        #expect(decision == .stay)
    }
}

// MARK: - Devam Et pozisyonu (04 §12.2, SS-065 çekirdeği)

@Suite("FeedResumePolicy — devam et kuralı")
struct FeedResumePolicyTests {
    @Test("3 sn üstü ve %90 altı ilerleme devam pozisyonu üretir")
    func midProgressResumes() {
        let episode = Fixture.episode(durationSec: 100)
        let item = Fixture.feedItem(episode: episode, progress: Fixture.progress(for: episode, positionSec: 42))
        #expect(FeedResumePolicy.resumePosition(for: item) == 42)
    }

    @Test("İlk 3 sn'lik ilerleme yok sayılır (sıfırdan başlar)")
    func tinyProgressIgnored() {
        let episode = Fixture.episode(durationSec: 100)
        let item = Fixture.feedItem(episode: episode, progress: Fixture.progress(for: episode, positionSec: 2))
        #expect(FeedResumePolicy.resumePosition(for: item) == nil)
    }

    @Test("%90 üstü ilerleme yok sayılır (tamamlandı eşiği)")
    func nearlyCompleteIgnored() {
        let episode = Fixture.episode(durationSec: 100)
        let item = Fixture.feedItem(episode: episode, progress: Fixture.progress(for: episode, positionSec: 95))
        #expect(FeedResumePolicy.resumePosition(for: item) == nil)
    }

    @Test("completed işaretli ilerleme yok sayılır")
    func completedIgnored() {
        let episode = Fixture.episode(durationSec: 100)
        let item = Fixture.feedItem(
            episode: episode,
            progress: Fixture.progress(for: episode, positionSec: 50, completed: true)
        )
        #expect(FeedResumePolicy.resumePosition(for: item) == nil)
    }

    @Test("İlerleme kaydı yoksa devam pozisyonu yok")
    func noProgressNoResume() {
        let episode = Fixture.episode(durationSec: 100)
        let item = Fixture.feedItem(episode: episode)
        #expect(FeedResumePolicy.resumePosition(for: item) == nil)
    }
}
