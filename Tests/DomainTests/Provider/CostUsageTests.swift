import Testing
import Foundation
@testable import Domain

@Suite
struct CostUsageTests {

    // MARK: - Initialization

    @Test
    func `creates cost usage with all fields`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "5.50")!,
            providerId: "claude"
        )

        // Then
        #expect(cost.totalCost == Decimal(string: "5.50"))
        #expect(cost.providerId == "claude")
    }

    @Test
    func `defaults kind to API cost`() {
        let cost = CostUsage(
            totalCost: 1,
            providerId: "claude"
        )

        #expect(cost.kind == .apiCost)
    }

    @Test
    func `creates extra usage kind`() {
        let cost = CostUsage(
            totalCost: 1,
            providerId: "claude",
            kind: .extraUsage
        )

        #expect(cost.kind == .extraUsage)
    }

    // MARK: - Formatting

    @Test
    func `formats cost as currency`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "0.55")!,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedCost == Self.expectedCurrencyString(for: Decimal(string: "0.55")!))
    }

    @Test
    func `formats large cost as currency`() {
        // Given
        let cost = CostUsage(
            totalCost: Decimal(string: "1234.56")!,
            providerId: "claude"
        )

        // Then
        #expect(cost.formattedCost == Self.expectedCurrencyString(for: Decimal(string: "1234.56")!))
    }

    private static func expectedCurrencyString(for value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
    }

    // MARK: - Budget Calculation

    @Test
    func `calculates budget status within budget`() {
        // Given
        let cost = CostUsage(
            totalCost: 5,
            providerId: "claude"
        )

        // When
        let status = cost.budgetStatus(budget: 10)

        // Then
        #expect(status == .withinBudget)
    }

    @Test
    func `calculates budget status approaching limit`() {
        // Given
        let cost = CostUsage(
            totalCost: 8.5,
            providerId: "claude"
        )

        // When
        let status = cost.budgetStatus(budget: 10)

        // Then
        #expect(status == .approachingLimit)
    }

    @Test
    func `calculates budget status over budget`() {
        // Given
        let cost = CostUsage(
            totalCost: 12,
            providerId: "claude"
        )

        // When
        let status = cost.budgetStatus(budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    // MARK: - Equatable

    @Test
    func `cost usage is equatable`() {
        // Given
        let capturedAt = Date()
        let cost1 = CostUsage(totalCost: 5, providerId: "claude", capturedAt: capturedAt)
        let cost2 = CostUsage(totalCost: 5, providerId: "claude", capturedAt: capturedAt)
        let cost3 = CostUsage(totalCost: 10, providerId: "claude", capturedAt: capturedAt)

        // Then
        #expect(cost1 == cost2)
        #expect(cost1 != cost3)
    }
}

@Suite
struct BudgetStatusTests {

    // MARK: - Factory Method

    @Test
    func `creates within budget status for low usage`() {
        // When
        let status = BudgetStatus.from(cost: 5, budget: 10)

        // Then
        #expect(status == .withinBudget)
    }

    @Test
    func `creates approaching limit status at 80 percent`() {
        // When
        let status = BudgetStatus.from(cost: 8, budget: 10)

        // Then
        #expect(status == .approachingLimit)
    }

    @Test
    func `creates over budget status at 100 percent`() {
        // When
        let status = BudgetStatus.from(cost: 10, budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    @Test
    func `creates over budget status when exceeding budget`() {
        // When
        let status = BudgetStatus.from(cost: 15, budget: 10)

        // Then
        #expect(status == .overBudget)
    }

    @Test
    func `handles zero budget gracefully`() {
        // When
        let status = BudgetStatus.from(cost: 5, budget: 0)

        // Then
        #expect(status == .withinBudget)
    }

    // MARK: - Display Properties

    @Test
    func `badge text for within budget`() {
        #expect(BudgetStatus.withinBudget.badgeText == "ON TRACK")
    }

    @Test
    func `badge text for approaching limit`() {
        #expect(BudgetStatus.approachingLimit.badgeText == "NEAR LIMIT")
    }

    @Test
    func `badge text for over budget`() {
        #expect(BudgetStatus.overBudget.badgeText == "OVER BUDGET")
    }

    @Test
    func `needs attention for within budget is false`() {
        #expect(BudgetStatus.withinBudget.needsAttention == false)
    }

    @Test
    func `needs attention for approaching limit is true`() {
        #expect(BudgetStatus.approachingLimit.needsAttention == true)
    }

    @Test
    func `needs attention for over budget is true`() {
        #expect(BudgetStatus.overBudget.needsAttention == true)
    }

    // MARK: - Comparable

    @Test
    func `budget status is comparable by severity`() {
        #expect(BudgetStatus.withinBudget < BudgetStatus.approachingLimit)
        #expect(BudgetStatus.approachingLimit < BudgetStatus.overBudget)
    }

    @Test
    func `max of budget statuses returns worst`() {
        let statuses: [BudgetStatus] = [.withinBudget, .approachingLimit, .overBudget]
        #expect(statuses.max() == .overBudget)
    }
}
