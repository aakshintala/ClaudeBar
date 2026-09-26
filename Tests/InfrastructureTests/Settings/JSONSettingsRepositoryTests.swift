import Testing
import Foundation
@testable import Infrastructure

@Suite("JSONSettingsRepository")
struct JSONSettingsRepositoryTests {

    /// Shape of a real `~/.claudebar/settings.json` written by older builds,
    /// including keys that are no longer read.
    private let legacyFile = """
    {
      "app" : {
        "backgroundSyncEnabled" : false, "backgroundSyncInterval" : 300,
        "menuBarDurationEnabled" : false, "menuBarPercentageEnabled" : false,
        "menuBarPercentageProviderId" : "claude", "menuBarPercentageQuotaKey" : "session",
        "overviewModeEnabled" : true, "quotaAlertsEnabled" : false,
        "showDailyUsageCards" : false, "themeMode" : "light",
        "usageDisplayMode" : "remaining", "userHasChosenTheme" : true
      },
      "claude" : { "probeMode" : "api" },
      "codex" : { "probeMode" : "api" },
      "mcp" : { "enabled" : true },
      "providers" : {
        "ampcode" : { "isEnabled" : false }, "claude" : { "isEnabled" : true },
        "codex" : { "isEnabled" : false }, "cursor" : { },
        "gemini" : { "isEnabled" : false }, "opencode-go" : { "isEnabled" : true }
      }
    }
    """

    private func tempFile(_ contents: String? = nil) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-test-\(UUID().uuidString)/settings.json")
        if let contents {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    private func json(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    }

    @Test
    func `missing file yields defaults`() {
        let repo = JSONSettingsRepository(fileURL: tempFile())
        let s = repo.settings
        #expect(s.app.themeMode == "dark")
        #expect(s.app.backgroundSyncEnabled == false)
        #expect(s.app.backgroundSyncInterval == 600)
        #expect(s.app.quotaAlertsEnabled == true)
        #expect(s.feed.enabled == false)
        #expect(s.feed.port == 8787)
        #expect(repo.isEnabled(forProvider: "claude") == true)
        #expect(repo.isEnabled(forProvider: "cursor", defaultValue: false) == false)
    }

    @Test
    func `legacy file loads the values the old dot-path repo returned`() {
        let repo = JSONSettingsRepository(fileURL: tempFile(legacyFile))
        let s = repo.settings
        #expect(s.app.themeMode == "light")
        #expect(s.app.backgroundSyncEnabled == false)
        #expect(s.app.backgroundSyncInterval == 300)
        #expect(s.app.quotaAlertsEnabled == false)
        #expect(s.feed.enabled == true)   // migrated from mcp.enabled
        #expect(s.feed.port == 8787)
        #expect(repo.isEnabled(forProvider: "claude") == true)
        #expect(repo.isEnabled(forProvider: "codex") == false)
        #expect(repo.isEnabled(forProvider: "cursor") == true)   // "{}" means default
        #expect(repo.isEnabled(forProvider: "opencode-go") == true)
    }

    @Test
    func `feed keys win over legacy mcp keys`() {
        let repo = JSONSettingsRepository(fileURL: tempFile("""
        { "mcp": { "enabled": true, "port": 9000 }, "feed": { "enabled": false, "port": 9100 } }
        """))
        #expect(repo.settings.feed.enabled == false)
        #expect(repo.settings.feed.port == 9100)
    }

    @Test
    func `a write drops dead keys and keeps live ones`() {
        let url = tempFile(legacyFile)
        let repo = JSONSettingsRepository(fileURL: url)
        repo.keepProviders(["claude", "codex", "cursor", "opencode-go"])
        repo.update { $0.app.themeMode = "dark" }

        let file = json(url)
        #expect(Set(file.keys) == ["app", "feed", "mcp", "providers"])
        let app = file["app"] as? [String: Any] ?? [:]
        #expect(Set(app.keys) == ["themeMode", "backgroundSyncEnabled", "backgroundSyncInterval", "quotaAlertsEnabled"])
        #expect(app["themeMode"] as? String == "dark")
        #expect(app["backgroundSyncInterval"] as? Double == 300)
        let providers = file["providers"] as? [String: Any] ?? [:]
        #expect(Set(providers.keys) == ["claude", "codex", "cursor", "opencode-go"])
        // The installed older build still reads mcp.*, so it is mirrored from feed.
        #expect((file["mcp"] as? [String: Any])?["enabled"] as? Bool == true)
        #expect((file["feed"] as? [String: Any])?["enabled"] as? Bool == true)

        let reloaded = JSONSettingsRepository(fileURL: url)
        #expect(reloaded.settings == repo.settings)
        #expect(reloaded.isEnabled(forProvider: "codex") == false)
    }

    @Test
    func `setEnabled persists across instances`() {
        let url = tempFile()
        JSONSettingsRepository(fileURL: url).setEnabled(false, forProvider: "codex")
        let repo = JSONSettingsRepository(fileURL: url)
        #expect(repo.isEnabled(forProvider: "codex") == false)
        #expect(repo.isEnabled(forProvider: "claude") == true)
    }
}
