import Foundation
import Domain
import Infrastructure
import ServiceManagement

/// Observable settings manager for ClaudeBar preferences.
/// Thin `@Observable` wrapper around `AppSettingsRepository` for SwiftUI reactivity.
/// All persistence is delegated to the repository (`~/.claudebar/settings.json`).
@MainActor
@Observable
public final class AppSettings {
    public static let shared = AppSettings()

    /// The underlying repository (internal - views access settings through AppSettings properties/methods)
    private let repository: JSONSettingsRepository

    // MARK: - Theme Settings

    /// The current theme mode (light, dark, system, christmas)
    public var themeMode: String {
        didSet {
            repository.setThemeMode(themeMode)
            if !isInitializing {
                userHasChosenTheme = true
            }
        }
    }

    /// Whether the user has explicitly chosen a theme (vs auto-enabled Christmas)
    public var userHasChosenTheme: Bool {
        didSet {
            repository.setUserHasChosenTheme(userHasChosenTheme)
        }
    }

    // MARK: - Overview Mode Settings

    /// Whether to show all enabled providers at once instead of one at a time
    public var overviewModeEnabled: Bool {
        didSet {
            repository.setOverviewModeEnabled(overviewModeEnabled)
        }
    }

    // MARK: - Background Sync Settings

    /// Whether background sync is enabled (default: false)
    public var backgroundSyncEnabled: Bool {
        didSet {
            repository.setBackgroundSyncEnabled(backgroundSyncEnabled)
        }
    }

    /// Background sync interval in seconds (default: 60)
    public var backgroundSyncInterval: TimeInterval {
        didSet {
            repository.setBackgroundSyncInterval(backgroundSyncInterval)
        }
    }

    /// The background-refresh cadence (Off / 1 / 5 / 15 min) as a single
    /// picker-friendly value. Computed over the legacy `backgroundSyncEnabled`
    /// + `backgroundSyncInterval` pair so `settings.json` stays backward
    /// compatible — "Off" maps to `backgroundSyncEnabled == false`, the others
    /// to enabled + 60/300/600/900s. Setting it persists both underlying keys.
    public var refreshInterval: RefreshInterval {
        get {
            RefreshInterval.migrating(
                enabled: backgroundSyncEnabled,
                storedSeconds: backgroundSyncInterval
            )
        }
        set {
            // Set the interval before flipping enabled so anything observing the
            // change sees the final cadence in a single pass.
            if let seconds = newValue.seconds {
                backgroundSyncInterval = TimeInterval(seconds)
            }
            backgroundSyncEnabled = newValue.isEnabled
        }
    }

    // MARK: - Burn Rate Warning Settings

    /// Whether burn rate-based warnings are enabled (default: false, uses absolute thresholds)
    public var burnRateWarningEnabled: Bool {
        didSet {
            repository.setBurnRateWarningEnabled(burnRateWarningEnabled)
        }
    }

    /// The burn rate multiplier threshold above which warnings fire (default: 1.5)
    public var burnRateThreshold: Double {
        didSet {
            repository.setBurnRateThreshold(burnRateThreshold)
        }
    }

    // MARK: - Update Settings

    /// Whether to receive beta updates (default: false)
    public var receiveBetaUpdates: Bool {
        didSet {
            repository.setReceiveBetaUpdates(receiveBetaUpdates)
            NotificationCenter.default.post(name: .betaUpdatesSettingChanged, object: nil)
        }
    }

    // MARK: - Launch at Login Settings

    /// Whether the app should launch at login (backed by SMAppService, not JSON)
    public var launchAtLogin: Bool {
        didSet {
            guard !isInitializing else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Internal

    private var isInitializing = true

    // MARK: - Initialization

    private init(repository: JSONSettingsRepository = .shared) {
        self.repository = repository

        // Load all values from repository
        self.themeMode = repository.themeMode()
        self.userHasChosenTheme = repository.userHasChosenTheme()
        self.receiveBetaUpdates = repository.receiveBetaUpdates()
        self.burnRateWarningEnabled = repository.burnRateWarningEnabled()
        self.burnRateThreshold = repository.burnRateThreshold()
        self.overviewModeEnabled = repository.overviewModeEnabled()
        self.backgroundSyncEnabled = repository.backgroundSyncEnabled()
        self.backgroundSyncInterval = repository.backgroundSyncInterval()

        // Launch at login - read from SMAppService (system service, not JSON)
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        self.isInitializing = false
    }

    // MARK: - Provider Settings Access

    /// Access provider-specific settings for reading/writing in Settings UI.
    /// These are non-observable (loaded into @State) - only app-level settings are @Observable.
    public var provider: ProviderSettingsRepository { repository }
    public var codex: CodexSettingsRepository { repository }
}

// MARK: - Notification Names

extension Notification.Name {
    static let betaUpdatesSettingChanged = Notification.Name("betaUpdatesSettingChanged")
}
