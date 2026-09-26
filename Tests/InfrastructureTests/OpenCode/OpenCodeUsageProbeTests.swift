import Testing
import Foundation
import Mockable
@testable import Infrastructure
@testable import Domain

@Suite
struct OpenCodeUsageProbeTests {

    // MARK: - Test Helpers

    private func createAuthFile(at directory: URL, key: String = "test-api-key") throws {
        let opencodeDir = directory.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: opencodeDir, withIntermediateDirectories: true)

        let auth: [String: Any] = [
            "opencode-go": ["type": "api", "key": key]
        ]
        let data = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted])
        try data.write(to: opencodeDir.appendingPathComponent("auth.json"))
    }

    private func makeLoader(dataHome: URL, key: String = "test-api-key") throws -> OpenCodeCredentialLoader {
        try createAuthFile(at: dataHome, key: key)
        return OpenCodeCredentialLoader(homeDirectory: "/unused", environment: ["XDG_DATA_HOME": dataHome.path])
    }

    private func jsonResponse(_ body: String, statusCode: Int = 200) -> (Data, URLResponse) {
        let response = httpResponse("https://opencode.ai/zen/go/v1/usage", statusCode: statusCode)
        return (Data(body.utf8), response)
    }

    // MARK: - isAvailable

    @Test
    func `isAvailable returns true when opencode-go API key exists`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = try makeLoader(dataHome: tempDir)
        let probe = OpenCodeUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == true)
    }

    @Test
    func `isAvailable returns false when auth file missing`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = OpenCodeCredentialLoader(homeDirectory: "/unused", environment: ["XDG_DATA_HOME": tempDir.path])
        let probe = OpenCodeUsageProbe(credentialLoader: loader)

        #expect(await probe.isAvailable() == false)
    }

    // MARK: - probe (happy path)

    @Test
    func `probe returns three quotas mapped from the usage API`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let loader = try makeLoader(dataHome: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse("""
        {"usage":{
          "rolling":{"status":"ok","percent":20.83333,"resetsAt":"2026-09-01T22:38:55.674Z"},
          "weekly":{"status":"ok","percent":25,"resetsAt":"2026-09-07T00:00:00.000Z"},
          "monthly":{"status":"ok","percent":25,"resetsAt":"2026-09-29T18:16:15.000Z"}
        }}
        """))

        let probe = OpenCodeUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        let snapshot = try await probe.probe()

        #expect(snapshot.providerId == "opencode-go")
        #expect(snapshot.quotas.count == 3)
        #expect(snapshot.quotas.allSatisfy { $0.providerId == "opencode-go" })

        // 20.83...% used → 79.166...% remaining ($2.50 of $12)
        let fiveHour = snapshot.quotas.first { $0.quotaType == .session }
        #expect(abs((fiveHour?.percentRemaining ?? 0) - 79.16667) < 0.001)
        #expect(fiveHour?.resetsAt != nil)

        let weekly = snapshot.quotas.first { $0.quotaType == .weekly }
        #expect(weekly?.percentRemaining == 75)

        let monthly = snapshot.quotas.first { $0.quotaType == .timeLimit("Monthly") }
        #expect(monthly?.percentRemaining == 75)
    }

    @Test
    func `probe returns 100 percent remaining when API reports no usage`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let loader = try makeLoader(dataHome: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse("""
        {"usage":{
          "rolling":{"status":"ok","percent":0,"resetsAt":null},
          "weekly":{"status":"ok","percent":0,"resetsAt":null},
          "monthly":{"status":"ok","percent":0,"resetsAt":null}
        }}
        """))

        let probe = OpenCodeUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        let snapshot = try await probe.probe()

        #expect(snapshot.quotas.allSatisfy { $0.percentRemaining == 100 })
        #expect(snapshot.quotas.allSatisfy { $0.resetsAt == nil })
    }

    @Test
    func `probe clamps over-limit usage to 0 percent remaining`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let loader = try makeLoader(dataHome: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse("""
        {"usage":{
          "rolling":{"status":"exceeded","percent":140,"resetsAt":"2026-09-01T22:38:55.674Z"},
          "weekly":{"status":"ok","percent":50,"resetsAt":"2026-09-07T00:00:00.000Z"},
          "monthly":{"status":"ok","percent":50,"resetsAt":"2026-09-29T18:16:15.000Z"}
        }}
        """))

        let probe = OpenCodeUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        let snapshot = try await probe.probe()

        let fiveHour = snapshot.quotas.first { $0.quotaType == .session }
        #expect(fiveHour?.percentRemaining == 0)
    }

    // MARK: - probe (error paths)

    @Test
    func `probe throws authenticationRequired when no API key`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let loader = OpenCodeCredentialLoader(homeDirectory: "/unused", environment: ["XDG_DATA_HOME": tempDir.path])
        let probe = OpenCodeUsageProbe(credentialLoader: loader)

        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws authenticationRequired on HTTP 401`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let loader = try makeLoader(dataHome: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse(
            #"{"type":"error","error":{"type":"AuthError","message":"Unauthorized"}}"#,
            statusCode: 401
        ))

        let probe = OpenCodeUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        await #expect(throws: ProbeError.authenticationRequired) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws executionFailed on other HTTP errors`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let loader = try makeLoader(dataHome: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse("", statusCode: 500))

        let probe = OpenCodeUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    @Test
    func `probe throws parseFailed on malformed JSON`() async throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let loader = try makeLoader(dataHome: tempDir)

        let mockNetwork = MockNetworkClient()
        given(mockNetwork).request(.any).willReturn(jsonResponse("not json"))

        let probe = OpenCodeUsageProbe(credentialLoader: loader, networkClient: mockNetwork)
        await #expect(throws: ProbeError.self) {
            try await probe.probe()
        }
    }

    // MARK: - Credential loader

    @Test
    func `credential loader reads key from XDG_DATA_HOME auth file`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let loader = try makeLoader(dataHome: tempDir, key: "sk-abc123")

        #expect(loader.loadAPIKey() == "sk-abc123")
    }

    @Test
    func `credential loader falls back to home directory local share when XDG_DATA_HOME unset`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let localShare = tempDir.appendingPathComponent(".local/share", isDirectory: true)
        try FileManager.default.createDirectory(at: localShare, withIntermediateDirectories: true)
        try createAuthFile(at: localShare, key: "sk-fallback")

        let loader = OpenCodeCredentialLoader(homeDirectory: tempDir.path, environment: [:])
        #expect(loader.loadAPIKey() == "sk-fallback")
    }

    @Test
    func `credential loader returns nil when opencode-go entry missing`() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let opencodeDir = tempDir.appendingPathComponent("opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: opencodeDir, withIntermediateDirectories: true)
        let auth: [String: Any] = ["some-other-provider": ["type": "api", "key": "x"]]
        let data = try JSONSerialization.data(withJSONObject: auth)
        try data.write(to: opencodeDir.appendingPathComponent("auth.json"))

        let loader = OpenCodeCredentialLoader(homeDirectory: "/unused", environment: ["XDG_DATA_HOME": tempDir.path])
        #expect(loader.loadAPIKey() == nil)
    }

    // MARK: - Parsing

    @Test
    func `percentRemaining flips used to remaining and clamps to zero and one hundred`() {
        #expect(OpenCodeUsageProbe.percentRemaining(from: 0) == 100)
        #expect(OpenCodeUsageProbe.percentRemaining(from: 25) == 75)
        #expect(OpenCodeUsageProbe.percentRemaining(from: 140) == 0)
        #expect(OpenCodeUsageProbe.percentRemaining(from: -5) == 100)
    }

    @Test
    func `parseISO8601 handles fractional and non fractional ISO8601`() {
        #expect(parseISO8601("2026-09-01T22:38:55.674Z") != nil)
        #expect(parseISO8601("2026-09-01T22:38:55Z") != nil)
        #expect(parseISO8601(nil) == nil)
    }
}
