import Foundation
import Domain

/// Loads the OpenCode Go API key from opencode's local auth store.
///
/// opencode CLI writes provider credentials to `auth.json` inside its XDG data
/// directory — `$XDG_DATA_HOME/opencode/auth.json`, falling back to
/// `~/.local/share/opencode/auth.json` when `XDG_DATA_HOME` is unset. This
/// mirrors opencode's own path resolution (verified via `opencode db path`
/// under `XDG_DATA_HOME` overrides).
///
/// File shape:
/// ```json
/// { "opencode-go": { "type": "api", "key": "sk-..." } }
/// ```
public struct OpenCodeCredentialLoader: Sendable {
    private let homeDirectory: String
    private let environment: [String: String]

    public init(
        homeDirectory: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.homeDirectory = homeDirectory
        self.environment = environment
    }

    /// The path to opencode's auth file.
    public var authFilePath: String {
        let dataHome = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (homeDirectory as NSString).appendingPathComponent(".local/share")
        return (dataHome as NSString).appendingPathComponent("opencode/auth.json")
    }

    /// Loads the OpenCode Go API key. Returns nil if the file is missing,
    /// unreadable, or has no `opencode-go` entry with a non-empty `key`.
    public func loadAPIKey() -> String? {
        let path = authFilePath
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entry = json["opencode-go"] as? [String: Any],
                  let key = entry["key"] as? String,
                  !key.isEmpty else {
                return nil
            }
            return key
        } catch {
            AppLog.credentials.error("Failed to load OpenCode Go credentials from file: \(error.localizedDescription)")
            return nil
        }
    }
}
