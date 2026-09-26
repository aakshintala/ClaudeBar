import Foundation

/// Represents the health status of a usage quota.
/// Rich domain model - status is determined by business rules, not UI logic.
public enum QuotaStatus: Sendable, Equatable, Hashable, Comparable {
    /// Quota has remaining capacity (>50%)
    case healthy
    /// Quota is getting low (20-50%)
    case warning
    /// Quota is almost exhausted (<20%)
    case critical
    /// Quota is completely exhausted (0%)
    case depleted

    // MARK: - Factory Methods

    /// Creates a status based on the percentage remaining.
    /// This encapsulates the business rules for status thresholds.
    public static func from(percentRemaining: Double) -> QuotaStatus {
        switch percentRemaining {
        case ...0:
            .depleted
        case 0..<20:
            .critical
        case 20..<50:
            .warning
        default:
            .healthy
        }
    }

    /// Creates a pace-aware status using burn rate (usage% / timeElapsed%).
    /// Burn rate > threshold means consuming faster than the period can sustain.
    /// Depleted is always absolute. Below 20% remaining, critical means the pace
    /// so far exhausts the rest before reset (burn rate > 1); a quota that will
    /// last is healthy however low it is. Falls back to absolute thresholds when
    /// time elapsed is 0.
    ///
    /// - Parameters:
    ///   - percentRemaining: The percentage of quota remaining (0-100)
    ///   - percentTimeElapsed: How much of the reset period has elapsed (0-100)
    ///   - burnRateThreshold: The multiplier above which a warning fires (e.g., 1.5 = 50% faster than sustainable)
    public static func from(
        percentRemaining: Double,
        percentTimeElapsed: Double,
        burnRateThreshold: Double
    ) -> QuotaStatus {
        if percentRemaining <= 0 { return .depleted }
        guard percentTimeElapsed > 0 else {
            return from(percentRemaining: percentRemaining)  // no pace data: fall back to absolute thresholds
        }
        let percentUsed = 100 - percentRemaining
        let burnRate = percentUsed / percentTimeElapsed
        if percentRemaining < 20 {
            // Not burnRateThreshold: any rate above 1 runs out before reset, and
            // this close to empty that is hours away, not a trend to watch.
            return burnRate > 1 ? .critical : .healthy
        }
        if burnRate > burnRateThreshold && percentRemaining < 50 {
            return .warning
        }
        return .healthy
    }

    // MARK: - Status Behavior

    /// Whether this status indicates a problem that needs attention
    public var needsAttention: Bool {
        switch self {
        case .healthy:
            false
        case .warning, .critical, .depleted:
            true
        }
    }

    /// The severity level (higher = more severe)
    private var severity: Int {
        switch self {
        case .healthy: 0
        case .warning: 1
        case .critical: 2
        case .depleted: 3
        }
    }

    public static func < (lhs: QuotaStatus, rhs: QuotaStatus) -> Bool {
        lhs.severity < rhs.severity
    }
}
