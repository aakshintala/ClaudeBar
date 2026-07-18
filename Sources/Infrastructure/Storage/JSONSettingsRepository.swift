import Foundation
import Domain

/// Unified JSON-backed settings repository.
/// Implements all settings protocols: AppSettingsRepository + ProviderSettingsRepository
/// (including all sub-protocols) + HookSettingsRepository.
///
/// Backed by `JSONSettingsStore` reading/writing `~/.claudebar/settings.json`.
/// Credentials (tokens, API keys) use UserDefaults for now (Keychain migration later).
public final class JSONSettingsRepository:
    AppSettingsRepository,
    ClaudeSettingsRepository,
    CodexSettingsRepository,
    HookSettingsRepository,
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
        store.read(key: "app.themeMode") ?? "system"
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

    public func usageDisplayMode() -> String {
        store.read(key: "app.usageDisplayMode") ?? "remaining"
    }

    public func setUsageDisplayMode(_ mode: String) {
        store.write(value: mode, key: "app.usageDisplayMode")
    }

    public func menuBarPercentageEnabled() -> Bool {
        store.read(key: "app.menuBarPercentageEnabled") ?? false
    }

    public func setMenuBarPercentageEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarPercentageEnabled")
    }

    public func menuBarDurationEnabled() -> Bool {
        store.read(key: "app.menuBarDurationEnabled") ?? false
    }

    public func setMenuBarDurationEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarDurationEnabled")
    }

    public func menuBarStackedEnabled() -> Bool {
        store.read(key: "app.menuBarStackedEnabled") ?? false
    }

    public func setMenuBarStackedEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.menuBarStackedEnabled")
    }

    public func menuBarStackedSize() -> String {
        store.read(key: "app.menuBarStackedSize") ?? "small"
    }

    public func setMenuBarStackedSize(_ size: String) {
        store.write(value: size, key: "app.menuBarStackedSize")
    }

    public func menuBarPercentageProviderId() -> String {
        store.read(key: "app.menuBarPercentageProviderId") ?? "claude"
    }

    public func setMenuBarPercentageProviderId(_ providerId: String) {
        store.write(value: providerId, key: "app.menuBarPercentageProviderId")
    }

    public func menuBarPercentageQuotaKey() -> String {
        store.read(key: "app.menuBarPercentageQuotaKey") ?? "session"
    }

    public func setMenuBarPercentageQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarPercentageQuotaKey")
    }

    public func menuBarSecondaryQuotaKey() -> String {
        store.read(key: "app.menuBarSecondaryQuotaKey") ?? ""
    }

    public func setMenuBarSecondaryQuotaKey(_ quotaKey: String) {
        store.write(value: quotaKey, key: "app.menuBarSecondaryQuotaKey")
    }

    public func showDailyUsageCards() -> Bool {
        store.read(key: "app.showDailyUsageCards") ?? true
    }

    public func setShowDailyUsageCards(_ show: Bool) {
        store.write(value: show, key: "app.showDailyUsageCards")
    }

    public func overviewModeEnabled() -> Bool {
        store.read(key: "app.overviewModeEnabled") ?? false
    }

    public func setOverviewModeEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.overviewModeEnabled")
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

    public func claudeApiBudgetEnabled() -> Bool {
        store.read(key: "app.claudeApiBudgetEnabled") ?? false
    }

    public func setClaudeApiBudgetEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.claudeApiBudgetEnabled")
    }

    public func claudeApiBudget() -> Double {
        store.read(key: "app.claudeApiBudget") ?? 0
    }

    public func setClaudeApiBudget(_ amount: Double) {
        store.write(value: amount, key: "app.claudeApiBudget")
    }

    // MARK: - Burn Rate Warning

    public func burnRateWarningEnabled() -> Bool {
        store.read(key: "app.burnRateWarningEnabled") ?? false
    }

    public func setBurnRateWarningEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "app.burnRateWarningEnabled")
    }

    public func burnRateThreshold() -> Double {
        store.read(key: "app.burnRateThreshold") ?? 1.5
    }

    public func setBurnRateThreshold(_ threshold: Double) {
        store.write(value: threshold, key: "app.burnRateThreshold")
    }

    public func receiveBetaUpdates() -> Bool {
        store.read(key: "app.receiveBetaUpdates") ?? false
    }

    public func setReceiveBetaUpdates(_ receive: Bool) {
        store.write(value: receive, key: "app.receiveBetaUpdates")
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        store.read(key: "providers.\(id).isEnabled") ?? defaultValue
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        store.write(value: enabled, key: "providers.\(id).isEnabled")
    }

    public func customCardURL(forProvider id: String) -> String? {
        store.read(key: "providers.\(id).customCardURL")
    }

    public func setCustomCardURL(_ url: String?, forProvider id: String) {
        let value: Any? = (url?.isEmpty == false) ? url : nil
        store.write(value: value, key: "providers.\(id).customCardURL")
    }

    // MARK: - ClaudeSettingsRepository

    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let raw: String = store.read(key: "claude.probeMode"),
              let mode = ClaudeProbeMode(rawValue: raw) else {
            return .cli
        }
        return mode
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        store.write(value: mode.rawValue, key: "claude.probeMode")
    }

    public func claudeCliFallbackEnabled() -> Bool {
        store.read(key: "claude.cliFallbackEnabled") ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "claude.cliFallbackEnabled")
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

    // MARK: - HookSettingsRepository

    public func isHookEnabled() -> Bool {
        store.read(key: "hook.enabled") ?? false
    }

    public func setHookEnabled(_ enabled: Bool) {
        store.write(value: enabled, key: "hook.enabled")
    }

    public func hookPort() -> Int {
        let port: Int = store.read(key: "hook.port") ?? Int(HookConstants.defaultPort)
        return port > 0 ? port : Int(HookConstants.defaultPort)
    }

    public func setHookPort(_ port: Int) {
        store.write(value: port, key: "hook.port")
    }
}
