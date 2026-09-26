import Foundation
import Testing
import Mockable
@testable import Infrastructure
@testable import Domain

/// Covers the in-memory token cache added to avoid spawning `sqlite3` on
/// every refresh: reuse while the JWT is unexpired, re-read once it expires,
/// and drop + retry once on a 401.
@Suite("CursorUsageProbe token caching")
struct CursorUsageProbeCachingTests {

    // MARK: - Test helpers

    private func makeTemporaryDatabase(accessToken: String) async throws -> URL {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cursor-probe-tests-\(UUID().uuidString).vscdb")

        let result = try await runProcess("/usr/bin/sqlite3", [
            dbURL.path,
            "CREATE TABLE ItemTable(key TEXT, value TEXT); " +
                "INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', '\(accessToken)');"
        ])
        #expect(result.status == 0)

        return dbURL
    }

    /// Builds a JWT with the given `sub` and `exp` (seconds since epoch).
    private func makeJWT(sub: String = "user_abc", exp: Double?) -> String {
        var payload: [String: Any] = ["sub": sub]
        if let exp {
            payload["exp"] = exp
        }
        let payloadData = try! JSONSerialization.data(withJSONObject: payload)
        let payloadBase64 = payloadData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(payloadBase64).sig"
    }

    private func jsonResponse(_ body: String, statusCode: Int = 200) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: URL(string: "https://cursor.com/api/usage-summary")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }

    private let usageJSON = """
    {
        "membershipType": "pro",
        "isUnlimited": false,
        "individualUsage": {
            "plan": { "enabled": true, "used": 10, "limit": 100 },
            "onDemand": { "enabled": false, "used": 0, "limit": null }
        }
    }
    """

    // MARK: - Tests

    @Test
    func `unexpired token is reused without re-reading the database`() async throws {
        let farFuture = Date().addingTimeInterval(3600).timeIntervalSince1970
        let jwt = makeJWT(exp: farFuture)
        let dbURL = try await makeTemporaryDatabase(accessToken: jwt)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse(usageJSON))

        let probe = CursorUsageProbe(networkClient: mockNetwork, dbPathOverride: dbURL.path)

        _ = try await probe.probe()

        // Remove the database entirely: a second read would now fail with
        // `.cliNotFound`. Success here proves the cached token was reused.
        try FileManager.default.removeItem(at: dbURL)

        let snapshot = try await probe.probe()
        #expect(snapshot.quotas.count == 1)
    }

    @Test
    func `expired token is re-read from the database`() async throws {
        let alreadyExpired = Date().addingTimeInterval(-60).timeIntervalSince1970
        let jwt = makeJWT(exp: alreadyExpired)
        let dbURL = try await makeTemporaryDatabase(accessToken: jwt)
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse(usageJSON))

        let probe = CursorUsageProbe(networkClient: mockNetwork, dbPathOverride: dbURL.path)
        _ = try await probe.probe()

        // The cached entry was already expired when stored, so the next probe
        // must hit the database again. Delete it and expect the failure that
        // proves a re-read was attempted.
        try FileManager.default.removeItem(at: dbURL)

        await #expect(throws: ProbeError.self) {
            _ = try await probe.probe()
        }
    }

    @Test
    func `a 401 drops the cached token and retries once with a fresh read`() async throws {
        let farFuture = Date().addingTimeInterval(3600).timeIntervalSince1970
        let jwt = makeJWT(exp: farFuture)
        let dbURL = try await makeTemporaryDatabase(accessToken: jwt)
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let mockNetwork = MockNetworkClient()
        // First call: server rejects the (cached) token. Second call: succeeds.
        given(mockNetwork).request(.any).willReturn(jsonResponse("{}", statusCode: 401))
        given(mockNetwork).request(.any).willReturn(jsonResponse(usageJSON))

        let probe = CursorUsageProbe(networkClient: mockNetwork, dbPathOverride: dbURL.path)
        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.count == 1)
    }
}
