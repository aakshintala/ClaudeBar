import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("QuotaFeedService")
@MainActor
struct QuotaFeedServiceTests {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    @Test
    func `concurrent feeds during refresh share one capturedAt`() async {
        let gate = RefreshGate()
        let probe = GatedUsageProbe(gate: gate) { Date(timeIntervalSince1970: 1_700_000_000) }
        let settings = makeSettings()
        let claude = AIProvider(id: "claude", name: "Claude", probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: [claude], clock: TestClock())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = QuotaFeedService(monitor: monitor, now: { now })

        async let feed1 = service.currentFeed()
        async let feed2 = service.currentFeed()
        async let feed3 = service.currentFeed()

        try? await Task.sleep(nanoseconds: 50_000_000)
        await gate.release()

        let feeds = await [feed1, feed2, feed3]
        let capturedAts = feeds.compactMap { $0.providers.first?.capturedAt }
        #expect(capturedAts.count == 3)
        #expect(Set(capturedAts).count == 1)
    }

    @Test
    func `hung probe does not hold the feed past the deadline`() async {
        let probe = GatedUsageProbe(gate: RefreshGate()) { Date() }  // gate never released
        let claude = AIProvider(id: "claude", name: "Claude", probe: probe, settingsRepository: makeSettings())
        let monitor = QuotaMonitor(providers: [claude], clock: TestClock())
        let service = QuotaFeedService(monitor: monitor, refreshDeadline: 0.2)

        let start = ContinuousClock.now
        _ = await service.currentFeed()
        _ = await service.currentFeed()  // joins the still-hung refresh; must also return

        #expect(ContinuousClock.now - start < .seconds(3))
    }

    @Test
    func `probe failure still returns feed with unavailable`() async {
        let settings = makeSettings()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willThrow(ProbeError.authenticationRequired)

        let cursor = AIProvider(id: "cursor", name: "Cursor", probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: [cursor], clock: TestClock())
        let service = QuotaFeedService(monitor: monitor)

        let feed = await service.currentFeed()

        #expect(feed.providers[0].unavailable != nil)
    }
}

private actor RefreshGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private final class GatedUsageProbe: UsageProbe, @unchecked Sendable {
    private let gate: RefreshGate
    private let now: @Sendable () -> Date

    init(gate: RefreshGate, now: @escaping @Sendable () -> Date) {
        self.gate = gate
        self.now = now
    }

    func isAvailable() async -> Bool { true }

    func probe() async throws -> UsageSnapshot {
        await gate.wait()
        let capturedAt = now()
        return UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: capturedAt
        )
    }
}
