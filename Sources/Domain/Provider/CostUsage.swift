import Foundation

/// Represents cost-based usage data for Claude accounts.
/// Used for API accounts (pay-per-use) and Pro accounts with Extra usage enabled.
public struct CostUsage: Sendable, Equatable, Hashable {
    public enum Kind: Sendable, Equatable, Hashable {
        case apiCost
        case extraUsage
    }

    /// Whether this represents general API cost or subscription Extra usage.
    public let kind: Kind

    /// The total cost/spent amount in dollars
    public let totalCost: Decimal

    /// The budget limit (for Pro accounts with Extra usage, e.g., $20.00)
    /// nil for API accounts that don't have a fixed budget
    public let budget: Decimal?

    /// The provider ID this cost belongs to (e.g., "claude")
    public let providerId: String

    /// When this usage data was captured
    public let capturedAt: Date

    /// When this cost usage resets (for Pro Extra usage)
    public let resetsAt: Date?

    // MARK: - Initialization

    public init(
        totalCost: Decimal,
        budget: Decimal? = nil,
        providerId: String,
        kind: Kind = .apiCost,
        capturedAt: Date = Date(),
        resetsAt: Date? = nil
    ) {
        self.kind = kind
        self.totalCost = totalCost
        self.budget = budget
        self.providerId = providerId
        self.capturedAt = capturedAt
        self.resetsAt = resetsAt
    }

    // MARK: - Formatting

    /// Formatted cost string (e.g., "$0.55")
    public var formattedCost: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: totalCost as NSDecimalNumber) ?? "$\(totalCost)"
    }

    // MARK: - Budget Calculation

    /// Calculates the budget status based on the given budget threshold
    public func budgetStatus(budget: Decimal) -> BudgetStatus {
        BudgetStatus.from(cost: totalCost, budget: budget)
    }

    /// Calculates budget status using the built-in budget (for Pro Extra usage)
    public var budgetStatusFromBuiltIn: BudgetStatus? {
        guard let budget else { return nil }
        return BudgetStatus.from(cost: totalCost, budget: budget)
    }
}
