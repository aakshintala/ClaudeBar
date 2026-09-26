import Foundation
import Domain

/// Infrastructure adapter that probes Cursor's usage API to fetch quota data.
///
/// Cursor stores its authentication in a local SQLite database. This probe:
/// 1. Reads the access token from `state.vscdb`
/// 2. Decodes the JWT to extract the user ID
/// 3. Calls `https://cursor.com/api/usage-summary` with cookie auth
/// 4. Parses the response into quota percentages
///
/// The auth cookie format is: `WorkosCursorSessionToken={userId}::{accessToken}`
///
/// Actual API response shape (usage-summary):
/// ```json
/// {
///   "membershipType": "ultra",
///   "isUnlimited": false,
///   "billingCycleStart": "2026-02-06T03:34:49.000Z",
///   "billingCycleEnd": "2026-03-06T03:34:49.000Z",
///   "individualUsage": {
///     "plan": {
///       "enabled": true,
///       "used": 326,
///       "limit": 40000,
///       "remaining": 39674
///     },
///     "onDemand": {
///       "enabled": false,
///       "used": 0,
///       "limit": null,
///       "remaining": null
///     }
///   }
/// }
/// ```

/// Caches the access token in memory for the probe's lifetime, keyed off the
/// JWT `exp` claim, so a normal refresh doesn't spawn `sqlite3`. Cleared on a
/// 401 so the next call re-reads the (possibly rotated) token from disk.
private actor CursorTokenCache {
    private var entry: (token: String, userId: String, expiresAt: Date)?

    func get() -> (token: String, userId: String)? {
        guard let entry, entry.expiresAt > Date() else { return nil }
        return (entry.token, entry.userId)
    }

    func set(token: String, userId: String, expiresAt: Date) {
        entry = (token, userId, expiresAt)
    }

    func clear() {
        entry = nil
    }
}

public struct CursorUsageProbe: UsageProbe {
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval
    private let dbPathOverride: String?
    private let tokenCache = CursorTokenCache()

    private static let usageSummaryURL = "https://cursor.com/api/usage-summary"

