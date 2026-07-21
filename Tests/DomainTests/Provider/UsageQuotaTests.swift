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
        #expect(quota.dollarUsed == nil)
        #expect(quota.dollarCap == nil)
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

    @Test
    func `quota reset timestamp shows days hours and minutes`() {
        // Given - 2 days, 5 hours, 30 minutes from now (+ 30s buffer to avoid rounding down)
        let resetDate = Date().addingTimeInterval(2.0 * 86400 + 5.0 * 3600 + 30.0 * 60 + 30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets in 2d 5h 30m")
    }

    @Test
    func `quota reset timestamp shows only hours and minutes when less than a day`() {
        // Given - 3 hours, 15 minutes from now (+ 30s buffer to avoid rounding down)
        let resetDate = Date().addingTimeInterval(3.0 * 3600 + 15.0 * 60 + 30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets in 3h 15m")
    }

    @Test
    func `quota reset timestamp shows resets soon when under a minute`() {
        // Given - 30 seconds from now
        let resetDate = Date().addingTimeInterval(30)

        // When
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude",
            resetsAt: resetDate
        )

        // Then
        #expect(quota.resetTimestampDescription == "Resets soon")
    }

    @Test
    func `quota reset timestamp description is nil without reset date`() {
        // Given
        let quota = UsageQuota(
            percentRemaining: 35,
            quotaType: .weekly,
            providerId: "claude"
        )

        // Then
        #expect(quota.resetTimestampDescription == nil)
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
        #expect(quotaType.modelName == "opus")
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
        #expect(quota.isDepleted == true)
    }

    // MARK: - Comparing Quotas

    @Test
    func `quotas can be sorted by percentage remaining`() {
        // Given
        let highQuota = UsageQuota(percentRemaining: 80, quotaType: .session, providerId: "claude")
        let lowQuota = UsageQuota(percentRemaining: 20, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(highQuota > lowQuota)
        #expect(lowQuota < highQuota)
    }

    @Test
    func `quotas with same percentage are equal`() {
        // Given
        let quota1 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")
        let quota2 = UsageQuota(percentRemaining: 50, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota1 == quota2)
    }

    // MARK: - Dollar-Based Quotas

    @Test
    func `isDollarBased returns true when dollarRemaining is set`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "claude", dollarRemaining: 50)

        // When & Then
        #expect(quota.isDollarBased == true)
    }

    @Test
    func `isDollarBased returns false when dollarRemaining is nil`() {
        // Given
        let quota = UsageQuota(percentRemaining: 87.95, quotaType: .modelSpecific("Amp Free"), providerId: "claude")

        // When & Then
        #expect(quota.isDollarBased == false)
    }

    @Test
    func `formattedDollarRemaining formats whole dollars`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "claude", dollarRemaining: 50)

        // When & Then
        #expect(quota.formattedDollarRemaining == "$50.00")
    }

    @Test
    func `formattedDollarRemaining formats zero`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "claude", dollarRemaining: 0)

        // When & Then
        #expect(quota.formattedDollarRemaining == "$0.00")
    }

    @Test
    func `formattedDollarRemaining formats decimal amount`() {
        // Given
        let quota = UsageQuota(percentRemaining: 100, quotaType: .modelSpecific("Individual credits"), providerId: "claude", dollarRemaining: Decimal(string: "17.59"))

        // When & Then
        #expect(quota.formattedDollarRemaining == "$17.59")
    }

    @Test
    func `formattedDollarRemaining returns nil when not dollar based`() {
        // Given
        let quota = UsageQuota(percentRemaining: 75, quotaType: .session, providerId: "claude")

        // When & Then
        #expect(quota.formattedDollarRemaining == nil)
    }

    @Test
    func `quota stores capped dollar spend amounts`() {
        let quota = UsageQuota(
            percentRemaining: 75,
            quotaType: .timeLimit("Claude Extra"),
            providerId: "claude",
            dollarUsed: Decimal(string: "123.45"),
            dollarCap: 500
        )

        #expect(quota.dollarUsed == Decimal(string: "123.45"))
        #expect(quota.dollarCap == 500)
        #expect(quota.dollarRemaining == nil)
    }

    @Test
    func `formats capped zero spend at a glance`() {
        let quota = UsageQuota(
            percentRemaining: 100,
            quotaType: .timeLimit("Claude Extra"),
            providerId: "claude",
            dollarUsed: 0,
            dollarCap: 500
        )

        #expect(quota.formattedDollarUsed == "$0.00")
        #expect(quota.formattedDollarCap == "$500")
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
    func `paceAwareStatus returns healthy when burn rate is low`() {
        // 57% used, ~85% elapsed → burn rate ~0.67 → healthy
        let resetsAt = Date().addingTimeInterval(0.75 * 3600) // 15% of 5h remaining
        let quota = UsageQuota(
            percentRemaining: 43,
            quotaType: .session,
            providerId: "claude",
            resetsAt: resetsAt
        )
        #expect(quota.paceAwareStatus(burnRateThreshold: 1.5) == .healthy)
    }

    @Test
    func `paceAwareStatus falls back to absolute thresholds without resetsAt`() {
        let quota = UsageQuota(percentRemaining: 35, quotaType: .session, providerId: "claude")
        // No reset time → falls back to absolute: 35% remaining → warning
        #expect(quota.paceAwareStatus(burnRateThreshold: 1.5) == .warning)
    }

    // MARK: - Window Duration Override

    @Test
    func `percentTimeElapsed uses explicit windowDuration over quota type duration`() {
        // A .timeLimit quota defaults to a 7-day window; an explicit 5h
        // window (as reported by aggregating probes like Oh My Pi) must win.
        let resetsAt = Date().addingTimeInterval(2.5 * 3600) // half of a 5h window left
        let quota = UsageQuota(
            percentRemaining: 50,
            quotaType: .timeLimit("Claude 5h"),
            providerId: "claude",
            resetsAt: resetsAt,
            windowDuration: 5 * 3600
        )
        let elapsed = quota.percentTimeElapsed!
        #expect(elapsed > 49 && elapsed < 51)
    }

    @Test
    func `percentTimeElapsed falls back to quota type duration without windowDuration`() {
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
}
