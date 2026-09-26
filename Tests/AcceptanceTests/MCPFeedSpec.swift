import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

@Suite("Feature: MCP Quota Feed")
struct MCPFeedSpec {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private func makeSettings() -> MockProviderSettingsRepository {
        let mock = MockProviderSettingsRepository()
        given(mock).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(mock).isEnabled(forProvider: .any).willReturn(true)
        given(mock).setEnabled(.any, forProvider: .any).willReturn()
        return mock
    }

    @Test
    @MainActor
    func `GET quotas returns decodable feed JSON`() async throws {
        let settings = makeSettings()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let claudeProbe = MockUsageProbe()
        given(claudeProbe).isAvailable().willReturn(true)
        given(claudeProbe).probe().willReturn(UsageSnapshot(
            providerId: "claude",
            quotas: [
                UsageQuota(percentRemaining: 68, quotaType: .session, providerId: "claude", resetsAt: capturedAt.addingTimeInterval(3600)),
                UsageQuota(percentRemaining: 12, quotaType: .weekly, providerId: "claude", resetsAt: capturedAt.addingTimeInterval(86400))
            ],
            capturedAt: capturedAt,
            accountTier: .claudeMax
        ))

        let codexProbe = MockUsageProbe()
        given(codexProbe).isAvailable().willReturn(true)
        given(codexProbe).probe().willReturn(UsageSnapshot(
            providerId: "codex",
            quotas: [UsageQuota(percentRemaining: 81, quotaType: .weekly, providerId: "codex")],
            capturedAt: capturedAt,
            accountTier: .custom("Plus")
        ))

        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [
                ClaudeProvider(probe: claudeProbe, settingsRepository: settings),
                CodexProvider(probe: codexProbe, settingsRepository: settings)
            ]),
            clock: TestClock()
        )

        let port: UInt16 = 19_876
        let feedService = QuotaFeedService(monitor: monitor, now: { capturedAt.addingTimeInterval(122) })
        let server = QuotaHTTPServer(port: port, feedService: feedService)
        try server.start()
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)

        let url = URL(string: "http://127.0.0.1:\(port)/quotas")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let feed = try decoder.decode(QuotaFeedDTO.self, from: data)

        #expect(feed.providers.count == 2)
        #expect(feed.providers[0].id == "claude")
        #expect(feed.providers[0].tier == "Max")
        #expect(feed.providers[0].ageSeconds == 122)
        #expect(feed.providers[0].quotas[0].key == "session")
        #expect(feed.providers[1].id == "codex")
    }

    @Test
    @MainActor
    func `POST session-start hook returns the rendered feed as additional context`() async throws {
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(UsageSnapshot(
            providerId: "codex",
            quotas: [UsageQuota(percentRemaining: 81, quotaType: .weekly, providerId: "codex")],
            capturedAt: capturedAt,
            accountTier: .custom("Plus")
        ))
        let monitor = QuotaMonitor(
            providers: AIProviders(providers: [CodexProvider(probe: probe, settingsRepository: makeSettings())]),
            clock: TestClock()
        )

        let port: UInt16 = 19_877
        let feedService = QuotaFeedService(monitor: monitor, now: { capturedAt.addingTimeInterval(30) })
        _ = await feedService.currentFeed()  // hooks read the cache, so warm it
        let server = QuotaHTTPServer(port: port, feedService: feedService)
        try server.start()
        defer { server.stop() }

        try await Task.sleep(nanoseconds: 100_000_000)

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/hooks/session-start")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"session_id":"s1","hook_event_name":"SessionStart"}"#.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)

        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try #require(json["hookSpecificOutput"] as? [String: Any])
        #expect(output["hookEventName"] as? String == "SessionStart")
        #expect(output["additionalContext"] as? String == "Quota headroom (QuotaBar):\ncodex (Plus) - weekly 81%")
    }
}
