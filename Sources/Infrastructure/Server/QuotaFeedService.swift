import Foundation
import Domain

@MainActor
public final class QuotaFeedService {
    public static let coalescingWindow: TimeInterval = 60
    public static let refreshDeadline: TimeInterval = 20

    private let monitor: QuotaMonitor
    private let now: @Sendable () -> Date
    private var lastRefreshCompletedAt: Date?
    private var inFlightRefresh: Task<Void, Never>?

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

    private func refreshIfNeeded() async {
        let currentTime = now()

        if let lastRefreshCompletedAt,
           currentTime.timeIntervalSince(lastRefreshCompletedAt) < Self.coalescingWindow {
            return
        }

        if let inFlightRefresh {
            await inFlightRefresh.value
            return
        }

        let enabledIds = monitor.enabledProviders.map(\.id)
        let task = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.monitor.refresh(providerIds: enabledIds, kind: .background)
                }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(Self.refreshDeadline * 1_000_000_000))
                }
                _ = await group.next()
                group.cancelAll()
            }
            self.lastRefreshCompletedAt = self.now()
            self.inFlightRefresh = nil
        }

        inFlightRefresh = task
        await task.value
    }
}
