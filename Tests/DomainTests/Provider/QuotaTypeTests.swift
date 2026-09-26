import Testing
import Foundation
@testable import Domain

@Suite
struct QuotaTypeTests {

    // MARK: - Display Name Tests

    @Test(arguments: [
        (QuotaType.session, "Session"),
        (.weekly, "Weekly"),
        (.modelSpecific("opus"), "Opus"),
        (.modelSpecific("sonnet"), "Sonnet"),
        (.modelSpecific("haiku"), "Haiku"),
        // .capitalized capitalizes each word
        (.modelSpecific("claude-3-opus"), "Claude-3-Opus"),
        // Labels arrive display-ready; capitalizing would mangle acronyms
        // ("MCP" → "Mcp") and window tokens ("Claude 5h" → "Claude 5H").
        (.timeLimit("MCP"), "MCP"),
        (.timeLimit("Daily Limit"), "Daily Limit"),
        (.timeLimit("Claude 5h"), "Claude 5h"),
    ])
    func `quota type display name`(quotaType: QuotaType, expected: String) {
        #expect(quotaType.displayName == expected)
    }

    @Test
    func `fable quota has display name and key`() {
        let fable = QuotaType.modelSpecific("fable")
        #expect(fable.displayName == "Fable")
        #expect(fable.quotaKey == "model:fable")
    }

    // MARK: - Duration Tests

    @Test(arguments: [
        (QuotaType.session, QuotaDuration.hours(5)),
        (.weekly, .days(7)),
        (.modelSpecific("opus"), .days(7)),
        (.timeLimit("any"), .days(7)),
    ])
    func `quota type duration`(quotaType: QuotaType, expected: QuotaDuration) {
        #expect(quotaType.duration == expected)
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

    @Test(arguments: [
        (QuotaDuration.hours(1), 3600),
        (.hours(5), 18000),
        (.hours(24), 86400),
        (.days(1), 86400),
        (.days(7), 604800),
    ])
    func `duration converts to seconds correctly`(duration: QuotaDuration, expectedSeconds: TimeInterval) {
        #expect(duration.seconds == expectedSeconds)
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
