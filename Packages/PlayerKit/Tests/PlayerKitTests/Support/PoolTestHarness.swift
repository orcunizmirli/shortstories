import AppFoundation
import AppFoundationTestSupport
import ContentKit
import Foundation
@testable import PlayerKit

// MARK: - Ortak havuz harness'ı (PlayerPool suite'leri paylaşır)

final class BackendBox: @unchecked Sendable {
    private let lock = NSLock()
    private var created: [FakeVideoPlaying] = []

    var backends: [FakeVideoPlaying] {
        lock.withLock { created }
    }

    var factory: @Sendable () -> any VideoPlaying {
        {
            let backend = FakeVideoPlaying()
            self.lock.withLock { self.created.append(backend) }
            return backend
        }
    }
}

struct PoolHarness {
    let pool: PlayerPool
    let box: BackendBox
    let service: PlaybackServicingSpy
}

func makePool(
    size: Int = 3,
    entitled: Set<EpisodeID> = [],
    network: NetworkCondition = .wifi,
    dataSaver: Bool = false
) -> PoolHarness {
    let box = BackendBox()
    let service = PlaybackServicingSpy()
    let pool = PlayerPool(
        size: size,
        backendFactory: box.factory,
        playback: service,
        entitlements: FakeEntitlements(granted: entitled),
        network: FakeNetworkProvider(network),
        preferences: FakePreferences(dataSaverEnabled: dataSaver),
        logger: MockLogger()
    )
    return PoolHarness(pool: pool, box: box, service: service)
}
