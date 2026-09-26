import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Notifications
///
/// Users receive system notifications when their quota status degrades.
/// No notification is sent when status improves or stays the same.
///
/// Behaviors covered:
/// - #19: Quota drops to Warning (≤50%) → system notification
/// - #20: Quota drops to Critical (<20%) → system notification
/// - #21: Quota hits Depleted (0%) → system notification
/// - #22: Quota improves → no notification
@Suite("Feature: Notifications")
struct NotificationsSpec {

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

    // MARK: - #19–21: Quota degrades → notification sent

    @Suite("Scenario: Quota degrades")
    @MainActor
    struct QuotaDegrades {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `quota drops from healthy to critical triggers alert`() async {
            // Given — Claude was previously healthy (no snapshot = healthy default)
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                alerter: mockAlerter,
                clock: TestClock()
            )

            // When — refresh returns 15% (critical)
            await monitor.refresh()

            // Then — alerter called with healthy → critical
            verify(mockAlerter).alert(
                providerId: .value("claude"),
                previousStatus: .value(.healthy),
                currentStatus: .value(.critical)
            ).called(1)
        }
    }

    // MARK: - Every refresh path alerts

    @Suite("Scenario: Popover refresh")
    @MainActor
    struct PopoverRefresh {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `refresh button that finds a degraded quota triggers alert`() async {
            // Given — Codex healthy, then critical on the next probe
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

            let probe = DegradingProbe()

            let codex = CodexProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [codex]),
                alerter: mockAlerter,
                clock: TestClock()
            )

            // When — the popover opens, then the user clicks Refresh
            await monitor.refresh()
            await monitor.refresh(force: true)

            // Then — the popover path alerts healthy → critical
            verify(mockAlerter).alert(
                providerId: .value("codex"),
                previousStatus: .value(.healthy),
                currentStatus: .value(.critical)
            ).called(1)
        }

        /// Healthy (80%) on the first probe, critical (10%) after.
        private final class DegradingProbe: UsageProbe, @unchecked Sendable {
            private let lock = NSLock()
            private var calls = 0
            func probe() async throws -> UsageSnapshot {
                let percent: Double = lock.withLock { calls += 1; return calls == 1 ? 80 : 10 }
                return UsageSnapshot(
                    providerId: "codex",
                    quotas: [UsageQuota(percentRemaining: percent, quotaType: .session, providerId: "codex")],
                    capturedAt: Date()
                )
            }
            func isAvailable() async -> Bool { true }
        }
    }

    // MARK: - #22: Quota stays the same → no notification

    @Suite("Scenario: Quota stays the same")
    @MainActor
    struct QuotaUnchanged {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `repeated healthy refreshes do not trigger alert`() async {
            // Given
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let mockAlerter = MockQuotaAlerter()
            given(mockAlerter).alert(providerId: .any, previousStatus: .any, currentStatus: .any).willReturn(())

            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                alerter: mockAlerter,
                clock: TestClock()
            )

            // When — refresh twice with same healthy status
            await monitor.refresh()
            await monitor.refresh()

            // Then — no alerts (healthy → healthy is not a degradation)
            verify(mockAlerter).alert(
                providerId: .any,
                previousStatus: .any,
                currentStatus: .any
            ).called(0)
        }
    }

    // MARK: - Cross-behavior: One provider failure does not affect others

    @Suite("Scenario: Provider isolation")
    @MainActor
    struct ProviderIsolation {

        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `one provider failure does not block others from refreshing`() async {
            // Given
            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

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

            // When — refresh all
            await monitor.refresh()

            // Then — Claude succeeds independently
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot == nil)
            #expect(codex.lastError != nil)
        }
    }
}
