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
    func `two feeds inside coalescing window share capturedAt`() async {
        let clock = MutableDate(Date(timeIntervalSince1970: 1_700_000_000))
        let probe = TimestampedUsageProbe { clock.value }
        let settings = makeSettings()
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())
        let service = QuotaFeedService(monitor: monitor, now: { clock.value })

        let first = await service.currentFeed()
        clock.value = clock.value.addingTimeInterval(30)
        let second = await service.currentFeed()

        #expect(first.providers[0].capturedAt == second.providers[0].capturedAt)
    }

    @Test
    func `feed after coalescing window has newer capturedAt`() async {
        let clock = MutableDate(Date(timeIntervalSince1970: 1_700_000_000))
        let probe = TimestampedUsageProbe { clock.value }
        let settings = makeSettings()
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())
        let service = QuotaFeedService(monitor: monitor, now: { clock.value })

        let first = await service.currentFeed()
        clock.value = clock.value.addingTimeInterval(61)
        let second = await service.currentFeed()

        #expect(second.providers[0].capturedAt! > first.providers[0].capturedAt!)
    }

    @Test
    func `concurrent feeds during refresh share one capturedAt`() async {
        let gate = RefreshGate()
        let probe = GatedUsageProbe(gate: gate) { Date(timeIntervalSince1970: 1_700_000_000) }
        let settings = makeSettings()
        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())
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
    func `probe failure still returns feed with unavailable`() async {
        let settings = makeSettings()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willThrow(ProbeError.authenticationRequired)

        let cursor = CursorProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [cursor]), clock: TestClock())
        let service = QuotaFeedService(monitor: monitor)

        let feed = await service.currentFeed()

        #expect(feed.providers[0].unavailable != nil)
    }
}

private final class MutableDate: @unchecked Sendable {
    var value: Date
    init(_ value: Date) { self.value = value }
}

private final class TimestampedUsageProbe: UsageProbe, @unchecked Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    func isAvailable() async -> Bool { true }

    func probe() async throws -> UsageSnapshot {
        let capturedAt = now()
        return UsageSnapshot(
            providerId: "claude",
            quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
            capturedAt: capturedAt
        )
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
