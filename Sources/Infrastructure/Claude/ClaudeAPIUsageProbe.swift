import Foundation
import Domain
import Synchronization

/// Thread-safe value with a time-to-live. Holds the last successful
/// `UsageSnapshot` (quota numbers move on multi-hour timescales, so a short
/// window costs no freshness and spares the rate-limited endpoint) and the
/// loaded OAuth credentials (so external changes such as a CLI re-login are
/// picked up within the TTL). Expiry is inclusive, so a TTL of 0 never hits.
private final class TTLBox<Value: Sendable>: Sendable {
    private let ttl: TimeInterval
    private let entry = Mutex<(value: Value, storedAt: Date)?>(nil)

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func get(now: Date = Date()) -> Value? {
        entry.withLock { entry in
            guard let current = entry, now.timeIntervalSince(current.storedAt) < ttl else {
                entry = nil
                return nil
            }
            return current.value
        }
    }

    /// Stores `value` stamped with `now`; `nil` clears the box.
    func set(_ value: Value?, now: Date = Date()) {
        entry.withLock { $0 = value.map { ($0, now) } }
    }
}

/// Thread-safe holder for an active rate-limit window. When the API returns
/// HTTP 429, the probe stores `retryAt` here so subsequent calls short-circuit
/// without re-hitting the endpoint until the window has elapsed.
private final class RateLimitState: @unchecked Sendable {
    private var retryAt: Date?
    private let lock = NSLock()

    /// Returns `retryAt` only if it is still in the future; otherwise clears
    /// it and returns nil so the next probe is allowed through.
    func activeRetryAt(now: Date = Date()) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        guard let retryAt else { return nil }
        if retryAt <= now {
            self.retryAt = nil
            return nil
        }
        return retryAt
    }

    /// Records a new rate-limit window expiring at `retryAt`. Subsequent
    /// `activeRetryAt` calls return this value until it falls into the past.
    func set(retryAt: Date) {
        lock.lock()
        defer { lock.unlock() }
        self.retryAt = retryAt
    }
}

/// Claude API-based usage probe that fetches quota data directly from Anthropic's OAuth API.
///
/// This probe uses the user's OAuth credentials (from `~/.claude/.credentials.json` or Keychain)
/// to call the usage API endpoint. It automatically refreshes expired tokens.
///
/// Usage URL: `https://api.anthropic.com/api/oauth/usage`
/// Token Refresh URL: `https://platform.claude.com/v1/oauth/token`
public struct ClaudeAPIUsageProbe: UsageProbe, @unchecked Sendable {
    private let credentialLoader: ClaudeCredentialLoader
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval
    private let cache = TTLBox<ClaudeCredentialResult>(ttl: 5 * 60)
    private let rateLimit = RateLimitState()
    private let snapshotCache: TTLBox<UsageSnapshot>

    /// Fallback retry window applied when the API returns 429 without a
    /// usable `Retry-After` header. Five minutes is conservative enough to
    /// stop hammering a throttled endpoint while still picking back up
    /// reasonably quickly once the window opens.
    static let defaultRetryAfter: TimeInterval = 5 * 60

    /// TTL for the in-memory snapshot cache: the app's only Claude rate-limit
    /// guard besides the 429 backoff. It applies to forced refreshes too, so
    /// at most one usage call reaches Anthropic per 5 minutes. The init
    /// parameter exists for tests.
    public static let snapshotCacheTTL: TimeInterval = 5 * 60

    // API endpoints
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    // OAuth configuration (from Claude Code)
    // client_id being used here is the official client_id being used for Claude Code CLI. It might be changed if Claude Code got updated.
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    // Only request scopes that are typically granted - do NOT add extra scopes like user:mcp_servers
    private static let scopes = "user:profile user:inference user:sessions:claude_code"

    public init(
        credentialLoader: ClaudeCredentialLoader = ClaudeCredentialLoader(),
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15,
        snapshotCacheTTL: TimeInterval = Self.snapshotCacheTTL
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.timeout = timeout
        self.snapshotCache = TTLBox(ttl: snapshotCacheTTL)
    }

