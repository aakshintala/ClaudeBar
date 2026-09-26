import Testing
import Foundation
@testable import Domain

@Suite
struct UsageQuotaTests {

    // MARK: - Creating Quotas

    @Test
    func `quota can be created with percentage and type`() {
        // Given
        let percentRemaining = 65.0
        let quotaType = QuotaType.session
        let providerId = "claude"

        // When
        let quota = UsageQuota(
            percentRemaining: percentRemaining,
            quotaType: quotaType,
            providerId: providerId
        )

        // Then
        #expect(quota.percentRemaining == 65)
        #expect(quota.quotaType == QuotaType.session)
        #expect(quota.providerId == "claude")
        #expect(quota.balanceUsed == nil)
        #expect(quota.balanceCap == nil)
    }

    @Test
    func `quota can include reset time`() {
        // Given
        let resetDate = Date().addingTimeInterval(3600)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetsAt == resetDate)
    }

    // MARK: - Compact Reset Time

    @Test
    func `compactResetTime shows days when over a day remains`() {
        let resetDate = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "2d")
    }

    @Test
    func `compactResetTime shows hours when under a day`() {
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 15.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "3h")
    }

    @Test
    func `compactResetTime shows minutes when under an hour`() {
        let resetDate = Date().addingTimeInterval(45.0 * 60 + 30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "45m")
    }

    @Test
    func `compactResetTime shows soon when under a minute`() {
        let resetDate = Date().addingTimeInterval(30)
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude", resetsAt: resetDate)
        #expect(quota.compactResetTime == "soon")
    }

    @Test
    func `compactResetTime is nil without reset date`() {
        let quota = UsageQuota(percentRemaining: 35, quotaType: .weekly, providerId: "claude")
        #expect(quota.compactResetTime == nil)
    }

    // MARK: - Quota Types

    @Test
    func `session quota represents a 5 hour window`() {
        // Given
        let quotaType = QuotaType.session

        // When & Then
        #expect(quotaType.displayName == "Session")
        #expect(quotaType.duration == .hours(5))
    }

    @Test
    func `weekly quota represents a 7 day window`() {
        // Given
        let quotaType = QuotaType.weekly

        // When & Then
        #expect(quotaType.displayName == "Weekly")
        #expect(quotaType.duration == .days(7))
    }

    @Test
    func `model specific quota shows the model name`() {
        // Given
        let quotaType = QuotaType.modelSpecific("opus")

        // When & Then
        #expect(quotaType.displayName == "Opus")
    }

    // MARK: - Status Thresholds

    @Test
    func `quota with more than 50 percent remaining is healthy`() {
        // Given
        let quota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .healthy)
    }

    @Test
    func `quota between 20 and 50 percent remaining shows warning`() {
        // Given
        let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .warning)
    }

    @Test
    func `quota below 20 percent remaining is critical`() {
        // Given
        let quota = UsageQuota(percentRemaining: 15, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .critical)
    }

    @Test
    func `quota at zero percent is depleted`() {
        // Given
        let quota = UsageQuota(percentRemaining: 0, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.status == .depleted)
    }

    // MARK: - Comparing Quotas

    @Test
    func `quotas with same percentage are equal`() {
        // Given
        let quota1 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        let quota2 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota1 == quota2)
    }

    // MARK: - Balance Meters

    @Test
    func `a balance with no cap is balance-only`() {
        let quota = UsageQuota(percentRemaining: nil, quotaType: .timeLimit("Credits"), providerId: "codex",
                               balanceRemaining: 750, balanceUnit: .credits)

        #expect(quota.isBalanceOnly)
    }

    @Test
    func `a capped balance and a percentage quota are not balance-only`() {
        let capped = UsageQuota(percentRemaining: 75, quotaType: .timeLimit("Extra"), providerId: "claude",
                                balanceUsed: 125, balanceCap: 500, balanceUnit: .usd)
        let percent = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        #expect(!capped.isBalanceOnly)
        #expect(!percent.isBalanceOnly)
    }

    @Test
    func `usd balances format as dollars and cents`() {
        #expect(BalanceUnit.usd.format(50) == "$50.00")
        #expect(BalanceUnit.usd.format(Decimal(string: "1234.5")!) == "$1,234.50")
    }

    @Test
    func `credit balances format as grouped credits`() {
        #expect(BalanceUnit.credits.format(1234) == "1,234 credits")
        #expect(BalanceUnit.credits.format(Decimal(string: "12.5")!) == "12.5 credits")
    }

    // MARK: - Unit Counts

    @Test
    func `quota stores request counts`() {
        let quota = UsageQuota(
            percentRemaining: 99,
            quotaType: .timeLimit("Monthly"),
            providerId: "cursor",
            unitsUsed: 326,
            unitsLimit: 40000
        )

        #expect(quota.unitsUsed == 326)
        #expect(quota.unitsLimit == 40000)
    }

    @Test
    func `formattedUnits renders the raw fraction without grouping`() {
        let quota = UsageQuota(
            percentRemaining: 21,
            quotaType: .timeLimit("Monthly"),
            providerId: "cursor",
            unitsUsed: 21479,
            unitsLimit: 27222
        )

        #expect(quota.formattedUnits == "21479/27222")
    }

    @Test
    func `formattedUnits is nil when either count is missing`() {
        let noLimit = UsageQuota(
            percentRemaining: 50,
            quotaType: .timeLimit("Monthly"),
            providerId: "cursor",
            unitsUsed: 10
        )
        let noUsed = UsageQuota(
            percentRemaining: 50,
            quotaType: .timeLimit("Monthly"),
            providerId: "cursor",
            unitsLimit: 2000
        )

        #expect(noLimit.formattedUnits == nil)
        #expect(noUsed.formattedUnits == nil)
    }

    @Test
    func `formattedUnits is nil for a zero limit`() {
        let quota = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Monthly"),
            providerId: "cursor",
            unitsUsed: 0,
            unitsLimit: 0
        )

        #expect(quota.formattedUnits == nil)
    }

    @Test
    func `percentage quotas carry no counts`() {
        let quota = UsageQuota(percentRemaining: 65, quotaType: .session, providerId: "claude")

        #expect(quota.unitsUsed == nil)
        #expect(quota.unitsLimit == nil)
        #expect(quota.formattedUnits == nil)
    }

    // MARK: - Burn Rate

    @Test
    func `burnRate is nil without resetsAt`() {
        let quota = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        #expect(quota.burnRate == nil)
    }

    @Test
    func `burnRate is calculated correctly when consuming faster than time`() {
        // 70% used, ~25% time elapsed → burn rate ≈ 2.8
        let resetsAt = Date().addingTimeInterval(3.75 * 3600) // 75% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 30,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        let rate = quota.burnRate!
        #expect(rate > 2.5 && rate < 3.1) // ~2.8, allow for test execution time
    }

    @Test
    func `burnRate is below 1 when consuming slower than time`() {
        // 25% used, ~50% time elapsed → burn rate ≈ 0.5
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 50% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        let rate = quota.burnRate!
        #expect(rate > 0.4 && rate < 0.6) // ~0.5
    }

    // MARK: - Pace-Aware Status

    @Test
    func `status returns healthy when burn rate is low`() {
        // 57% used, ~85% elapsed → burn rate ~0.67 → healthy
        let resetsAt = Date().addingTimeInterval(0.75 * 3600) // 15% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        #expect(quota.status == .healthy)
    }

    @Test
    func `status falls back to absolute thresholds without resetsAt`() {
        let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")
        // No reset time → falls back to absolute: 35% remaining → warning
        #expect(quota.status == .warning)
    }

    @Test
    func `status treats slow-burn Cursor monthly quota as healthy`() {
        // Real scenario: ~18.84% remaining, monthly window nearly elapsed, slow burn rate
        let resetsAt = Date().addingTimeInterval(5.8 * 3600) // ~5h48m until reset
        let quota = UsageQuota(
            percentRemaining: 18.84,
            quotaType: .timeLimit("Monthly"),
            providerId: "cursor",
            resetsAt: resetsAt
        )
        #expect(quota.status == .healthy)
        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 98) // most of the 30-day window has elapsed
    }

    @Test
    func `status keeps Codex session quota critical when reset is days away`() {
        // Session window is 5h but reset is multi-day away → elapsed clamps to 0 → absolute thresholds
        let resetsAt = Date().addingTimeInterval(3 * 24 * 3600) // 3 days
        let quota = UsageQuota(
            percentRemaining: 9,
            quotaType: .session,
            providerId: "codex",
            resetsAt: resetsAt
        )
        #expect(quota.percentTimeElapsed == 0)
        #expect(quota.status == .critical)
    }

    @Test
    func `status is pace-aware when reset time is known`() {
        // 40% left @ ~90% of the week elapsed → burn rate ~0.67, lasts to reset → healthy,
        // though the absolute 20-50% band says warning. Popover, alerts and feed all read this.
        let resetsAt = Date().addingTimeInterval(0.1 * 7 * 24 * 3600)
        let quota = UsageQuota(
            percentRemaining: 40,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetsAt
        )
        #expect(quota.status == .healthy)
    }

    // MARK: - Percent Time Elapsed

    @Test
    func `percentTimeElapsed uses quota type duration`() {
        let resetsAt = Date().addingTimeInterval(3.5 * 24 * 3600) // half of the default 7d left
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .timeLimit("Anything"),
            providerId: "claude",
            resetsAt: resetsAt
        )
        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51)
    }

    @Test
    func `percentTimeElapsed is nil without resetsAt`() {
        let quota = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        #expect(quota.percentTimeElapsed == nil)
    }

    @Test
    func `percentTimeElapsed calculates correctly for session halfway through`() {
        // Session = 5 hours. If resets in 2.5 hours, we're 50% through.
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // 2.5 hours from now
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51) // ~50%, allow for test execution time
    }

    @Test
    func `percentTimeElapsed is clamped to 0 when just reset`() {
        // Reset time is the full duration away (just started)
        let resetsAt = Date().addingTimeInterval(5 * 3600) // 5 hours from now (full session)
        let quota = UsageQuota(
            percentRemaining: 100,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed >= 0 && elapsed < 1) // ~0%
    }

    @Test
    func `percentTimeElapsed is clamped to 100 when past reset time`() {
        // Reset time is in the past (timeUntilReset will be 0)
        let resetsAt = Date().addingTimeInterval(-60) // 1 minute ago
        let quota = UsageQuota(
            percentRemaining: 0,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )

        #expect(quota.percentTimeElapsed == 100)
    }
}
