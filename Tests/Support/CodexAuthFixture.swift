import Foundation

/// Writes a `~/.codex/auth.json` file under `directory`, for tests that
/// exercise `CodexCredentialLoader` / `CodexAPIUsageProbe`.
func createAuthFile(
    at directory: URL,
    accessToken: String = "test-access-token",
    refreshToken: String = "test-refresh-token",
    accountId: String? = nil,
    lastRefresh: String? = nil
) throws {
    let codexDir = directory.appendingPathComponent(".codex", isDirectory: true)
    try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)

    var tokens: [String: Any] = [
        "access_token": accessToken,
        "refresh_token": refreshToken
    ]
    if let accountId {
        tokens["account_id"] = accountId
    }

    var auth: [String: Any] = [
        "tokens": tokens
    ]
    if let lastRefresh {
        auth["last_refresh"] = lastRefresh
    } else {
        // Set a recent last_refresh so we don't trigger a proactive refresh
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        auth["last_refresh"] = formatter.string(from: Date())
    }

    let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
    let filePath = codexDir.appendingPathComponent("auth.json")
    try data.write(to: filePath)
}