    public func isAvailable() async -> Bool {
        if cache.get() != nil { return true }
        return await credentialLoader.loadCredentials() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        // Serve a fresh cached snapshot before doing anything else. This is
        // the dominant code path during normal monitor polling and means
        // we make ~1 actual HTTP call per cache TTL instead of one per
        // monitor tick — well under Anthropic's per-token throttle.
        if let cached = snapshotCache.get() {
            return cached
        }

        // Honor an active rate-limit window before doing any work so we stop
        // hammering the endpoint while Anthropic is throttling us.
        if let retryAt = rateLimit.activeRetryAt() {
            AppLog.probes.info("Claude API: Skipping probe — rate-limited until \(retryAt)")
            throw ProbeError.rateLimited(retryAt: retryAt)
        }

        // Check cache first, fall back to loading from file/keychain
        // Only update cache when loading from file (not from cache hit) to preserve TTL
        // 仅在从文件加载时更新缓存，避免滑动续期导致 TTL 永不过期
        let fromCache = cache.get()
        var loaded = fromCache
        if loaded == nil { loaded = await credentialLoader.loadCredentials() }
        guard var credentials = loaded else {
            AppLog.probes.error("Claude API: No credentials found")
            throw ProbeError.authenticationRequired
        }
        if fromCache == nil {
            cache.set(credentials)
        }

        // Check if token needs refresh
        if credentialLoader.needsRefresh(credentials.oauth) {
            if credentials.oauth.refreshToken != nil {
                AppLog.probes.info("Claude API: Token expired or expiring soon, refreshing...")
                do {
                    credentials = try await refreshToken(credentials)
                } catch let refreshError {
                    // Clear cache so next probe reloads from file (CLI may have re-authenticated)
                    // 清除缓存，下次 probe 会从文件重新加载（CLI 可能已重新登录）
                    cache.set(nil)

                    // Try reloading from file — CLI may have updated credentials externally
                    // 尝试从文件重新加载——CLI 可能已在外部更新了凭证
                    if let freshCredentials = await credentialLoader.loadCredentials(),
                       freshCredentials.oauth != credentials.oauth {
                        AppLog.probes.info("Claude API: Found updated credentials from file, retrying...")
                        credentials = freshCredentials
                        cache.set(credentials)
                        // Re-check if the fresh credentials also need refresh
                        if credentialLoader.needsRefresh(credentials.oauth) {
                            do {
                                credentials = try await refreshToken(credentials)
                            } catch {
                                AppLog.probes.error("Claude API: Retry with fresh credentials also failed: \(error.localizedDescription)")
                                cache.set(nil)
                                throw error
                            }
                        }
                        // Fresh credentials are valid, continue to fetch usage
                    } else {
                        AppLog.probes.error("Claude API: Token refresh failed: \(refreshError.localizedDescription)")
                        throw refreshError
                    }
                }
            } else {
                // Long-lived token (e.g. from `claude setup-token`) — no refresh mechanism.
                // Proceed directly with the token; the API call will fail with 401 if it's actually expired.
                AppLog.probes.info("Claude API: Token has no expiry info and no refresh token (setup-token), proceeding...")
            }
        }

        // Fetch usage data
        let usageData: Data
        do {
            usageData = try await fetchUsage(accessToken: credentials.oauth.accessToken)
        } catch let error as ProbeError where error == .authenticationRequired {
            // Token might have been invalidated, try refreshing once
            // Token 可能已被外部失效，尝试刷新一次
            if credentials.oauth.refreshToken != nil {
                AppLog.probes.info("Claude API: Got 401/403, attempting token refresh...")
                do {
                    credentials = try await refreshToken(credentials)
                    usageData = try await fetchUsage(accessToken: credentials.oauth.accessToken)
                } catch {
                    // Clear cache on auth failure so next probe reloads from file
                    // 认证失败时清除缓存，下次 probe 从文件重新加载
                    cache.set(nil)
                    AppLog.probes.error("Claude API: Retry after refresh failed: \(error.localizedDescription)")
                    throw error
                }
            } else {
                // No refresh token (setup-token) — can't recover from 401/403
                AppLog.probes.error("Claude API: Got 401/403 with no refresh token available")
                cache.set(nil)
                throw error
            }
        }

        let snapshot = try Self.parse(usageData, subscriptionType: credentials.oauth.subscriptionType, now: Date())
        snapshotCache.set(snapshot)
        return snapshot
    }

