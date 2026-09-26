import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Refresh
///
/// Users refresh quota data manually or via background sync.
///
/// Behaviors covered:
/// - #15: User clicks Refresh → fetches latest quota for current provider
/// - #16: Button shows "Syncing..." spinner while in progress
/// - #17: Duplicate refresh clicks are ignored while syncing
/// - #18: Background sync auto-refreshes every enabled provider at configured interval
@Suite("Feature: Refresh")
struct RefreshSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private static func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    // MARK: - #15: Successful refresh

    @Suite("Scenario: Successful refresh")
    @MainActor
    struct SuccessfulRefresh {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `refresh updates snapshot with fresh data`() async {
            // Given
            let settings = RefreshSpec.makeSettings()
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            #expect(claude.snapshot == nil)

            // When — user clicks Refresh
            await monitor.refresh()

            // Then
            #expect(claude.snapshot != nil)
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 65)
        }

        @Test
        func `failed refresh stores error without affecting other providers`() async {
            // Given
            let settings = RefreshSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            given(codexProbe).isAvailable().willReturn(true)
            given(codexProbe).probe().willThrow(ProbeError.timeout)

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: TestClock()
            )

            // When
            await monitor.refresh()

            // Then — Claude succeeds, Codex fails independently
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot == nil)
            #expect(codex.lastError != nil)
        }
    }

    // MARK: - #18: Background sync

    @Suite("Scenario: Background sync")
    @MainActor
    struct BackgroundSync {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `background sync refreshes every enabled provider`() async {
            // Given — Claude and Codex enabled
            let settings = RefreshSpec.makeSettings()
            let claudeProbe = SequentialProbe([UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            )])
            let codexProbe = SequentialProbe([UsageSnapshot(
                providerId: "codex",
                quotas: [UsageQuota(percentRemaining: 40, quotaType: .session, providerId: "codex")],
                capturedAt: Date()
            )])
            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude, codex]),
                clock: OneTickClock()
            )

            // When — background sync runs one tick
            await monitor.startMonitoring(interval: .seconds(60)).value

            // Then — both providers were refreshed, not just Claude
            #expect(claude.snapshot?.quotas.first?.percentRemaining == 50)
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 40)
        }

        /// A clock that ends the loop at its first sleep, so one tick runs.
        private struct OneTickClock: Clock {
            func sleep(for duration: Duration) async throws { throw CancellationError() }
            func sleep(nanoseconds: UInt64) async throws { throw CancellationError() }
        }

        /// A probe that returns the next snapshot in a sequence on each call, so a
        /// test can tell successive refreshes apart by their data.
        private final class SequentialProbe: UsageProbe, @unchecked Sendable {
            private let lock = NSLock()
            private var index = 0
            private let snapshots: [UsageSnapshot]
            init(_ snapshots: [UsageSnapshot]) { self.snapshots = snapshots }
            func probe() async throws -> UsageSnapshot {
                lock.withLock {
                    let snapshot = snapshots[min(index, snapshots.count - 1)]
                    index += 1
                    return snapshot
                }
            }
            func isAvailable() async -> Bool { true }
        }

        @Test
        func `refresh button bypasses the one-minute freshness window`() async {
            // Given — a provider returning a different snapshot on each probe
            let settings = RefreshSpec.makeSettings()
            let probe = SequentialProbe([
                UsageSnapshot(
                    providerId: "codex",
                    quotas: [UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "codex")],
                    capturedAt: Date()
                ),
                UsageSnapshot(
                    providerId: "codex",
                    quotas: [UsageQuota(percentRemaining: 60, quotaType: .session, providerId: "codex")],
                    capturedAt: Date()
                ),
            ])
            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(providers: AIProviders(providers: [codex]), clock: TestClock())

            // When/Then — opening the popover again keeps the fresh snapshot...
            await monitor.refresh()
            await monitor.refresh()
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 80)

            // ...and the refresh button fetches new data
            await monitor.refresh(force: true)
            #expect(codex.snapshot?.quotas.first?.percentRemaining == 60)
        }
    }
}
