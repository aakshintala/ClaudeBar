import Foundation

/// Claude Code HTTP hook endpoints. SessionStart gets the full feed; the
/// prompt hook stays silent unless a bucket got worse since this session was
/// last told, so a low quota is announced once rather than on every prompt.
///
/// Both read the cached feed and never trigger a refresh: a hook blocks the
/// session or prompt it runs for, and the rendered text already states data age.
@MainActor
public final class QuotaHooks {
    private let feed: @MainActor () -> QuotaFeedDTO
    private let now: () -> Date

    /// Per session: "provider/bucket" → severity last reported.
    // ponytail: never evicted, a few strings per session. Clear on a SessionEnd hook if it ever matters.
    private var reported: [String: [String: Int]] = [:]

    public init(feed: @escaping @MainActor () -> QuotaFeedDTO, now: @escaping () -> Date = { Date() }) {
        self.feed = feed
        self.now = now
    }

    public func sessionStart(_ body: Data) -> Data {
        let feed = feed()
        reported[Self.sessionId(body)] = Self.severities(in: feed)
        let text = QuotaFeedText.render(feed, now: now())
        return text.isEmpty ? Self.empty : Self.envelope("SessionStart", "Quota headroom (QuotaBar):\n\(text)")
    }

    public func prompt(_ body: Data) -> Data {
        let feed = feed()
        let session = Self.sessionId(body)
        let previous = reported[session] ?? [:]
        let current = Self.severities(in: feed)
        reported[session] = current

        let worsened = Set(current.filter { $0.value > previous[$0.key, default: 0] }.keys)
        let providers = feed.providers.filter { p in p.quotas.contains { worsened.contains("\(p.id)/\($0.key)") } }
        guard !providers.isEmpty else { return Self.empty }

        let lines = providers.flatMap { QuotaFeedText.renderProvider($0, now: now()) }
        return Self.envelope("UserPromptSubmit", "Quota alert (QuotaBar):\n" + lines.joined(separator: "\n"))
    }

    private static let empty = Data("{}".utf8)

    private static func severities(in feed: QuotaFeedDTO) -> [String: Int] {
        let rank = ["warning": 1, "critical": 2, "depleted": 3]
        var result: [String: Int] = [:]
        for p in feed.providers {
            for q in p.quotas {
                if let severity = rank[q.status] { result["\(p.id)/\(q.key)"] = severity }
            }
        }
        return result
    }

    private static func sessionId(_ body: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        return json?["session_id"] as? String ?? ""
    }

    private struct Envelope: Encodable {
        struct Output: Encodable {
            let hookEventName: String
            let additionalContext: String
        }
        let hookSpecificOutput: Output
    }

    private static func envelope(_ event: String, _ context: String) -> Data {
        let value = Envelope(hookSpecificOutput: .init(hookEventName: event, additionalContext: context))
        return (try? JSONEncoder().encode(value)) ?? empty
    }
}
