import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Feature: Action Bar
///
/// Users interact with action buttons: Dashboard, Refresh, Settings, Quit.
///
/// Behaviors covered:
/// - #24: User clicks Dashboard → opens provider's web dashboard in browser
@Suite("Feature: Action Bar")
struct ActionBarSpec {

    // MARK: - #24: Dashboard URLs

    @Suite("Scenario: Dashboard opens correct URL per provider")
    @MainActor
    struct DashboardURLs {

        private static func makeSettings() -> MockProviderSettingsRepository {
            let mock = MockProviderSettingsRepository()
            given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
            given(mock).isEnabled(forProvider: .any).willReturn(true)
            given(mock).setEnabled(.any, forProvider: .any).willReturn()
            return mock
        }

        @Test
        func `Claude dashboard URL is Anthropic billing`() {
            let claude = ClaudeProvider(probe: MockUsageProbe(), settingsRepository: Self.makeSettings())
            #expect(claude.dashboardURL?.absoluteString == "https://console.anthropic.com/settings/billing")
        }

        @Test
        func `Codex dashboard URL is OpenAI usage`() {
            let codex = CodexProvider(probe: MockUsageProbe(), settingsRepository: Self.makeSettings())
            #expect(codex.dashboardURL?.absoluteString == "https://platform.openai.com/usage")
        }
    }
}
