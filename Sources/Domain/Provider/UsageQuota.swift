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

    /// Raw reset text from CLI (e.g., "Resets 11am", "Resets Jan 15")
    public let resetText: String?

    /// Dollar balance remaining for credit-based quotas with no cap (e.g., "$50 remaining").
    /// nil for percentage-based quotas that have a known total.
    public let dollarRemaining: Decimal?

    /// Dollars spent for a capped spend meter.
    /// Co-occurs with `dollarCap`; nil for percentage and balance meters.
    public let dollarUsed: Decimal?

    /// Dollar cap for a capped spend meter.
    /// Co-occurs with `dollarUsed`; nil for percentage and balance meters.
    public let dollarCap: Decimal?

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
        resetText: String? = nil,
        dollarRemaining: Decimal? = nil,
        dollarUsed: Decimal? = nil,
        dollarCap: Decimal? = nil,
        unitsUsed: Int? = nil,
        unitsLimit: Int? = nil
    ) {
        self.percentRemaining = min(100, percentRemaining)  // Allow negative, cap at 100
        self.quotaType = quotaType
        self.providerId = providerId
        self.resetsAt = resetsAt
        self.resetText = resetText
        self.dollarRemaining = dollarRemaining
        self.dollarUsed = dollarUsed
        self.dollarCap = dollarCap
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

    /// Whether this quota is dollar-based (credit balance with no percentage cap)
    public var isDollarBased: Bool {
        dollarRemaining != nil
    }

    /// Formatted dollar remaining string (e.g., "$50.00"), nil for percentage-based quotas
    public var formattedDollarRemaining: String? {
        guard let dollarRemaining else { return nil }
        let amount = NSDecimalNumber(decimal: dollarRemaining).doubleValue
        return String(format: "$%.2f", amount)
    }

    /// Formatted spend amount for capped monetary quotas (e.g. "$1,234.56").
    public var formattedDollarUsed: String? {
        formatDollars(dollarUsed, minimumFractionDigits: 2)
    }

    /// Formatted cap for capped monetary quotas (e.g. "$500").
    public var formattedDollarCap: String? {
        formatDollars(dollarCap, minimumFractionDigits: 0)
    }

    /// The used/total fraction for a count-based meter (e.g. "326/40000"), nil
    /// otherwise. Deliberately ungrouped — the popover row is narrow and
    /// separators buy nothing at these magnitudes.
    public var formattedUnits: String? {
        guard let unitsUsed, let unitsLimit, unitsLimit > 0 else { return nil }
        return "\(unitsUsed)/\(unitsLimit)"
    }

    private func formatDollars(_ amount: Decimal?, minimumFractionDigits: Int) -> String? {
        guard let amount else { return nil }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = 2
        let value = formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
        return "$\(value)"
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