    /// The default path to Cursor's SQLite database on macOS
    static let defaultDatabasePath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    }()

    public init(
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15.0,
        dbPathOverride: String? = nil
    ) {
        self.networkClient = networkClient
        self.timeout = timeout
        self.dbPathOverride = dbPathOverride
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        let dbPath = dbPathOverride ?? Self.defaultDatabasePath
        let dbExists = FileManager.default.fileExists(atPath: dbPath)
        if !dbExists {
            AppLog.probes.debug("Cursor: Database not found at \(dbPath)")
        }
        return dbExists
    }

    public func probe() async throws -> UsageSnapshot {
        let dbPath = dbPathOverride ?? Self.defaultDatabasePath

        let (token, userId) = try await credentials(dbPath: dbPath)
        do {
            return try await fetchAndParse(token: token, userId: userId)
        } catch ProbeError.sessionExpired {
            // Cached token was stale (rotated or revoked); drop it and retry once.
            await tokenCache.clear()
            let (freshToken, freshUserId) = try await credentials(dbPath: dbPath)
            return try await fetchAndParse(token: freshToken, userId: freshUserId)
        }
    }

    private func fetchAndParse(token: String, userId: String) async throws -> UsageSnapshot {
        let cookie = "WorkosCursorSessionToken=\(userId)::\(token)"

        AppLog.probes.debug("Cursor: Fetching usage summary...")

        let response = try await fetchUsageSummary(cookie: cookie)
        let snapshot = try Self.parseUsageSummary(response)

        AppLog.probes.debug("Cursor: Probe success - \(snapshot.quotas.count) quotas found")
        return snapshot
    }

    /// Returns the cached token/user id if it hasn't expired, otherwise reads
    /// (and caches) a fresh one from Cursor's SQLite database.
    private func credentials(dbPath: String) async throws -> (token: String, userId: String) {
        if let cached = await tokenCache.get() {
            return cached
        }

        guard FileManager.default.fileExists(atPath: dbPath) else {
            AppLog.probes.error("Cursor: Database not found at \(dbPath)")
            throw ProbeError.cliNotFound("Cursor (database not found)")
        }

        AppLog.probes.debug("Cursor: Reading auth token from database...")

        let accessToken = try await readAccessToken(from: dbPath)
        let (userId, expiresAt) = try Self.decodeJWT(accessToken)
        // No `exp` claim to cache against: re-read next time rather than guess a TTL.
        if let expiresAt {
            await tokenCache.set(token: accessToken, userId: userId, expiresAt: expiresAt)
        }
        return (accessToken, userId)
    }

    // MARK: - Token Extraction

    /// Reads the access token from Cursor's SQLite database using the sqlite3 CLI.
    private func readAccessToken(from dbPath: String) async throws -> String {
        let result: (status: Int32, stdout: Data)
        do {
            result = try await runProcess("/usr/bin/sqlite3", [dbPath, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"])
        } catch {
            AppLog.probes.error("Cursor: Failed to run sqlite3 - \(error.localizedDescription)")
            throw ProbeError.executionFailed("Failed to read Cursor database: \(error.localizedDescription)")
        }

        guard result.status == 0 else {
            AppLog.probes.error("Cursor: sqlite3 exited with status \(result.status)")
            throw ProbeError.executionFailed("sqlite3 exited with status \(result.status)")
        }

        let token = String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !token.isEmpty else {
            AppLog.probes.error("Cursor: No access token found in database (not logged in?)")
            throw ProbeError.authenticationRequired
        }

        return token
    }

    /// Extracts the user ID (`sub` claim) from a JWT token by base64-decoding the payload.
    static func extractUserIdFromJWT(_ token: String) throws -> String {
        try decodeJWT(token).userId
    }

    /// Decodes a JWT's payload, returning the `sub` claim and, if present, the
    /// `exp` claim as a `Date` (used to know how long the token is cacheable).
    static func decodeJWT(_ token: String) throws -> (userId: String, expiresAt: Date?) {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            throw ProbeError.parseFailed("Invalid JWT format")
        }

        // JWT payload is base64url-encoded
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad to multiple of 4
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let payloadData = Data(base64Encoded: base64) else {
            throw ProbeError.parseFailed("Failed to decode JWT payload")
        }

        guard let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let sub = json["sub"] as? String, !sub.isEmpty else {
            throw ProbeError.parseFailed("JWT payload missing 'sub' claim")
        }

        let expiresAt = (json["exp"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return (sub, expiresAt)
    }

    // MARK: - API Call

    private func fetchUsageSummary(cookie: String) async throws -> Data {
        guard let url = URL(string: Self.usageSummaryURL) else {
            throw ProbeError.executionFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        AppLog.probes.debug("Cursor: API response status \(httpResponse.statusCode)")

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401:
            AppLog.probes.error("Cursor: Authentication failed (401) - token may be expired")
            throw ProbeError.sessionExpired(hint: "Re-authenticate in Cursor settings.")
        case 403:
            AppLog.probes.error("Cursor: Forbidden (403)")
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("Cursor: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Response Parsing (static for testability)

    /// Parses the Cursor usage-summary API response into a UsageSnapshot.
    ///
    /// The API returns usage nested under `individualUsage.plan` and `individualUsage.onDemand`.
    public static func parseUsageSummary(_ data: Data) throws -> UsageSnapshot {
        let json: [String: Any]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ProbeError.parseFailed("Response is not a JSON object")
            }
            json = parsed
        } catch let error as ProbeError {
            throw error
        } catch {
            throw ProbeError.parseFailed("Invalid JSON: \(error.localizedDescription)")
        }

        var quotas: [UsageQuota] = []

        let membershipType = json["membershipType"] as? String ?? "unknown"
        let limitType = json["limitType"] as? String ?? ""

        // Parse billing cycle dates for reset time
        var resetsAt: Date?
        if let cycleEnd = json["billingCycleEnd"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: cycleEnd) {
                resetsAt = date
            } else {
                // Try without fractional seconds
                formatter.formatOptions = [.withInternetDateTime]
                resetsAt = formatter.date(from: cycleEnd)
            }
        }

        // The API nests usage under "individualUsage" with "plan" and "onDemand" sub-objects
        let individualUsage = json["individualUsage"] as? [String: Any]

        // Parse plan usage (included requests)
        if let planUsage = individualUsage?["plan"] as? [String: Any],
           let enabled = planUsage["enabled"] as? Bool, enabled {
            let used = Self.intValue(from: planUsage, key: "used") ?? 0
            let limit = Self.intValue(from: planUsage, key: "limit") ?? 0

            // The `used`/`limit` fields describe only the *included* base allotment. Users
            // with bonus credits have `limit` maxed (used == limit) while real capacity is
            // `breakdown.total` (included + bonus). Enterprise plans report `limit == 0` and
            // carry everything in the breakdown. Use the larger of the two as the true
            // capacity so bonus credits aren't ignored.
            let breakdown = planUsage["breakdown"] as? [String: Any]
            let breakdownTotal = breakdown.flatMap { Self.intValue(from: $0, key: "total") } ?? 0
            let effectiveLimit = max(limit, breakdownTotal)

            if effectiveLimit > 0 {
                // `totalPercentUsed` is Cursor's authoritative usage figure across the full
                // capacity (matches the "You've used X%" message in Cursor's own UI). Prefer
                // it; fall back to used/limit only when the API doesn't provide it.
                let percentRemaining: Double
                let effectiveUsed: Int
                if let totalPercentUsed = planUsage["totalPercentUsed"] as? Double {
                    percentRemaining = 100 - totalPercentUsed
                    effectiveUsed = Int((totalPercentUsed * Double(effectiveLimit) / 100).rounded())
                } else {
                    effectiveUsed = used
                    percentRemaining = Double(effectiveLimit - used) / Double(effectiveLimit) * 100
                }

                quotas.append(UsageQuota(
                    percentRemaining: max(0, percentRemaining),
                    quotaType: .timeLimit("Monthly"),
                    providerId: "cursor",
                    resetsAt: resetsAt,
                    resetText: "\(effectiveUsed)/\(effectiveLimit) requests",
                    unitsUsed: effectiveUsed,
                    unitsLimit: effectiveLimit
                ))
            }
        }

        // Parse on-demand usage (usage-based pricing)
        if let onDemand = individualUsage?["onDemand"] as? [String: Any],
           let enabled = onDemand["enabled"] as? Bool, enabled {
            let used = Self.intValue(from: onDemand, key: "used") ?? 0
            let limit = Self.intValue(from: onDemand, key: "limit") ?? 0

            if limit > 0 {
                let percentRemaining = Double(limit - used) / Double(limit) * 100
                quotas.append(UsageQuota(
                    percentRemaining: max(0, percentRemaining),
                    quotaType: .timeLimit("On-Demand"),
                    providerId: "cursor",
                    resetsAt: resetsAt,
                    resetText: "\(used)/\(limit) on-demand",
                    unitsUsed: used,
                    unitsLimit: limit
                ))
            }
        }

        // Parse team usage for enterprise plans (limitType == "team")
        if limitType == "team",
           let teamUsage = json["teamUsage"] as? [String: Any],
           let teamOnDemand = teamUsage["onDemand"] as? [String: Any],
           let teamEnabled = teamOnDemand["enabled"] as? Bool, teamEnabled {
            let used = Self.intValue(from: teamOnDemand, key: "used") ?? 0
            let limit = Self.intValue(from: teamOnDemand, key: "limit") ?? 0

            if limit > 0 {
                let percentRemaining = Double(limit - used) / Double(limit) * 100
                quotas.append(UsageQuota(
                    percentRemaining: max(0, percentRemaining),
                    quotaType: .timeLimit("Team"),
                    providerId: "cursor",
                    resetsAt: resetsAt,
                    resetText: "\(used)/\(limit) team credits",
                    unitsUsed: used,
                    unitsLimit: limit
                ))
            }
        }

        // Check for unlimited plans
        if let isUnlimited = json["isUnlimited"] as? Bool, isUnlimited {
            quotas.append(UsageQuota(
                percentRemaining: 100,
                quotaType: .timeLimit("Monthly"),
                providerId: "cursor",
                resetText: "Unlimited"
            ))
        }

        // If no quotas found, the user might be on a free plan with no data
        guard !quotas.isEmpty else {
            throw ProbeError.parseFailed("No usage data found in Cursor response")
        }

        // Determine account tier from membership type
        let tier: AccountTier? = switch membershipType.lowercased() {
        case "pro": .custom("PRO")
        case "business": .custom("BUSINESS")
        case "free": .custom("FREE")
        case "ultra": .custom("ULTRA")
        case "enterprise": .custom("ENTERPRISE")
        default: membershipType.isEmpty ? nil : .custom(membershipType.uppercased())
        }

        return UsageSnapshot(
            providerId: "cursor",
            quotas: quotas,
            capturedAt: Date(),
            accountTier: tier
        )
    }

    /// Safely extracts an Int from a JSON dictionary value that could be Int, Double, or NSNumber.
    private static func intValue(from dict: [String: Any], key: String) -> Int? {
        if let intVal = dict[key] as? Int {
            return intVal
        }
        if let doubleVal = dict[key] as? Double {
            return Int(doubleVal)
        }
        return nil
    }
}