    // MARK: - Token Refresh

    private func refreshToken(_ credentials: ClaudeCredentialResult) async throws -> ClaudeCredentialResult {
        guard let refreshToken = credentials.oauth.refreshToken else {
            AppLog.probes.error("Claude API: No refresh token available")
            throw ProbeError.authenticationRequired
        }

        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": Self.clientID,
            "scope": Self.scopes
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        AppLog.probes.debug("Claude API: Refreshing token...")

        let (data, response) = try await networkClient.request(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response from token refresh")
        }

        // Handle error responses
        if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
            // Log raw response for debugging
            if let rawBody = String(data: data, encoding: .utf8) {
                AppLog.probes.debug("Claude API: Token refresh error response: \(rawBody)")
            }

            // Check for specific OAuth errors
            if let errorResponse = try? Self.decoder.decode(TokenErrorResponse.self, from: data) {
                AppLog.probes.error("Claude API: Token refresh failed - error: \(errorResponse.error ?? "unknown"), description: \(errorResponse.errorDescription ?? "none")")

                if errorResponse.error == "invalid_grant" {
                    AppLog.probes.error("Claude API: Session expired (invalid_grant) - run `claude` to re-authenticate")
                    cache.set(nil)
                    throw ProbeError.sessionExpired(hint: "Run `claude` in terminal to log in again.")
                }
            }
            AppLog.probes.error("Claude API: Token expired or invalid (HTTP \(httpResponse.statusCode))")
            cache.set(nil)
            throw ProbeError.sessionExpired(hint: "Run `claude` in terminal to log in again.")
        }

        guard httpResponse.statusCode >= 200, httpResponse.statusCode < 300 else {
            AppLog.probes.error("Claude API: Token refresh failed with HTTP \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("Token refresh failed: HTTP \(httpResponse.statusCode)")
        }

        // Parse refresh response
        let refreshResponse = try Self.decoder.decode(TokenRefreshResponse.self, from: data)

        guard let newAccessToken = refreshResponse.accessToken, !newAccessToken.isEmpty else {
            AppLog.probes.error("Claude API: No access token in refresh response")
            throw ProbeError.executionFailed("No access token in refresh response")
        }

        // Update credentials
        var updatedCredentials = credentials
        updatedCredentials.oauth.accessToken = newAccessToken
        if let newRefreshToken = refreshResponse.refreshToken {
            updatedCredentials.oauth.refreshToken = newRefreshToken
        }
        if let expiresIn = refreshResponse.expiresIn {
            updatedCredentials.oauth.expiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn) * 1000
        }

        // Save updated credentials and update cache
        await credentialLoader.saveCredentials(updatedCredentials)
        cache.set(updatedCredentials)

