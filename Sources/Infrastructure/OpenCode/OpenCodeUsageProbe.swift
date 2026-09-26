import Foundation
import Domain

/// Fetches OpenCode Go usage quotas — 5h/$12, weekly/$30, monthly/$60 — from
/// opencode's own quota API. This is the same server-tracked accounting the
/// opencode.ai dashboard reads, so it agrees with what the website shows.
///
/// Earlier versions of this probe approximated usage by summing a `cost`
/// field out of the local session database (`opencode db ...`). That figure
/// is opencode's client-side cost *estimate* for each message, not the
/// server's actual quota deduction, and it consistently undercounted real
/// usage — the quota bar sat pinned near 100% remaining regardless of what
/// the dashboard showed. Querying the API directly removes the discrepancy
/// by construction: there's nothing left to approximate.
///
/// API: `GET https://opencode.ai/zen/go/v1/usage`, `Authorization: Bearer <key>`
/// where `<key>` is opencode's own stored OpenCode Go API key (see
/// `OpenCodeCredentialLoader`).
public struct OpenCodeUsageProbe: UsageProbe, @unchecked Sendable {
    private let credentialLoader: OpenCodeCredentialLoader
    private let networkClient: any NetworkClient
    private let timeout: TimeInterval

    private static let usageURL = URL(string: "https://opencode.ai/zen/go/v1/usage")!

    public init(
        credentialLoader: OpenCodeCredentialLoader = OpenCodeCredentialLoader(),
        networkClient: any NetworkClient = URLSession.shared,
        timeout: TimeInterval = 15.0
    ) {
        self.credentialLoader = credentialLoader
        self.networkClient = networkClient
        self.timeout = timeout
    }

    // MARK: - UsageProbe

    public func isAvailable() async -> Bool {
        credentialLoader.loadAPIKey() != nil
    }

    public func probe() async throws -> UsageSnapshot {
        guard let apiKey = credentialLoader.loadAPIKey() else {
            AppLog.probes.error("OpenCode: No API key found")
            throw ProbeError.authenticationRequired
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await networkClient.request(request)
        } catch {
            AppLog.probes.error("OpenCode: Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            AppLog.probes.error("OpenCode: Unauthorized (HTTP \(httpResponse.statusCode))")
            throw ProbeError.authenticationRequired
        default:
            AppLog.probes.error("OpenCode: HTTP error \(httpResponse.statusCode)")
            throw ProbeError.executionFailed("HTTP error: \(httpResponse.statusCode)")
        }

        let quotas = try Self.parseUsageResponse(data)

        AppLog.probes.info("OpenCode probe success: 5hr \(Int(quotas[0].percentRemaining))%, weekly \(Int(quotas[1].percentRemaining))%, monthly \(Int(quotas[2].percentRemaining))%")

        return UsageSnapshot(
            providerId: "opencode-go",
            quotas: quotas,
            capturedAt: Date()
        )
    }

    // MARK: - Parsing (testable)

    static func parseUsageResponse(_ data: Data) throws -> [UsageQuota] {
        struct Window: Decodable {
            let percent: Double
            let resetsAt: String?
        }
        struct Usage: Decodable {
            let rolling: Window
            let weekly: Window
            let monthly: Window
        }
        struct Response: Decodable {
            let usage: Usage
        }

        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ProbeError.parseFailed("Failed to decode OpenCode Go usage response: \(error.localizedDescription)")
        }

        return [
            UsageQuota(
                percentRemaining: percentRemaining(from: response.usage.rolling.percent),
                quotaType: .session,
                providerId: "opencode-go",
                resetsAt: parseDate(response.usage.rolling.resetsAt)
            ),
            UsageQuota(
                percentRemaining: percentRemaining(from: response.usage.weekly.percent),
                quotaType: .weekly,
                providerId: "opencode-go",
                resetsAt: parseDate(response.usage.weekly.resetsAt)
            ),
            UsageQuota(
                percentRemaining: percentRemaining(from: response.usage.monthly.percent),
                quotaType: .timeLimit("Monthly"),
                providerId: "opencode-go",
                resetsAt: parseDate(response.usage.monthly.resetsAt)
            ),
        ]
    }

    /// The API reports percent *used*, clamped to [0, 100] before flipping —
    /// mirrors the old local implementation's over-limit-to-zero behavior.
    static func percentRemaining(from percentUsed: Double) -> Double {
        100 - max(0, min(100, percentUsed))
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
