import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("QuotaFeedDTO mapping")
@MainActor
struct QuotaFeedDTOTests {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSettings(enabled: Bool = true) -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(enabled)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    @Test
    func `modelSpecific quota maps quotaKey and displayName label`() async {
        let settings = makeSettings()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        let capturedAt = Self.fixedNow.addingTimeInterval(-120)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(
                    percentRemaining: 42,
                    quotaType: .modelSpecific("opus"),
                    providerId: "claude",
                    resetsAt: Self.fixedNow.addingTimeInterval(3600),
                    resetText: "12/500 on-demand"
                ),
                UsageQuota(
                    percentRemaining: 80,
                    quotaType: .timeLimit("Monthly"),
                    providerId: "claude"
                )
            ],
            capturedAt: capturedAt,
            accountTier: .claudeMax
        ))

        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())
        await monitor.refresh(providerId: "claude")

        let feed = QuotaFeedDTO.make(from: monitor.allProviders, at: Self.fixedNow)

        #expect(feed.providers.count == 1)
        let quotas = feed.providers[0].quotas
        #expect(quotas[0].key == "model:opus")
        #expect(quotas[0].label == "Opus")
        #expect(quotas[0].resetText == "12/500 on-demand")
        #expect(quotas[1].key == "time:Monthly")
        #expect(quotas[1].label == "Monthly")
    }

    @Test
    func `nil snapshot with no error yields null capturedAt`() {
        let settings = makeSettings()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)

        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)

        let feed = QuotaFeedDTO.make(from: [claude], at: Self.fixedNow)

        #expect(feed.providers.count == 1)
        #expect(feed.providers[0].capturedAt == nil)
        #expect(feed.providers[0].ageSeconds == nil)
        #expect(feed.providers[0].unavailable == nil)
        #expect(feed.providers[0].throttledUntil == nil)
    }

    @Test
    func `lastError populates unavailable`() async {
        let settings = makeSettings()
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willThrow(ProbeError.authenticationRequired)

        let cursor = CursorProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [cursor]), clock: TestClock())
        await monitor.refresh(providerId: "cursor")

        let feed = QuotaFeedDTO.make(from: monitor.allProviders, at: Self.fixedNow)

        #expect(feed.providers[0].unavailable == ProbeError.authenticationRequired.localizedDescription)
        #expect(feed.providers[0].throttledUntil == nil)
    }

    @Test
    func `rateLimited populates throttledUntil not unavailable`() async {
        let settings = makeSettings()
        let capturedAt = Self.fixedNow.addingTimeInterval(-600)
        let retryAt = Self.fixedNow.addingTimeInterval(3600)
        let probe = SequentialUsageProbe(
            results: [
                .success(UsageSnapshot(
                    providerId: "claude",
                    quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                    capturedAt: capturedAt
                )),
                .failure(ProbeError.rateLimited(retryAt: retryAt))
            ]
        )

        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        let monitor = QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())
        await monitor.refresh(providerId: "claude")
        await monitor.refresh(providerId: "claude")

        let feed = QuotaFeedDTO.make(from: monitor.allProviders, at: Self.fixedNow)

        #expect(feed.providers[0].throttledUntil == retryAt)
        #expect(feed.providers[0].unavailable == nil)
        #expect(feed.providers[0].capturedAt == capturedAt)
    }

    @Test
    func `disabled providers appear in disabledProviderIds not providers`() {
        let enabledSettings = makeSettings(enabled: true)
        let disabledSettings = makeSettings(enabled: false)

        let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: enabledSettings)
        let opencode = OpenCodeProvider(
            probe: MockUsageProbe(),
            settingsRepository: disabledSettings
        )

        let feed = QuotaFeedDTO.make(from: [claude, opencode], at: Self.fixedNow)

        #expect(feed.providers.map(\.id) == ["claude"])
        #expect(feed.disabledProviderIds == ["opencode-go"])
    }
}

private final class SequentialUsageProbe: UsageProbe, @unchecked Sendable {
    private let results: [Result<UsageSnapshot, Error>]
    nonisolated(unsafe) private var index = 0

    init(results: [Result<UsageSnapshot, Error>]) {
        self.results = results
    }

    func isAvailable() async -> Bool { true }

    func probe() async throws -> UsageSnapshot {
        defer { index += 1 }
        guard index < results.count else {
            throw ProbeError.noData
        }
        switch results[index] {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }
}
