import Foundation
import Domain

/// Renders the quota feed as compact text for agents. Output adapts to
/// severity: an all-healthy provider collapses to one line, and reset times
/// appear only on buckets that need attention, because that is what separates
/// "session resets in an hour, wait it out" from "weekly resets in days, move
/// the work".
public enum QuotaFeedText {
    public static func render(_ feed: QuotaFeedDTO, now: Date) -> String {
        var lines = feed.providers
            .map { renderProvider($0, now: now).joined(separator: "\n") }
            .joined(separator: "\n\n")
        if !feed.disabledProviderIds.isEmpty {
            lines += "\n\n(disabled in QuotaBar: \(feed.disabledProviderIds.joined(separator: ", ")))"
        }
        return lines.trimmingCharacters(in: .newlines)
    }

    public static func renderProvider(_ p: QuotaFeedProviderDTO, now: Date) -> [String] {
        let tier = p.tier.map { " (\($0))" } ?? ""
        var lines: [String] = []

        if let throttledUntil = p.throttledUntil {
            lines.append(
                "\(p.id)\(tier) - throttled until \(formatClock(throttledUntil)), " +
                "showing last known data (\(formatAge(p.ageSeconds)))"
            )
        } else if let unavailable = p.unavailable {
            return ["\(p.id)\(tier) - unavailable: \(unavailable)"]
        } else if p.capturedAt == nil {
            return ["\(p.id)\(tier) - no data yet"]
        }

        // Everything healthy: one scannable line per provider.
        if p.throttledUntil == nil, !p.quotas.contains(where: needsDetail) {
            let summary = p.quotas.map { q in
                "\(q.label.lowercased()) \(amount(q))" + (extra(q).map { " (\($0))" } ?? "")
            }.joined(separator: " · ")
            return ["\(p.id)\(tier) - \(summary.isEmpty ? "no quotas reported" : summary)"]
        }

        if p.throttledUntil == nil {
            lines.append("\(p.id)\(tier) - data \(formatAge(p.ageSeconds))")
        }

        for q in p.quotas {
            let note = extra(q).map { " (\($0))" } ?? ""
            let left = q.percentRemaining == nil ? "" : " left"
            let line = "  \(padLabel(q.label)) \(amount(q))\(left)\(note)"
            guard needsDetail(q) else {
                lines.append(line)
                continue
            }
            let reset = q.resetsAt.map { ", resets in \(formatUntil($0, now: now))" } ?? ""
            lines.append("\(line)\(reset)  [\(q.status)]")
        }
        return lines
    }

    static func needsDetail(_ q: QuotaFeedQuotaDTO) -> Bool {
        q.status != "healthy"
    }

    /// "42%", or the balance ("1,234 credits left") when there is no percentage.
    private static func amount(_ q: QuotaFeedQuotaDTO) -> String {
        if let p = q.percentRemaining { return "\(Int(p.rounded()))%" }
        return balanceLeft(q) ?? "?"
    }

    /// Counts ("412/500"), or the balance left beside a percentage.
    private static func extra(_ q: QuotaFeedQuotaDTO) -> String? {
        if let used = q.unitsUsed, let limit = q.unitsLimit, limit > 0 { return "\(used)/\(limit)" }
        return q.percentRemaining == nil ? nil : balanceLeft(q)
    }

    private static func balanceLeft(_ q: QuotaFeedQuotaDTO) -> String? {
        guard let left = q.balanceRemaining else { return nil }
        return (q.balanceUnit.flatMap(BalanceUnit.init(rawValue:)) ?? .usd).format(left) + " left"
    }

    private static func padLabel(_ label: String, width: Int = 8) -> String {
        label.count >= width ? label : label + String(repeating: " ", count: width - label.count)
    }

    private static func formatAge(_ seconds: Int?) -> String {
        guard let seconds else { return "no data yet" }
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m old" }
        if seconds < 86_400 {
            let h = seconds / 3600, m = (seconds % 3600) / 60
            return m > 0 ? "\(h)h\(m)m old" : "\(h)h old"
        }
        let d = seconds / 86_400, h = (seconds % 86_400) / 3600
        return h > 0 ? "\(d)d\(h)h old" : "\(d)d old"
    }

    private static func formatUntil(_ date: Date, now: Date) -> String {
        let totalMinutes = Int(date.timeIntervalSince(now) / 60)
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d" + (hours > 0 ? "\(hours)h" : "") }
        if hours > 0 { return "\(hours)h" + (minutes > 0 ? "\(minutes)m" : "") }
        if minutes > 0 { return "\(minutes)m" }
        return "soon"
    }

    private static func formatClock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
