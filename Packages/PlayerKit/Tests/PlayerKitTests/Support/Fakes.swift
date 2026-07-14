import AppFoundation
import ContentKit
import Foundation
@testable import PlayerKit

// MARK: - Fixture üreticileri

enum Fixture {
    static func episode(
        id: String = "e1",
        seriesID: String = "s1",
        index: Int = 1,
        kind: EpisodeAccess.Kind = .free,
        unlockPrice: Int? = nil,
        adUnlockEligible: Bool = false,
        durationSec: Int = 90
    ) -> Episode {
        Episode(
            id: EpisodeID(id),
            seriesId: SeriesID(seriesID),
            index: index,
            title: nil,
            durationSec: durationSec,
            thumbnailURL: URL(string: "https://cdn.test/thumbs/\(id).jpg")!,
            access: EpisodeAccess(kind: kind, unlockPrice: unlockPrice, adUnlockEligible: adUnlockEligible),
            publishedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 0..<count aralığında feed indeksiyle hizalı serbest bölüm listesi üretir.
    static func episodes(count: Int, lockedIndexes: Set<Int> = []) -> [Episode] {
        (0 ..< count).map { feedIndex in
            episode(
                id: "e\(feedIndex)",
                index: feedIndex + 1,
                kind: lockedIndexes.contains(feedIndex) ? .locked : .free,
                unlockPrice: lockedIndexes.contains(feedIndex) ? 60 : nil
            )
        }
    }
}

// MARK: - Sahte saat

final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_000_000)) {
        current = start
    }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }

    var nowProvider: @Sendable () -> Date {
        { self.now }
    }
}

// MARK: - Sahte video backend'i (AVFoundation'sız)

final class FakeVideoPlaying: VideoPlaying, @unchecked Sendable {
    enum Call: Equatable, Sendable {
        case load(URL, BufferPolicy)
        case playImmediately(Double)
        case pause
        /// Keskin (`.zero` toleranslı) seek: resume / scrubber bırakışı yolu.
        case seek(TimeInterval)
        /// Toleranslı seek: çift-tap ±10 sn hızlı segment-sınırı seek'i (04 §8.1).
        case seekTolerant(TimeInterval)
        case setRate(Double)
        case setMuted(Bool)
        case setPitchPreservation(Bool)
        case applyBufferPolicy(BufferPolicy)
        case setPeakBitRateCap(Double?)
        case clearItem
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []
    private var positionSeconds: TimeInterval = 0
    private var currentGeneration: UInt64 = 0

    nonisolated let runtimeEvents: AsyncStream<TaggedRuntimeEvent>
    private let continuation: AsyncStream<TaggedRuntimeEvent>.Continuation

    init() {
        (runtimeEvents, continuation) = AsyncStream.makeStream()
    }

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    /// Son `load` çağrısının jenerasyonu — bayat-olay testleri eski etiketi buradan yakalar.
    var lastLoadGeneration: UInt64 {
        lock.withLock { currentGeneration }
    }

    /// Olayı GÜNCEL yüklemenin jenerasyonuyla basar (gerçek backend'in normal yolu).
    func emit(_ event: PlayerRuntimeEvent) {
        continuation.yield(TaggedRuntimeEvent(generation: lastLoadGeneration, event: event))
    }

    /// Olayı verilen (ör. bayat) jenerasyonla basar — yarış testleri için.
    func emit(_ event: PlayerRuntimeEvent, generation: UInt64) {
        continuation.yield(TaggedRuntimeEvent(generation: generation, event: event))
    }

    func setPosition(_ seconds: TimeInterval) {
        lock.withLock { positionSeconds = seconds }
    }

    private func record(_ call: Call) {
        lock.withLock { recordedCalls.append(call) }
    }

    func load(url: URL, bufferPolicy: BufferPolicy, generation: UInt64) async {
        lock.withLock { currentGeneration = generation }
        record(.load(url, bufferPolicy))
    }

    func playImmediately(atRate rate: Double) async {
        record(.playImmediately(rate))
    }

    func pause() async {
        record(.pause)
    }

    func seek(toSeconds seconds: TimeInterval, tolerant: Bool) async {
        record(tolerant ? .seekTolerant(seconds) : .seek(seconds))
    }

    func setRate(_ rate: Double) async {
        record(.setRate(rate))
    }

    func setMuted(_ muted: Bool) async {
        record(.setMuted(muted))
    }

    func setPitchPreservation(_ enabled: Bool) async {
        record(.setPitchPreservation(enabled))
    }

    func applyBufferPolicy(_ policy: BufferPolicy) async {
        record(.applyBufferPolicy(policy))
    }

