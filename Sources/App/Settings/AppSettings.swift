import Foundation
import Domain
import Infrastructure

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

    /// The current theme mode (light, dark)
    public var themeMode: String {
        didSet {
            repository.setThemeMode(themeMode)
            if !isInitializing {
                userHasChosenTheme = true
            }
        }
    }

    /// Whether the user has explicitly chosen a theme
    public var userHasChosenTheme: Bool {
        didSet {
            repository.setUserHasChosenTheme(userHasChosenTheme)
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

    /// Whether quota-threshold notifications are enabled (default: true)
    public var quotaAlertsEnabled: Bool {
        didSet {
            repository.setQuotaAlertsEnabled(quotaAlertsEnabled)
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

    // MARK: - Internal

    private var isInitializing = true

    // MARK: - Initialization

    private init(repository: JSONSettingsRepository = .shared) {
        self.repository = repository

        // Load all values from repository
        self.themeMode = repository.themeMode()
        self.userHasChosenTheme = repository.userHasChosenTheme()
        self.backgroundSyncEnabled = repository.backgroundSyncEnabled()
        self.backgroundSyncInterval = repository.backgroundSyncInterval()
        self.quotaAlertsEnabled = repository.quotaAlertsEnabled()

        self.isInitializing = false
    }

    // MARK: - Provider Settings Access

    /// Access provider-specific settings for reading/writing in Settings UI.
    /// These are non-observable (loaded into @State) - only app-level settings are @Observable.
    public var provider: ProviderSettingsRepository { repository }
    public var codex: CodexSettingsRepository { repository }
}
