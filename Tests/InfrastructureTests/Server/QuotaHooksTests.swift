import Testing
import Foundation
@testable import Infrastructure

@Suite("QuotaHooks")
@MainActor
struct QuotaHooksTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Mutable feed so a test can move quota between hook calls.
    private final class FeedBox {
        var weeklyStatus = "healthy"
        var weeklyPercent: Double = 60
    }

    private func makeHooks(_ box: FeedBox) -> QuotaHooks {
        let now = now
        return QuotaHooks(feed: {
            QuotaFeedDTO(generatedAt: now, providers: [
                QuotaFeedProviderDTO(
                    id: "claude", name: "Claude", tier: nil,
                    capturedAt: now, ageSeconds: 0, status: box.weeklyStatus,
                    unavailable: nil, throttledUntil: nil,
                    quotas: [
                        QuotaFeedQuotaDTO(key: "session", label: "Session", percentRemaining: 90,
                                          resetsAt: nil, resetText: nil, status: "healthy"),
                        QuotaFeedQuotaDTO(key: "weekly", label: "Weekly", percentRemaining: box.weeklyPercent,
                                          resetsAt: now.addingTimeInterval(3600), resetText: nil,
                                          status: box.weeklyStatus)
                    ]
                )
            ], disabledProviderIds: [])
        }, now: { now })
    }

    private func body(_ session: String) -> Data {
        Data(#"{"session_id":"\#(session)","hook_event_name":"UserPromptSubmit","prompt":"hi"}"#.utf8)
    }

    /// The `additionalContext` a hook response carries, or nil for an empty `{}`.
    private func context(_ response: Data) throws -> String? {
        let json = try #require(try JSONSerialization.jsonObject(with: response) as? [String: Any])
        let output = json["hookSpecificOutput"] as? [String: Any]
        return output?["additionalContext"] as? String
    }

    private func eventName(_ response: Data) throws -> String? {
        let json = try #require(try JSONSerialization.jsonObject(with: response) as? [String: Any])
        return (json["hookSpecificOutput"] as? [String: Any])?["hookEventName"] as? String
    }

    @Test
    func `session start carries the full feed`() throws {
        let hooks = makeHooks(FeedBox())
        let response = hooks.sessionStart(body("a"))

        #expect(try eventName(response) == "SessionStart")
        #expect(try context(response) == "Quota headroom (QuotaBar):\nclaude - session 90% · weekly 60%")
    }

    @Test
    func `prompt hook is silent while nothing is low`() throws {
        let hooks = makeHooks(FeedBox())
        _ = hooks.sessionStart(body("a"))

        #expect(try context(hooks.prompt(body("a"))) == nil)
    }

    @Test
    func `prompt hook alerts once when a bucket turns low`() throws {
        let box = FeedBox()
        let hooks = makeHooks(box)
        _ = hooks.sessionStart(body("a"))

        box.weeklyStatus = "warning"
        box.weeklyPercent = 20
        let first = hooks.prompt(body("a"))

        #expect(try eventName(first) == "UserPromptSubmit")
        #expect(try context(first) == """
        Quota alert (QuotaBar):
        claude - data just now
          Session  90% left
          Weekly   20% left, resets in 1h  [warning]
        """)
        #expect(try context(hooks.prompt(body("a"))) == nil)
    }

    @Test
    func `session start already reported low buckets so the prompt hook stays quiet`() throws {
        let box = FeedBox()
        box.weeklyStatus = "warning"
        let hooks = makeHooks(box)

        _ = hooks.sessionStart(body("a"))

        #expect(try context(hooks.prompt(body("a"))) == nil)
    }

    @Test
    func `a worse status alerts again but an improving one does not`() throws {
        let box = FeedBox()
        box.weeklyStatus = "warning"
        let hooks = makeHooks(box)
        _ = hooks.sessionStart(body("a"))

        box.weeklyStatus = "critical"
        #expect(try context(hooks.prompt(body("a"))) != nil)

        box.weeklyStatus = "warning"
        #expect(try context(hooks.prompt(body("a"))) == nil)
    }

    @Test
    func `recovery re-arms the alert`() throws {
        let box = FeedBox()
        let hooks = makeHooks(box)
        _ = hooks.sessionStart(body("a"))

        box.weeklyStatus = "warning"
        _ = hooks.prompt(body("a"))
        box.weeklyStatus = "healthy"
        #expect(try context(hooks.prompt(body("a"))) == nil)

        box.weeklyStatus = "warning"
        #expect(try context(hooks.prompt(body("a"))) != nil)
    }

    @Test
    func `sessions are tracked independently`() throws {
        let box = FeedBox()
        let hooks = makeHooks(box)
        _ = hooks.sessionStart(body("a"))
        _ = hooks.sessionStart(body("b"))

        box.weeklyStatus = "warning"
        _ = hooks.prompt(body("a"))

        #expect(try context(hooks.prompt(body("b"))) != nil)
    }
}
