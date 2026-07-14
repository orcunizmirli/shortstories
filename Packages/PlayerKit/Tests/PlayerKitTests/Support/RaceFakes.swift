import AppFoundation
import ContentKit
import Foundation
@testable import PlayerKit

// MARK: - Test kapısı (deterministik yarış penceresi)

/// Anahtar bazlı askı kapısı: üretim yolundaki suspension noktası `pass(_:)` ile
/// test kontrolünde askıya alınır; test `awaitEntered` ile girişi gözler, `open`
/// ile devam ettirir. Zamanlayıcı/sleep YOK — yarış pencereleri deterministiktir.
final class TestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enteredKeys: Set<String> = []
    private var enterWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var openedKeys: Set<String> = []
    private var openWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]

    /// Üretim yolu: anahtara girildiğini işaretler ve kapı açılana dek askıda kalır.
    func pass(_ key: String) async {
        signal(key)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow: Bool = lock.withLock {
                if openedKeys.contains(key) {
                    return true
                }
                openWaiters[key, default: []].append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    /// Üretim yolu (askısız): anahtara girildiğini işaretler, beklemez.
    func signal(_ key: String) {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            enteredKeys.insert(key)
            return enterWaiters.removeValue(forKey: key) ?? []
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Test: anahtara girilmesini bekler (girildiyse hemen döner).
    func awaitEntered(_ key: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow: Bool = lock.withLock {
                if enteredKeys.contains(key) {
                    return true
                }
                enterWaiters[key, default: []].append(continuation)
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    /// Test: kapıyı açar — askıdaki ve gelecekteki `pass` çağrıları geçer.
    func open(_ key: String) {
        let waiters: [CheckedContinuation<Void, Never>] = lock.withLock {
            openedKeys.insert(key)
            return openWaiters.removeValue(forKey: key) ?? []
        }
        for waiter in waiters {
            waiter.resume()
        }
    }
}

// MARK: - Kapılı authorize servisi

/// `authorize` çağrısını bölüm anahtarında (`episodeId.rawValue`) kapıda askıya alır;
/// test, acquire'ın authorize suspension'ında olduğunu deterministik bilir.
final class GatedPlaybackService: PlaybackServicing, @unchecked Sendable {
    let gate = TestGate()
    private let lock = NSLock()
    private var callCount = 0
    private let expiry: Date

    init(expiresAt: Date = Date().addingTimeInterval(600)) {
        expiry = expiresAt
    }

    var authorizeCallCount: Int {
        lock.withLock { callCount }
    }

    func authorize(episodeId: EpisodeID) async throws -> PlaybackAuthorization {
        await gate.pass(episodeId.rawValue)
        return lock.withLock {
            callCount += 1
            return PlaybackAuthorization(
                episodeId: episodeId,
                playbackURL: URL(string: "https://cdn.test/\(episodeId.rawValue)/v\(callCount)/master.m3u8")!,
                expiresAt: expiry,
                drm: nil
            )
        }
    }
}

// MARK: - Kapılı ısındırıcı

/// `warm` çağrısını "\(episodeID)#\(çağrıSırası)" anahtarında askıya alır: aynı
/// bölümün ardışık ısındırmaları ayrı anahtar taşır (e6#1, e6#2, ...).
final class GatedWarmer: EpisodeWarming, @unchecked Sendable {
    let gate = TestGate()
    private let lock = NSLock()
    private var callCounts: [EpisodeID: Int] = [:]
    private var completedKeys: [String] = []

    var completions: [String] {
        lock.withLock { completedKeys }
    }

    func warm(_ episode: Episode, atFeedIndex _: Int) async {
        let sequence: Int = lock.withLock {
            let next = (callCounts[episode.id] ?? 0) + 1
            callCounts[episode.id] = next
            return next
        }
        let key = "\(episode.id.rawValue)#\(sequence)"
        await gate.pass(key)
        lock.withLock { completedKeys.append(key) }
    }
}

// MARK: - Aktör çalkalama yardımcısı

/// Engine aktörüne art arda tur attırır: kapı açılışıyla kuyruklanmış continuation
/// işlerinin işlenmesi için yeterli işlem penceresi tanır (negatif iddialar öncesi).
func settle(_ engine: PlaybackEngine, rounds: Int = 25) async {
    for _ in 0 ..< rounds {
        _ = await engine.currentState()
        await Task.yield()
    }
}
