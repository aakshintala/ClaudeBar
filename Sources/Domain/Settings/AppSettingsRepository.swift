import Foundation
import Mockable

/// Repository protocol for all app-level settings (display, sync, budget, etc.).
/// Provider-specific settings live in `ProviderSettingsRepository` sub-protocols.
///
/// Both protocols share one backing store (`~/.claudebar/settings.json`).
/// `AppSettings` wraps this as an `@Observable` for SwiftUI.
@Mockable
public protocol AppSettingsRepository: Sendable {
    // MARK: - Theme

    func themeMode() -> String
    func setThemeMode(_ mode: String)

    func userHasChosenTheme() -> Bool
    func setUserHasChosenTheme(_ chosen: Bool)

    // MARK: - Background Sync

    func backgroundSyncEnabled() -> Bool
    func setBackgroundSyncEnabled(_ enabled: Bool)

    func backgroundSyncInterval() -> TimeInterval
    func setBackgroundSyncInterval(_ interval: TimeInterval)

    // MARK: - Quota Alerts

    func quotaAlertsEnabled() -> Bool
    func setQuotaAlertsEnabled(_ enabled: Bool)
}
