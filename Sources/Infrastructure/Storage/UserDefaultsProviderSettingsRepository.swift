import Foundation
import Domain

/// UserDefaults-based implementation of ProviderSettingsRepository and its sub-protocols.
/// Persists provider settings like isEnabled state and provider-specific configuration.
public final class UserDefaultsProviderSettingsRepository: CodexSettingsRepository, HookSettingsRepository, @unchecked Sendable {
    /// Shared singleton instance
    public static let shared = UserDefaultsProviderSettingsRepository()

    /// The UserDefaults instance to use
    private let userDefaults: UserDefaults

    /// Creates a new repository with the specified UserDefaults instance
    /// - Parameter userDefaults: The UserDefaults to use (defaults to .standard)
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - ProviderSettingsRepository

    public func isEnabled(forProvider id: String, defaultValue: Bool) -> Bool {
        let key = Self.enabledKey(forProvider: id)
        guard userDefaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return userDefaults.bool(forKey: key)
    }

    public func setEnabled(_ enabled: Bool, forProvider id: String) {
        let key = Self.enabledKey(forProvider: id)
        userDefaults.set(enabled, forKey: key)
    }

    // MARK: - CodexSettingsRepository

    public func codexProbeMode() -> CodexProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.codexProbeMode) else {
            return .rpc // Default to RPC mode
        }
        return CodexProbeMode(rawValue: rawValue) ?? .rpc
    }

    public func setCodexProbeMode(_ mode: CodexProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.codexProbeMode)
    }

    // MARK: - HookSettingsRepository

    public func isHookEnabled() -> Bool {
        guard userDefaults.object(forKey: Keys.hookEnabled) != nil else {
            return false
        }
        return userDefaults.bool(forKey: Keys.hookEnabled)
    }

    public func setHookEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Keys.hookEnabled)
    }

    public func hookPort() -> Int {
        let port = userDefaults.integer(forKey: Keys.hookPort)
        return port > 0 ? port : Int(HookConstants.defaultPort)
    }

    public func setHookPort(_ port: Int) {
        userDefaults.set(port, forKey: Keys.hookPort)
    }

    // MARK: - Keys

    private enum Keys {
        // Hook settings
        static let hookEnabled = "hookConfig.enabled"
        static let hookPort = "hookConfig.port"
        // Codex settings
        static let codexProbeMode = "providerConfig.codexProbeMode"
    }

    /// Generates the UserDefaults key for a provider's enabled state
    private static func enabledKey(forProvider id: String) -> String {
        "provider.\(id).isEnabled"
    }
}
