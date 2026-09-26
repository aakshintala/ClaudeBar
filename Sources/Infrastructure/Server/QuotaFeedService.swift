import Foundation
import Domain

@MainActor
public final class QuotaFeedService {
    public static let refreshDeadline: TimeInterval = 20

    private let monitor: QuotaMonitor
    private let now: @Sendable () -> Date

    public init(
        monitor: QuotaMonitor,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.monitor = monitor
        self.now = now
    }

    public func currentFeed() async -> QuotaFeedDTO {
        await refreshIfNeeded()
        return QuotaFeedDTO.make(from: monitor.allProviders, at: now())
    }

    /// The feed as the monitor holds it now, without triggering a refresh.
    public func cachedFeed() -> QuotaFeedDTO {
        QuotaFeedDTO.make(from: monitor.allProviders, at: now())
    }

    /// Freshness and coalescing live in `QuotaMonitor.refresh()`; the feed
    /// only bounds how long a request waits for it.
    private func refreshIfNeeded() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.monitor.refresh() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshDeadline * 1_000_000_000))
            }
            _ = await group.next()
            group.cancelAll()
        }
    }
}
