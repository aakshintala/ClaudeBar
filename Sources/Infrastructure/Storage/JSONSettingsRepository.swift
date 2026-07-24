import Foundation
import Domain

/// Unified JSON-backed settings repository.
/// Implements all settings protocols: AppSettingsRepository + ProviderSettingsRepository
/// (including all sub-protocols).
///
/// Backed by `JSONSettingsStore` reading/writing `~/.claudebar/settings.json`.
/// Credentials (tokens, API keys) use UserDefaults for now (Keychain migration later).
public final class JSONSettingsRepository:
    AppSettingsRepository,
    CodexSettingsRepository,
    @unchecked Sendable
{
    /// Shared instance using the default settings file
    public static let shared = JSONSettingsRepository(store: .shared)

    private let store: JSONSettingsStore
    private let credentials: UserDefaults

    public init(store: JSONSettingsStore, credentials: UserDefaults = .standard) {
        self.store = store
        self.credentials = credentials
    }

    // MARK: - AppSettingsRepository

    public func themeMode() -> String {
        store.read(key: "app.themeMode") ?? "dark"
    }

    public func setThemeMode(_ mode: String) {
        store.write(value: mode, key: "app.themeMode")
    }

    public func userHasChosenTheme() -> Bool {
        store.read(key: "app.userHasChosenTheme") ?? false
    }

    public func setUserHasChosenTheme(_ chosen: Bool) {
        store.write(value: chosen, key: "app.userHasChosenTheme")
    }

    public func backgroundSyncEnabled() -> Bool {
        store.read(key: "app.backgroundSyncEnabled") ?? false
    }

    public func setBackgroundSyncEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.backgroundSyncEnabled")
    }

    public func backgroundSyncInterval() -> TimeInterval {
        // Default 10 min (issue #204): a power-conscious cadence for the
        // background menu-bar refresh when no interval has been persisted yet.
        store.read(key: "app.backgroundSyncInterval") ?? 600
    }

    public func setBackgroundSyncInterval(_ interval: TimeInterval) {
        store.write(value: interval, key: "app.backgroundSyncInterval")
    }

    public func quotaAlertsEnabled() -> Bool {
        store.read(key: "app.quotaAlertsEnabled") ?? true
    }

    public func setQuotaAlertsEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.quotaAlertsEnabled")
    }

    public func mcpEnabled() -> Bool {
        store.read(key: "mcp.enabled") ?? false
    }

    public func setMCPEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "mcp.enabled")
    }

    public func mcpPort() -> Int {
        store.read(key: "mcp.port") ?? 8787
    }

    public func setMCPPort(_ port: Int) {
        store.write(value: port, key: "mcp.port")
    }

    public func claudeSnapshotCacheTTL() -> TimeInterval {
        store.read(key: "claude.snapshotCacheTTL") ?? 300
    }

    public func setClaudeSnapshotCacheTTL(_ ttl: TimeInterval) {
        store.write(value: ttl, key: "claude.snapshotCacheTTL")
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        store.read(key: "providers.\(id).isEnabled") ?? defaultValue
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        store.write(value: enabled, key: "providers.\(id).isEnabled")
    }

    // MARK: - CodexSettingsRepository

    public func codexProbeMode() -> CodexProbeMode {
        guard let raw: String = store.read(key: "codex.probeMode"),
              let mode = CodexProbeMode(rawValue: raw) else {
            return .rpc
        }
        return mode
    }

    public func setCodexProbeMode(_ mode: CodexProbeMode) {
        store.write(value: mode.rawValue, key: "codex.probeMode")
    }
}
