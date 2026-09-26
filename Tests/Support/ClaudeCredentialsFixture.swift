import Foundation

/// Writes a `~/.claude/.credentials.json` file under `directory`, for tests
/// that exercise `ClaudeCredentialLoader` / `ClaudeAPIUsageProbe`.
func createCredentialsFile(
    at directory: URL,
    accessToken: String = "test-access-token",
    refreshToken: String = "test-refresh-token",
    expiresAt: Double? = nil,
    subscriptionType: String? = nil
) throws {
    let claudeDir = directory.appendingPathComponent(".claude", isDirectory: true)
    try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)

    var oauthDict: [String: Any] = [
        "accessToken": accessToken,
        "refreshToken": refreshToken
    ]
    if let expiresAt {
        oauthDict["expiresAt"] = expiresAt
    }
    if let subscriptionType {
        oauthDict["subscriptionType"] = subscriptionType
    }

    let credentials: [String: Any] = [
        "claudeAiOauth": oauthDict
    ]

    let data = try JSONSerialization.data(withJSONObject: credentials, options: [.prettyPrinted])
    let filePath = claudeDir.appendingPathComponent(".credentials.json")
    try data.write(to: filePath)
}
