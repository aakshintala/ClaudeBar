import Testing
import Foundation
@testable import Infrastructure

@Suite("QuotaFeedText")
struct QuotaFeedTextTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func quota(
        _ label: String,
        _ percent: Double?,
        status: String = "healthy",
        resetsIn: TimeInterval? = nil,
        balanceRemaining: Decimal? = nil,
        balanceUnit: String? = nil,
        unitsUsed: Int? = nil,
        unitsLimit: Int? = nil
    ) -> QuotaFeedQuotaDTO {
        QuotaFeedQuotaDTO(
            key: label.lowercased(),
            label: label,
            percentRemaining: percent,
            resetsAt: resetsIn.map { now.addingTimeInterval($0) },
            resetText: nil,
            status: status,
            balanceRemaining: balanceRemaining,
            balanceUnit: balanceUnit,
            unitsUsed: unitsUsed,
            unitsLimit: unitsLimit
        )
    }

    private func provider(
        _ id: String,
        tier: String? = nil,
        ageSeconds: Int? = 30,
        unavailable: String? = nil,
        quotas: [QuotaFeedQuotaDTO]
    ) -> QuotaFeedProviderDTO {
        QuotaFeedProviderDTO(
            id: id,
            name: id.capitalized,
            tier: tier,
            capturedAt: ageSeconds.map { now.addingTimeInterval(-Double($0)) },
            ageSeconds: ageSeconds,
            status: "healthy",
            unavailable: unavailable,
            throttledUntil: nil,
            quotas: quotas
        )
    }

    private func feed(_ providers: [QuotaFeedProviderDTO], disabled: [String] = []) -> QuotaFeedDTO {
        QuotaFeedDTO(generatedAt: now, providers: providers, disabledProviderIds: disabled)
    }

    @Test
    func `healthy provider collapses to one line`() {
        let text = QuotaFeedText.render(feed([
            provider("claude", tier: "Max", quotas: [quota("Session", 78.4), quota("Weekly", 61.6)])
        ]), now: now)

        #expect(text == "claude (Max) - session 78% · weekly 62%")
    }

    @Test
    func `unhealthy bucket gets reset time and status while healthy siblings stay terse`() {
        let text = QuotaFeedText.render(feed([
            provider("claude", ageSeconds: 300, quotas: [
                quota("Session", 80),
                quota("Weekly", 9, status: "critical", resetsIn: 2 * 86_400 + 3 * 3600)
            ])
        ]), now: now)

        #expect(text == """
        claude - data 5m old
          Session  80% left
          Weekly   9% left, resets in 2d3h  [critical]
        """)
    }

    @Test
    func `counts and balances render from their fields`() {
        let text = QuotaFeedText.render(feed([
            provider("cursor", quotas: [quota("Monthly", 21, unitsUsed: 21479, unitsLimit: 27222)]),
            provider("codex", quotas: [
                quota("Session", 50),
                quota("Credits", nil, balanceRemaining: 1234, balanceUnit: "credits")
            ])
        ]), now: now)

        #expect(text == """
        cursor - monthly 21% (21479/27222)

        codex - session 50% · credits 1,234 credits left
        """)
    }

    @Test
    func `unavailable and never-probed providers say so`() {
        let text = QuotaFeedText.render(feed([
            provider("codex", unavailable: "token has expired", quotas: []),
            provider("cursor", ageSeconds: nil, quotas: [])
        ], disabled: ["opencode-go"]), now: now)

        #expect(text == """
        codex - unavailable: token has expired

        cursor - no data yet

        (disabled in QuotaBar: opencode-go)
        """)
    }
}
