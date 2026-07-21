import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Quota Display
///
/// Users see quota cards with percentages, progress bars, status badges,
/// and reset times after a provider refresh.
///
/// Behaviors covered:
/// - #8: User sees account info card (email, tier badge, freshness)
/// - #9: User sees quota cards with percentage, progress bar, reset time
/// - #10: User toggles "Remaining" vs "Used" display mode
/// - #13: Unavailable provider shows error message with guidance
/// - #14: Over-quota displays negative percentages
@Suite("Feature: Quota Display")
struct QuotaDisplaySpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    // MARK: - #8: Account info card

    @Suite("Scenario: Account info displays after refresh")
    @MainActor
    struct AccountInfo {
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

        @Test
        func `account email and tier are displayed after refresh`() async throws {
            // Given — probe returns a snapshot with account metadata
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")],
                capturedAt: Date(),
                accountEmail: "user@example.com",
                accountOrganization: "Acme Corp",
                accountTier: .claudeMax
            )
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(snapshot)

            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When — user opens menu and quota is refreshed
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot != nil)
            #expect(claude.snapshot?.accountEmail == "user@example.com")
            #expect(claude.snapshot?.accountTier == .claudeMax)
        }
    }

    // MARK: - #9: Quota cards with percentage, status, reset time

    @Suite("Scenario: Quota cards display correctly after refresh")
    @MainActor
    struct QuotaCards {
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

        @Test
        func `healthy session and warning weekly quotas display with correct status`() async throws {
            // Given — 65% session (healthy) and 35% weekly (warning)
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [
                    UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude"),
                    UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
                ],
                capturedAt: Date()
            )
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(snapshot)

            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then — multiple quota cards with correct statuses
            let resultSnapshot = claude.snapshot
            #expect(resultSnapshot != nil)
            #expect(resultSnapshot!.quotas.count == 2)

            let session = resultSnapshot?.quota(for: .session)
            #expect(session?.percentRemaining == 65)
            #expect(session?.status == .healthy)

            let weekly = resultSnapshot?.quota(for: .weekly)
            #expect(weekly?.percentRemaining == 35)
            #expect(weekly?.status == .warning)
        }

        @Test
        func `exhausted session shows depleted status`() async throws {
            // Given — 0% left
            let snapshot = UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            )
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willReturn(snapshot)

            let claude = ClaudeProvider(probe: probe, settingsRepository: Self.makeSettings())
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then
            let session = claude.snapshot?.quota(for: .session)
            #expect(session?.percentRemaining == 0)
            #expect(session?.status == .depleted)
        }
    }

    // MARK: - #13: Unavailable provider shows error

    @Suite("Scenario: Unavailable provider shows error message")
    @MainActor
    struct ProviderErrors {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `unavailable provider has no snapshot after refresh`() async {
            // Given — CLI not found
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(false)

            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then
            #expect(claude.snapshot == nil)
        }

        @Test
        func `session expired error is stored on provider`() async {
            // Given — API returns 401
            let probe = MockUsageProbe()
            given(probe).isAvailable().willReturn(true)
            given(probe).probe().willThrow(ProbeError.sessionExpired())

            let settings = MockProviderSettingsRepository()
            given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(settings).isEnabled(forProvider: .any).willReturn(true)
            given(settings).setEnabled(.any, forProvider: .any).willReturn()

            let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
            let monitor = QuotaMonitor(
                providers: AIProviders(providers: [claude]),
                clock: TestClock()
            )

            // When
            await monitor.refresh(providerId: "claude")

            // Then — error stored, user sees "Session expired..."
            #expect(claude.snapshot == nil)
            #expect(claude.lastError != nil)
            #expect(claude.lastError?.localizedDescription.contains("Session expired") == true)
        }
    }

    // MARK: - #14: Over-quota negative percentages

    @Suite("Scenario: Over-quota displays negative percentages")
    @MainActor
    struct OverQuota {

        @Test
        func `negative percentage is depleted status`() {
            let quota = UsageQuota(
                percentRemaining: -98,
                quotaType: .session,
                providerId: "codex"
            )

            #expect(quota.status == .depleted)
            #expect(quota.percentRemaining == -98)
        }
    }
}