        AppLog.probes.info("Claude API: Token refreshed successfully")
        return updatedCredentials
    }

    // MARK: - Usage Fetch

    private func fetchUsage(accessToken: String) async throws -> Data {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("ClaudeBar", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        AppLog.probes.debug("Claude API: Fetching usage...")

        let (data, _) = try await networkClient.send(request, label: "Claude API") { httpResponse in
            guard httpResponse.statusCode == 429 else { return nil }
            let retryAfter = Self.parseRetryAfter(
                httpResponse.value(forHTTPHeaderField: "Retry-After")
            ) ?? Self.defaultRetryAfter
            let retryAt = Date().addingTimeInterval(retryAfter)
            rateLimit.set(retryAt: retryAt)
            AppLog.probes.warning("Claude API: Rate limited (HTTP 429), retrying after \(Int(retryAfter))s")
            return .rateLimited(retryAt: retryAt)
        }

        if let rawString = String(data: data, encoding: .utf8) {
            AppLog.probes.debug("Claude API: Raw response: \(rawString.prefix(500))")
        }
        return data
    }

    // MARK: - Response Parsing

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Parses an `/api/oauth/usage` response body into a snapshot.
    static func parse(_ data: Data, subscriptionType: String?, now: Date) throws -> UsageSnapshot {
        let response: UsageResponse
        do {
            response = try decoder.decode(UsageResponse.self, from: data)
        } catch {
            AppLog.probes.error("Claude API: Failed to parse response: \(error.localizedDescription)")
            throw ProbeError.parseFailed("Failed to parse usage response: \(error.localizedDescription)")
        }

        let windows: [(UsageQuotaData?, QuotaType)] = [
            (response.fiveHour, .session),
            (response.sevenDay, .weekly),
            (response.sevenDaySonnet, .modelSpecific("sonnet")),
            (response.sevenDayOpus, .modelSpecific("opus")),
        ]
        var quotas = windows.compactMap { window, quotaType in
            window?.utilization.map {
                UsageQuota(percentRemaining: 100 - $0, quotaType: quotaType, providerId: "claude",
                           resetsAt: parseISO8601(window?.resetsAt))
            }
        }

        // Parse model-scoped limits from the generic `limits` array (e.g. Fable).
        // Session/weekly entries there mirror `five_hour`/`seven_day` and are
        // skipped; a model already covered by a legacy field is not duplicated.
        // If the legacy `five_hour`/`seven_day` fields ever go null (as
        // `seven_day_opus`/`seven_day_sonnet` did), extend this loop to the
        // `session`/`weekly_all` kinds.
        for entry in response.limits ?? [] {
            guard entry.kind == "weekly_scoped",
                  // Key on the first word of the display name ("Fable 5" -> "fable")
                  // so a persisted "model:<name>" menu-bar selection stays stable.
                  let modelName = entry.scope?.model?.displayName?
                      .split(separator: " ").first.map({ $0.lowercased() }),
                  !modelName.isEmpty,
                  let percent = entry.percent else {
                continue
            }
            let quotaType = QuotaType.modelSpecific(modelName)
            guard !quotas.contains(where: { $0.quotaType == quotaType }) else {
                continue
            }
            quotas.append(UsageQuota(
                percentRemaining: 100.0 - percent,
                quotaType: quotaType,
                providerId: "claude",
                resetsAt: parseISO8601(entry.resetsAt)
            ))
        }

        // Prefer the current spend payload, then fall back to legacy
        // extra_usage. A shape with a present-but-invalid cap is dropped
        // (falls through) rather than reclassified as uncapped.
        let costUsage = (response.spend?.costPair ?? response.extraUsage?.costPair).map {
            CostUsage(totalCost: $0.used, budget: $0.cap, providerId: "claude", kind: .extraUsage, capturedAt: now)
        }

        let accountTier = parseAccountTier(subscriptionType)

        AppLog.probes.info("Claude API: Parsed \(quotas.count) quotas, tier=\(accountTier?.badgeText ?? "unknown")")

        return UsageSnapshot(
            providerId: "claude",
            quotas: quotas,
            capturedAt: now,
            accountTier: accountTier,
            costUsage: costUsage
        )
    }

    /// Parses an HTTP `Retry-After` header value into a duration.
    /// Per RFC 7231 the value is either a non-negative integer of seconds, or
    /// an HTTP-date. Returns nil for missing, malformed, or past-dated values
    /// so the caller can apply its own fallback.
    static func parseRetryAfter(_ value: String?, now: Date = Date()) -> TimeInterval? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        // Reject 0 — the /api/oauth/usage endpoint has been observed returning
        // `Retry-After: 0` while continuing to 429, so treating 0 as "retry
        // immediately" lands us right back in a hammering loop. See
        // anthropics/claude-code#30930.
        if let seconds = TimeInterval(value), seconds > 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        let delta = date.timeIntervalSince(now)
        return delta > 0 ? delta : nil
    }

    private static func parseAccountTier(_ subscriptionType: String?) -> AccountTier? {
        guard let subscriptionType else { return nil }

        switch subscriptionType.lowercased() {
        case "claude_max", "max":
            return .claudeMax
        case "claude_pro", "pro":
            return .claudePro
        case "api", "claude_api":
            return .claudeApi
        default:
            return .custom(subscriptionType)
        }
    }
}

