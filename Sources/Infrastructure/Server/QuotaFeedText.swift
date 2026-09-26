import Foundation

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
                "\(q.label.lowercased()) \(percent(q))%" + (informativeResetText(q).map { " (\($0))" } ?? "")
            }.joined(separator: " · ")
            return ["\(p.id)\(tier) - \(summary.isEmpty ? "no quotas reported" : summary)"]
        }

        if p.throttledUntil == nil {
            lines.append("\(p.id)\(tier) - data \(formatAge(p.ageSeconds))")
        }

        for q in p.quotas {
            let extra = informativeResetText(q).map { " (\($0))" } ?? ""
            let line = "  \(padLabel(q.label)) \(percent(q))% left\(extra)"
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

    private static func percent(_ q: QuotaFeedQuotaDTO) -> Int {
        Int(q.percentRemaining.rounded())
    }

    /// `resetText` is overloaded upstream: Cursor puts usage counts in it
    /// ("21479/27222 requests") while Claude and Codex put a reset description
    /// ("Resets in 1h 24m") that duplicates `resetsAt`. Keep only the former.
    private static func informativeResetText(_ q: QuotaFeedQuotaDTO) -> String? {
        guard let text = q.resetText?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        let isResetDescription = text.range(of: #"^resets?\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        return isResetDescription ? nil : text
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
