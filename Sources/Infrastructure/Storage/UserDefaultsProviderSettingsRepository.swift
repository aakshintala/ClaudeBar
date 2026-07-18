import Foundation
import Domain

/// UserDefaults-based implementation of ProviderSettingsRepository and its sub-protocols.
/// Persists provider settings like isEnabled state and provider-specific configuration.
public final class UserDefaultsProviderSettingsRepository: BedrockSettingsRepository, ClaudeSettingsRepository, CodexSettingsRepository, HookSettingsRepository, @unchecked Sendable {
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

    public func customCardURL(forProvider id: String) -> String? {
        userDefaults.string(forKey: "provider.\(id).customCardURL")
    }

    public func setCustomCardURL(_ url: String?, forProvider id: String) {
        if let url, !url.isEmpty {
            userDefaults.set(url, forKey: "provider.\(id).customCardURL")
        } else {
            userDefaults.removeObject(forKey: "provider.\(id).customCardURL")
        }
    }

    // MARK: - ClaudeSettingsRepository

    public func claudeProbeMode() -> ClaudeProbeMode {
        guard let rawValue = userDefaults.string(forKey: Keys.claudeProbeMode) else {
            return .cli // Default to CLI mode
        }
        return ClaudeProbeMode(rawValue: rawValue) ?? .cli
    }

    public func setClaudeProbeMode(_ mode: ClaudeProbeMode) {
        userDefaults.set(mode.rawValue, forKey: Keys.claudeProbeMode)
    }

    public func claudeCliFallbackEnabled() -> Bool {
        userDefaults.object(forKey: Keys.claudeCliFallbackEnabled) as? Bool ?? true
    }

    public func setClaudeCliFallbackEnabled(_ enabled: Bool) {
        userDefaults.set(enabled, forKey: Keys.claudeCliFallbackEnabled)
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

    // MARK: - BedrockSettingsRepository

    public func awsProfileName() -> String {
        userDefaults.string(forKey: Keys.awsProfileName) ?? ""
    }

    public func setAWSProfileName(_ name: String) {
        userDefaults.set(name, forKey: Keys.awsProfileName)
    }

    public func bedrockRegions() -> [String] {
        userDefaults.stringArray(forKey: Keys.bedrockRegions) ?? ["us-east-1"]
    }

    public func setBedrockRegions(_ regions: [String]) {
        userDefaults.set(regions, forKey: Keys.bedrockRegions)
    }

    public func bedrockDailyBudget() -> Decimal? {
        guard let doubleValue = userDefaults.object(forKey: Keys.bedrockDailyBudget) as? Double else {
            return nil
        }
        return Decimal(doubleValue)
    }

    public func setBedrockDailyBudget(_ amount: Decimal?) {
        if let amount {
            userDefaults.set(NSDecimalNumber(decimal: amount).doubleValue, forKey: Keys.bedrockDailyBudget)
        } else {
            userDefaults.removeObject(forKey: Keys.bedrockDailyBudget)
        }
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
        // Claude settings
        static let claudeProbeMode = "providerConfig.claudeProbeMode"
        static let claudeCliFallbackEnabled = "providerConfig.claudeCliFallbackEnabled"
        // Codex settings
        static let codexProbeMode = "providerConfig.codexProbeMode"
        // Bedrock settings
        static let awsProfileName = "providerConfig.awsProfileName"
        static let bedrockRegions = "providerConfig.bedrockRegions"
        static let bedrockDailyBudget = "providerConfig.bedrockDailyBudget"
    }

    /// Generates the UserDefaults key for a provider's enabled state
    private static func enabledKey(forProvider id: String) -> String {
        "provider.\(id).isEnabled"
    }
}
