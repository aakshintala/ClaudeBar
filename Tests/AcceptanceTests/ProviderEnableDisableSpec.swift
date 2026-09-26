import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Provider Enable/Disable
///
/// Users toggle providers on/off from Settings. Disabled providers
/// are hidden from pills and excluded from monitoring.
///
/// Behaviors covered:
/// - #46: User toggles provider off → removed from pills, excluded from monitoring
/// - #47: User toggles provider on → appears in pills, included in monitoring
/// - #48: Enabled state persists across restarts
@Suite("Feature: Provider Enable/Disable")
struct ProviderEnableDisableSpec {

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

    // MARK: - #46: Disable provider excludes from monitoring

    @Suite("Scenario: Disable a provider")
    @MainActor
    struct DisableProvider {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `disabled provider is skipped during refresh`() async {
            // Given — Claude enabled, Codex disabled
            let settings = ProviderEnableDisableSpec.makeSettings()

            let claudeProbe = MockUsageProbe()
            given(claudeProbe).isAvailable().willReturn(true)
            given(claudeProbe).probe().willReturn(UsageSnapshot(
                providerId: "claude",
                quotas: [UsageQuota(percentRemaining: 70, quotaType: .session, providerId: "claude")],
                capturedAt: Date()
            ))

            let codexProbe = MockUsageProbe()
            // No setup — Codex should never be called

            let claude = ClaudeProvider(probe: claudeProbe, settingsRepository: settings)
            let codex = CodexProvider(probe: codexProbe, settingsRepository: settings)
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: [claude, codex],
                clock: TestClock()
            )

            // When
            await monitor.refresh()

            // Then — Claude refreshed, Codex skipped
            #expect(claude.snapshot != nil)
            #expect(codex.snapshot == nil)
        }

    }

    // MARK: - #47: Enable provider

    @Suite("Scenario: Enable a provider")
    @MainActor
    struct EnableProvider {
        private struct TestClock: Clock {
            func sleep(for duration: Duration) async throws {}
            func sleep(nanoseconds: UInt64) async throws {}
        }

        @Test
        func `enabling Codex includes it in monitoring`() {
            // Given — Codex disabled
            let settings = ProviderEnableDisableSpec.makeSettings()
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: settings)
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: settings)
            codex.isEnabled = false

            let monitor = QuotaMonitor(
                providers: [claude, codex],
                clock: TestClock()
            )

            // When — user enables Codex
            monitor.setProviderEnabled("codex", enabled: true)

            // Then — Codex appears
            #expect(codex.isEnabled == true)
            #expect(monitor.enabledProviders.count == 2)
        }
    }

    // MARK: - #48: Enabled state persists

    @Suite("Scenario: Enabled state persists across restarts")
    @MainActor
    struct PersistEnabledState {

        @Test
        func `enabled state is stored in settings`() {
            // Given — isolated settings file
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("claudebar-test-\(UUID().uuidString)")
            let fileURL = tempDir.appendingPathComponent("settings.json")
            defer { try? FileManager.default.removeItem(at: tempDir) }
            let repo = JSONSettingsRepository(store: JSONSettingsStore(fileURL: fileURL))

            // When — set enabled to false
            repo.setEnabled(false, forProvider: "codex")

            // Then — persisted value is false
            #expect(repo.isEnabled(forProvider: "codex", defaultValue: true) == false)

            // When — set enabled to true
            repo.setEnabled(true, forProvider: "codex")

            // Then — persisted value is true
            #expect(repo.isEnabled(forProvider: "codex", defaultValue: true) == true)
        }
    }
}
