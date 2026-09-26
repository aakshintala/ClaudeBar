import Foundation

/// Represents the type of usage quota being tracked.
/// Rich domain model with behavior - knows its own display name and duration.
public enum QuotaType: Sendable, Equatable, Hashable {
    /// Rolling 5-hour session limit
    case session
    /// Rolling 7-day weekly limit
    case weekly
    /// Model-specific limit (e.g., "opus", "sonnet")
    case modelSpecific(String)
    /// Generic time-based limit (e.g., "MCP Usage")
    case timeLimit(String)

    /// Human-readable display name for this quota type
    public var displayName: String {
        switch self {
        case .session:
            "Session"
        case .weekly:
            "Weekly"
        case .modelSpecific(let modelName):
            modelName.capitalized
        case .timeLimit(let name):
            name
        }
    }

    /// Stable key for the quota (the feed's bucket key).
    public var quotaKey: String {
        switch self {
        case .session:
            "session"
        case .weekly:
            "weekly"
        case .modelSpecific(let modelName):
            "model:\(modelName)"
        case .timeLimit(let name):
            "time:\(name)"
        }
    }

    /// The duration of the quota window
    public var duration: QuotaDuration {
        switch self {
        case .session:
            .hours(5)
        case .weekly:
            .days(7)
        case .modelSpecific:
            .days(7) // Model-specific limits typically follow weekly windows
        case .timeLimit(let name) where name.localizedCaseInsensitiveCompare("Monthly") == .orderedSame:
            .days(30)
        case .timeLimit:
            .days(7) // Generic time limits default to weekly
        }
    }
}

/// Represents a time duration for quota windows.
public enum QuotaDuration: Sendable, Equatable, Hashable {
    case hours(Int)
    case days(Int)

    /// Duration in seconds
    public var seconds: TimeInterval {
        switch self {
        case .hours(let h):
            TimeInterval(h * 3600)
        case .days(let d):
            TimeInterval(d * 24 * 3600)
        }
    }
}
