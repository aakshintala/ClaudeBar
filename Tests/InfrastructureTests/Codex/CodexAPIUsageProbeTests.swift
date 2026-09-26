import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite("CodexAPIUsageProbe Tests")
struct CodexAPIUsageProbeTests {

    // MARK: - Test Helpers

    private func probe(
        responseJSON: String,
        statusCode: Int = 200,
        headerFields: [String: String]? = nil
    ) async throws -> UsageSnapshot {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let response = httpResponse("https://chatgpt.com", statusCode: statusCode, headerFields: headerFields)
        given(mockNetwork).request(.any).willReturn((Data(responseJSON.utf8), response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        return try await probe.probe()
    }

    // MARK: - isAvailable Tests

    @Test
    func `isAvailable returns true when credentials exist`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when credentials missing`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - Probe Authentication Tests

    @Test
    func `probe throws authenticationRequired when no credentials`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    // MARK: - Response Parsing Tests (Headers)

    @Test
    func `probe parses session usage from response headers`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        let responseJSON = """
        {
          "rate_limit": {
            "primary_window": {
              "reset_after_seconds": 3600
            }
          }
        }
        """.data(using: .utf8)!

        let response = httpResponse("https://chatgpt.com", statusCode: 200, headerFields: [
            "x-codex-primary-used-percent": "25.5",
            "x-codex-secondary-used-percent": "45.0"
        ])

        given(mockNetwork).request(.any).willReturn((responseJSON, response))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "codex")

        let sessionQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(sessionQuota != nil)
        #expect(sessionQuota?.percentRemaining == 74.5) // 100 - 25.5

        let weeklyQuota = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weeklyQuota != nil)
        #expect(weeklyQuota?.percentRemaining == 55.0) // 100 - 45.0
    }

    // MARK: - Response Parsing Tests (Body Fallback)

    @Test
    func `probe falls back to body when headers not present`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 30.0,
              "reset_at": 1705312800
            },
            "secondary_window": {
              "used_percent": 60.0,
              "reset_after_seconds": 432000
            }
          }
        }
        """)

        let sessionQuota = snapshot.quotas.first { $0.quotaType == .session }
        #expect(sessionQuota != nil)
        #expect(sessionQuota?.percentRemaining == 70.0) // 100 - 30

        let weeklyQuota = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weeklyQuota != nil)
        #expect(weeklyQuota?.percentRemaining == 40.0) // 100 - 60
    }

    // MARK: - Plan Type Tests

    @Test
    func `probe parses plan type from response body`() async throws {
        let snapshot = try await probe(responseJSON: """
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 10.0
            }
          },
          "plan_type": "plus"
        }
        """)

        #expect(snapshot.accountTier == .custom("PLUS"))
    }

    // MARK: - Credits Tests

    @Test
    func `probe parses credits from response header`() async throws {
        let snapshot = try await probe(
            responseJSON: """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 10.0
                }
              }
            }
            """,
            headerFields: ["x-codex-credits-balance": "750.0"]
        )

        // The real balance, no invented cap: the API reports no grant.
        let credits = try #require(snapshot.quotas.first { $0.quotaType == .timeLimit("Credits") })
        #expect(credits.balanceRemaining == 750)
        #expect(credits.balanceCap == nil)
        #expect(credits.balanceUnit == .credits)
        #expect(credits.isBalanceOnly)
        #expect(snapshot.costUsage == nil)
    }

    @Test
    func `probe parses a string credits balance from the body`() async throws {
        let snapshot = try await probe(
            responseJSON: #"{"credits": {"has_credits": true, "unlimited": false, "balance": "1234.5"}}"#
        )

        #expect(snapshot.quotas.map(\.balanceRemaining) == [Decimal(string: "1234.5")])
    }

    /// A Plus account without credits reports `has_credits: false` and a 0
    /// balance; "0 credits left" would be noise, so no Credits bucket.
    @Test(arguments: [
        #"{"credits": {"has_credits": false, "unlimited": false, "balance": "0"}}"#,
        #"{"credits": {"balance": 0}}"#,
        #"{"credits": {"has_credits": false, "balance": "12"}}"#,
    ])
    func `probe omits the credits bucket when the account has no credits`(responseJSON: String) async throws {
        let snapshot = try await probe(responseJSON: responseJSON)

        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Empty Response Tests

    @Test
    func `probe handles empty response with no usage data`() async throws {
        let snapshot = try await probe(responseJSON: "{}")

        // Should succeed but have no quotas
        #expect(snapshot.quotas.isEmpty)
    }

    // MARK: - Error Handling Tests

    @Test
    func `probe throws sessionExpired on 401 response`() async throws {
        await #expect(throws: ProbeError.sessionExpired()) {
            try await probe(responseJSON: "", statusCode: 401)
        }
    }

    @Test
    func `probe throws parseFailed on invalid JSON`() async throws {
        await #expect(throws: ProbeError.self) {
            try await probe(responseJSON: "not json")
        }
    }

    @Test
    func `probe throws executionFailed on HTTP 500`() async throws {
        await #expect(throws: ProbeError.self) {
            try await probe(responseJSON: "", statusCode: 500)
        }
    }

    @Test
    func `probe throws executionFailed on network error`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createAuthFile(at: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willThrow(URLError(.notConnectedToInternet))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }
}

// MARK: - Token Refresh Tests

@Suite("CodexAPIUsageProbe Token Refresh Tests")
struct CodexAPIUsageProbeTokenRefreshTests {

    @Test
    func `probe refreshes token when lastRefresh is old and retries`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // last_refresh 9 days ago → needs refresh
        let oldDate = Date().addingTimeInterval(-9 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let oldDateStr = formatter.string(from: oldDate)

        try createAuthFile(at: tempDir, accessToken: "old-token", lastRefresh: oldDateStr)

        let mockNetwork = MockNetworkClient()

        // First call: refresh token request (form-urlencoded)
        let refreshResponse = """
        {
          "access_token": "new-token",
          "refresh_token": "new-refresh-token"
        }
        """.data(using: .utf8)!

        let refreshHTTP = httpResponse("https://auth.openai.com", statusCode: 200)

        // Second call: usage request with new token
        let usageResponse = """
        {
          "rate_limit": {
            "primary_window": { "used_percent": 10.0 }
          }
        }
        """.data(using: .utf8)!

        let usageHTTP = httpResponse("https://chatgpt.com", statusCode: 200)

        given(mockNetwork).request(.any).willProduce { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth/token") {
                return (refreshResponse, refreshHTTP)
            } else {
                return (usageResponse, usageHTTP)
            }
        }

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "codex")
        #expect(snapshot.quotas.first?.percentRemaining == 90.0) // 100 - 10
    }

    @Test
    func `probe throws sessionExpired when refresh returns refresh_token_expired`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Trigger refresh by setting old last_refresh
        let oldDate = Date().addingTimeInterval(-9 * 24 * 60 * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try createAuthFile(at: tempDir, lastRefresh: formatter.string(from: oldDate))

        let mockNetwork = MockNetworkClient()

        let errorResponse = """
        { "error": { "code": "refresh_token_expired" } }
        """.data(using: .utf8)!

        let errorHTTP = httpResponse("https://auth.openai.com", statusCode: 400)

        given(mockNetwork).request(.any).willReturn((errorResponse, errorHTTP))

        let loader = CodexCredentialLoader(homeDirectory: tempDir.path)
        let probe = CodexAPIUsageProbe(credentialLoader: loader, networkClient: mockNetwork)

        await #expect(throws: ProbeError.sessionExpired()) {
            try await probe.probe()
        }
    }
}
