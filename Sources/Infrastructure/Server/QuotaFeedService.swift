import Foundation
import Domain

@MainActor
public final class QuotaFeedService {
    private let monitor: QuotaMonitor
    private let refreshDeadline: TimeInterval
    private let now: @Sendable () -> Date

    public init(
        monitor: QuotaMonitor,
        refreshDeadline: TimeInterval = 20,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.monitor = monitor
        self.refreshDeadline = refreshDeadline
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
    /// only bounds how long a request waits for it. The refresh is unstructured so a
    /// hung probe cannot hold the request: whichever finishes first ends the wait,
    /// and the feed serves whatever snapshots exist.
    private func refreshIfNeeded() async {
        let (done, finish) = AsyncStream<Void>.makeStream()
        Task { await monitor.refresh(); finish.finish() }
        let timer = Task { [refreshDeadline] in
            try? await Task.sleep(for: .seconds(refreshDeadline))
            finish.finish()
        }
        for await _ in done {}
        timer.cancel()
    }
}
