import Foundation

/// Represents a single usage quota measurement for an AI provider.
/// This is a rich domain model that encapsulates quota-related behavior.
public struct UsageQuota: Sendable, Equatable, Hashable, Comparable {
    /// The percentage of quota remaining (can be negative when over quota, capped at 100)
    public let percentRemaining: Double

    /// The type of quota (session, weekly, model-specific)
    public let quotaType: QuotaType

    /// The provider ID this quota belongs to (e.g., "claude", "codex", "gemini")
    public let providerId: String

    /// When this quota will reset (if known)
    public let resetsAt: Date?

    /// Money or credits left. With no `balanceCap` this is a balance-only
    /// meter, whose `percentRemaining` is a placeholder (see `isBalanceOnly`).
    public let balanceRemaining: Decimal?

    /// Amount spent against `balanceCap`.
    public let balanceUsed: Decimal?

    /// The cap a spend meter counts against; nil when none exists.
    public let balanceCap: Decimal?

    /// What the balance fields count; nil for non-balance meters.
    public let balanceUnit: BalanceUnit?

    /// Requests consumed for a count-based meter (e.g. Cursor's 326 of 40000).
    /// Co-occurs with `unitsLimit`; nil for percentage and monetary meters.
    public let unitsUsed: Int?

    /// Total requests available for a count-based meter.
    /// Co-occurs with `unitsUsed`; nil for percentage and monetary meters.
    public let unitsLimit: Int?

    // MARK: - Initialization

    public init(
        percentRemaining: Double,
        quotaType: QuotaType,
        providerId: String,
        resetsAt: Date? = nil,
        balanceRemaining: Decimal? = nil,
        balanceUsed: Decimal? = nil,
        balanceCap: Decimal? = nil,
        balanceUnit: BalanceUnit? = nil,
        unitsUsed: Int? = nil,
        unitsLimit: Int? = nil
    ) {
        self.percentRemaining = min(100, percentRemaining)  // Allow negative, cap at 100
        self.quotaType = quotaType
        self.providerId = providerId
        self.resetsAt = resetsAt
        self.balanceRemaining = balanceRemaining
        self.balanceUsed = balanceUsed
        self.balanceCap = balanceCap
        self.balanceUnit = balanceUnit
        self.unitsUsed = unitsUsed
        self.unitsLimit = unitsLimit
    }

    // MARK: - Domain Behavior

    /// The current health status: pace-aware when the reset time is known,
    /// absolute thresholds otherwise. Popover, alerts and the feed all read this.
    public var status: QuotaStatus {
        QuotaStatus.from(percentRemaining: percentRemaining, percentTimeElapsed: percentTimeElapsed)
    }

    /// The percentage that has been used (0-100)
    public var percentUsed: Double {
        100 - percentRemaining
    }

    /// A balance with no cap (e.g. Codex credits): no meaningful percentage.
    public var isBalanceOnly: Bool {
        balanceRemaining != nil && balanceCap == nil
    }

    /// The used/total fraction for a count-based meter (e.g. "326/40000"), nil
    /// otherwise. Deliberately ungrouped — the popover row is narrow and
    /// separators buy nothing at these magnitudes.
    public var formattedUnits: String? {
        guard let unitsUsed, let unitsLimit, unitsLimit > 0 else { return nil }
        return "\(unitsUsed)/\(unitsLimit)"
    }

    // MARK: - Burn Rate

    /// The burn rate: how fast quota is being consumed relative to time elapsed.
    /// A burn rate of 1.0 means consuming exactly on pace.
    /// A burn rate of 2.0 means consuming 2x faster than sustainable.
    /// Returns nil when reset time is unknown.
    public var burnRate: Double? {
        guard let percentTimeElapsed, percentTimeElapsed > 0 else { return nil }
        return percentUsed / percentTimeElapsed
    }

    // MARK: - Pace

    /// The percentage of the reset period that has elapsed (0-100), or nil if no reset time is known.
    ///
    /// Calculated as: `(totalDuration - timeUntilReset) / totalDuration * 100`
    public var percentTimeElapsed: Double? {
        guard let timeUntilReset else { return nil }
        let totalDuration = quotaType.duration.seconds
        guard totalDuration > 0 else { return nil }
        let elapsed = totalDuration - timeUntilReset
        return min(100, max(0, elapsed / totalDuration * 100))
    }

    /// Time until this quota resets (if known)
    public var timeUntilReset: TimeInterval? {
        guard let resetsAt else { return nil }
        return max(0, resetsAt.timeIntervalSinceNow)
    }

    /// Compact reset duration for the menu bar label (e.g., "1d", "3h 30m", "45m").
    /// Single largest non-zero unit ("Xd", "Xh", "Xm"); "soon" under a
    /// minute; nil when reset time is unknown. Smaller-unit precision is
    /// intentionally dropped to keep the menu bar label short.
    public var compactResetTime: String? {
        guard let timeUntilReset else { return nil }
        let s = Int(timeUntilReset)
        if s >= 86400 { return "\(s / 86400)d" }
        if s >= 3600  { return "\(s / 3600)h" }
        if s >= 60    { return "\(s / 60)m" }
        return "soon"
    }

    // MARK: - Comparable

    public static func < (lhs: UsageQuota, rhs: UsageQuota) -> Bool {
        lhs.percentRemaining < rhs.percentRemaining
    }
}

/// What a balance meter counts.
public enum BalanceUnit: String, Sendable, Hashable {
    case usd
    case credits

    /// The one balance formatter: "$1,234.50" for usd, "1,234 credits" for credits.
    public func format(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = self == .usd ? 2 : 0
        let value = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return self == .usd ? "$\(value)" : "\(value) credits"
    }
}
