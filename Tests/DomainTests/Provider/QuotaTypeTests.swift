import Testing
import Foundation
@testable import Domain

@Suite
struct QuotaTypeTests {

    // MARK: - Display Name Tests

    @Test
    func `session quota has display name Session`() {
        #expect(QuotaType.session.displayName == "Session")
    }

    @Test
    func `weekly quota has display name Weekly`() {
        #expect(QuotaType.weekly.displayName == "Weekly")
    }

    @Test
    func `model specific quota capitalizes model name`() {
        #expect(QuotaType.modelSpecific("opus").displayName == "Opus")
        #expect(QuotaType.modelSpecific("sonnet").displayName == "Sonnet")
        #expect(QuotaType.modelSpecific("haiku").displayName == "Haiku")
    }

    @Test
    func `fable quota key round trips through persistence`() {
        let fable = QuotaType.modelSpecific("fable")
        #expect(fable.displayName == "Fable")
        #expect(fable.quotaKey == "model:fable")
        #expect(QuotaType(quotaKey: "model:fable") == fable)
    }

    @Test
    func `model specific quota handles multi-word names`() {
        // .capitalized capitalizes each word
        #expect(QuotaType.modelSpecific("claude-3-opus").displayName == "Claude-3-Opus")
    }

    @Test
    func `time limit quota preserves name verbatim`() {
        // Labels arrive display-ready; capitalizing would mangle acronyms
        // ("MCP" → "Mcp") and window tokens ("Claude 5h" → "Claude 5H").
        #expect(QuotaType.timeLimit("MCP").displayName == "MCP")
        #expect(QuotaType.timeLimit("Daily Limit").displayName == "Daily Limit")
        #expect(QuotaType.timeLimit("Claude 5h").displayName == "Claude 5h")
    }

    // MARK: - Duration Tests

    @Test
    func `session quota has 5 hour duration`() {
        #expect(QuotaType.session.duration == .hours(5))
    }

    @Test
    func `weekly quota has 7 day duration`() {
        #expect(QuotaType.weekly.duration == .days(7))
    }

    @Test
    func `model specific quota has 7 day duration`() {
        #expect(QuotaType.modelSpecific("opus").duration == .days(7))
    }

    @Test
    func `time limit quota has 7 day duration`() {
        #expect(QuotaType.timeLimit("any").duration == .days(7))
    }

    // MARK: - Equality Tests

    @Test
    func `same quota types are equal`() {
        #expect(QuotaType.session == .session)
        #expect(QuotaType.weekly == .weekly)
        #expect(QuotaType.modelSpecific("opus") == .modelSpecific("opus"))
    }

    @Test
    func `different quota types are not equal`() {
        #expect(QuotaType.session != .weekly)
        #expect(QuotaType.modelSpecific("opus") != .modelSpecific("sonnet"))
    }

    // MARK: - Hashable Tests

    @Test
    func `quota types can be used in set`() {
        let types: Set<QuotaType> = [.session, .weekly, .modelSpecific("opus"), .session]
        #expect(types.count == 3)
    }

    @Test
    func `quota types can be used as dictionary keys`() {
        var dict: [QuotaType: String] = [:]
        dict[.session] = "5 hours"
        dict[.weekly] = "7 days"

        #expect(dict[.session] == "5 hours")
        #expect(dict[.weekly] == "7 days")
    }
}

@Suite
struct QuotaDurationTests {

    // MARK: - Seconds Calculation Tests

    @Test
    func `hours converts to seconds correctly`() {
        #expect(QuotaDuration.hours(1).seconds == 3600)
        #expect(QuotaDuration.hours(5).seconds == 18000)
        #expect(QuotaDuration.hours(24).seconds == 86400)
    }

    @Test
    func `days converts to seconds correctly`() {
        #expect(QuotaDuration.days(1).seconds == 86400)
        #expect(QuotaDuration.days(7).seconds == 604800)
    }

    // MARK: - Equality Tests

    @Test
    func `same durations are equal`() {
        #expect(QuotaDuration.hours(5) == .hours(5))
        #expect(QuotaDuration.days(7) == .days(7))
    }

    @Test
    func `different durations are not equal`() {
        #expect(QuotaDuration.hours(5) != .hours(6))
        #expect(QuotaDuration.days(7) != .days(1))
        #expect(QuotaDuration.hours(24) != .days(1)) // Same seconds, different types
    }
}
