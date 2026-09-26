import Foundation

/// Represents a point-in-time snapshot of usage quotas for an AI provider.
/// This is an aggregate root that collects all quota information for a provider.
public struct UsageSnapshot: Sendable, Equatable {
    /// The provider ID this snapshot belongs to (e.g., "claude", "codex", "cursor")
    public let providerId: String

    /// All quotas captured in this snapshot (empty for API accounts)
    public let quotas: [UsageQuota]

    /// When this snapshot was captured
    public let capturedAt: Date

    /// The account tier (e.g., Claude Max, Pro, or custom tier from other providers)
    public let accountTier: AccountTier?

    /// Cost-based usage data (for Claude API accounts)
    public let costUsage: CostUsage?

    // MARK: - Initialization

    public init(
        providerId: String,
        quotas: [UsageQuota],
        capturedAt: Date,
        accountTier: AccountTier? = nil,
        costUsage: CostUsage? = nil
    ) {
        self.providerId = providerId
        self.quotas = quotas
        self.capturedAt = capturedAt
        self.accountTier = accountTier
        self.costUsage = costUsage
    }

    // MARK: - Domain Queries

    /// Finds a specific quota type from this snapshot
    public func quota(for type: QuotaType) -> UsageQuota? {
        quotas.first { $0.quotaType == type }
    }

    /// The session quota if available
    public var sessionQuota: UsageQuota? {
        quota(for: .session)
    }

    /// The weekly quota if available
    public var weeklyQuota: UsageQuota? {
        quota(for: .weekly)
    }

    /// The overall status is the worst status among all quotas.
    /// This is a domain rule: overall health reflects the most critical issue.
    /// Balance-only meters have no percentage and never count.
    public var overallStatus: QuotaStatus {
        quotas.filter { !$0.isBalanceOnly }.map(\.status).max() ?? .healthy
    }

    /// The quota with the lowest remaining percentage, ignoring balance-only
    /// meters. Useful for determining which limit to highlight.
    public var lowestQuota: UsageQuota? {
        quotas.compactMap { q in q.percentRemaining.map { (q, $0) } }.min(by: { $0.1 < $1.1 })?.0
    }

}