// MARK: - Response Models (snake_case keys, decoded with `.convertFromSnakeCase`)

private struct UsageResponse: Decodable {
    let fiveHour: UsageQuotaData?
    let sevenDay: UsageQuotaData?
    let sevenDaySonnet: UsageQuotaData?
    let sevenDayOpus: UsageQuotaData?
    let extraUsage: ExtraUsageData?
    let spend: SpendData?
    let limits: [LimitEntry]?
}

/// Entry in the newer generic `limits` array. Model-scoped limits (e.g. Fable)
/// are reported here as `kind: "weekly_scoped"` with the model in `scope`,
/// instead of dedicated `seven_day_<model>` fields.
private struct LimitEntry: Decodable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?
    let scope: LimitScope?
}

private struct LimitScope: Decodable {
    let model: LimitScopeModel?
}

private struct LimitScopeModel: Decodable {
    let displayName: String?
}

private struct UsageQuotaData: Decodable {
    let utilization: Double?
    let resetsAt: String?
}

private struct SpendData: Decodable {
    let used: MoneyData?
    let limit: MoneyData?
    let enabled: Bool?

    /// The decoded (used, cap) pair, or `nil` when the shape is disabled or
    /// invalid. A `nil` cap inside the pair means genuinely uncapped
    /// (`limit` absent or JSON null). A present-but-invalid `limit` poisons
    /// the whole shape instead of silently reading as "no monthly cap".
    var costPair: (used: Decimal, cap: Decimal?)? {
        guard enabled == true, let used = used?.amount else { return nil }
        guard let limit else { return (used, nil) }
        guard let cap = limit.amount else { return nil }
        return (used, cap)
    }
}

private struct MoneyData: Decodable {
    let amountMinor: Decimal?
    let currency: String?
    let exponent: Int?

    /// Negative spend is not a valid payload state; reject the row rather
    /// than silently flipping the sign.
    var amount: Decimal? {
        guard let amountMinor, amountMinor >= 0, let exponent, exponent >= 0 else { return nil }
        return Decimal(sign: .plus, exponent: -exponent, significand: amountMinor)
    }
}

private struct ExtraUsageData: Decodable {
    let isEnabled: Bool?
    let usedCredits: Decimal?
    let monthlyLimit: Decimal?
    let decimalPlaces: Int?

    /// Same cap semantics as `SpendData.costPair`: absent/null limit means
    /// uncapped; a present-but-invalid limit invalidates the shape.
    var costPair: (used: Decimal, cap: Decimal?)? {
        guard isEnabled == true, let used = scaledAmount(usedCredits) else { return nil }
        guard monthlyLimit != nil else { return (used, nil) }
        guard let cap = scaledAmount(monthlyLimit) else { return nil }
        return (used, cap)
    }

    private func scaledAmount(_ amount: Decimal?) -> Decimal? {
        guard let amount, amount >= 0 else { return nil }
        let places = decimalPlaces ?? 2
        guard places >= 0 else { return nil }
        return Decimal(sign: .plus, exponent: -places, significand: amount)
    }
}

private struct TokenRefreshResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
}

private struct TokenErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?
}