    func setPeakBitRateCap(_ bitsPerSecond: Double?) async {
        record(.setPeakBitRateCap(bitsPerSecond))
    }

    func currentPositionSeconds() async -> TimeInterval {
        lock.withLock { positionSeconds }
    }

    func clearItem() async {
        record(.clearItem)
    }
}

// MARK: - PlaybackServicing casusu

final class PlaybackServicingSpy: PlaybackServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var expiry: Date
    private var delayNanoseconds: UInt64 = 0
    private var failure: AppError?

    init(expiresAt: Date = Date().addingTimeInterval(600)) {
        expiry = expiresAt
    }

    var authorizeCallCount: Int {
        lock.withLock { callCount }
    }

    func setExpiry(_ date: Date) {
        lock.withLock { expiry = date }
    }

    func setDelay(nanoseconds: UInt64) {
        lock.withLock { delayNanoseconds = nanoseconds }
    }

    func setFailure(_ error: AppError?) {
        lock.withLock { failure = error }
    }

    func authorize(episodeId: EpisodeID) async throws -> PlaybackAuthorization {
        let delay = lock.withLock { delayNanoseconds }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return try makeAuthorization(episodeId: episodeId)
    }

    private func makeAuthorization(episodeId: EpisodeID) throws -> PlaybackAuthorization {
        try lock.withLock {
            callCount += 1
            if let failure {
                throw failure
            }
            return PlaybackAuthorization(
                episodeId: episodeId,
                playbackURL: URL(string: "https://cdn.test/\(episodeId.rawValue)/v\(callCount)/master.m3u8")!,
                expiresAt: expiry,
                drm: nil
            )
        }
    }
}

// MARK: - Entitlement sahtesi

final class FakeEntitlements: EntitlementChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var granted: Set<EpisodeID>

    init(granted: Set<EpisodeID> = []) {
        self.granted = granted
    }

    func grant(_ episodeID: EpisodeID) {
        lock.withLock { _ = granted.insert(episodeID) }
    }

    func hasAccess(to episodeID: EpisodeID) async -> Bool {
        lock.withLock { granted.contains(episodeID) }
    }
}

// MARK: - Ağ / tercih sahteleri

final class FakeNetworkProvider: NetworkConditionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var condition: NetworkCondition

    init(_ condition: NetworkCondition = .wifi) {
        self.condition = condition
    }

    func set(_ newCondition: NetworkCondition) {
        lock.withLock { condition = newCondition }
    }

    func currentCondition() async -> NetworkCondition {
        lock.withLock { condition }
    }
}

final class FakePreferences: PlaybackPreferencesProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var dataSaver: Bool

    init(dataSaverEnabled: Bool = false) {
        dataSaver = dataSaverEnabled
    }

    func setDataSaver(_ enabled: Bool) {
        lock.withLock { dataSaver = enabled }
    }

    func isDataSaverEnabled() async -> Bool {
        lock.withLock { dataSaver }
    }
}

// MARK: - Prefetch ısındırma kaydedicisi

final class RecordingWarmer: EpisodeWarming, @unchecked Sendable {
    private let lock = NSLock()
    private var warmedRecords: [(episodeID: EpisodeID, feedIndex: Int)] = []
    private var cancelled: [EpisodeID] = []
    private var delayNanoseconds: UInt64 = 0

    var warmedIDs: [EpisodeID] {
        lock.withLock { warmedRecords.map(\.episodeID) }
    }

    var warmedFeedIndexes: [Int] {
        lock.withLock { warmedRecords.map(\.feedIndex) }
    }

    var cancelledIDs: [EpisodeID] {
        lock.withLock { cancelled }
    }

    func setDelay(nanoseconds: UInt64) {
        lock.withLock { delayNanoseconds = nanoseconds }
    }

    func warm(_ episode: Episode, atFeedIndex feedIndex: Int) async {
        let delay = lock.withLock { delayNanoseconds }
        if delay > 0 {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                lock.withLock { cancelled.append(episode.id) }
                return
            }
        }
        lock.withLock { warmedRecords.append((episode.id, feedIndex)) }
    }
}

// MARK: - Asenkron bekleme yardımcıları

/// Koşul sağlanana dek kısa aralıklarla yoklar; testlerde sonsuz bekleme yerine
/// zaman aşımlı determinizm sağlar.
@discardableResult
func eventually(
    timeoutSeconds: TimeInterval = 2,
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

func awaitState(
    _ expected: PlayerEngineState,
    on engine: PlaybackEngine,
    timeoutSeconds: TimeInterval = 2
) async -> Bool {
    await eventually(timeoutSeconds: timeoutSeconds) { await engine.currentState() == expected }
}
