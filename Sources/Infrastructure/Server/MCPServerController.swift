import Foundation
import Domain
import Observation

@MainActor
@Observable
public final class MCPServerController {
    public private(set) var bindError: String?

    private let feedService: QuotaFeedService
    private var server: QuotaHTTPServer?

    public init(monitor: QuotaMonitor) {
        self.feedService = QuotaFeedService(monitor: monitor)
    }

    public func sync(enabled: Bool, port: Int) {
        if enabled {
            start(port: port)
        } else {
            stop()
            bindError = nil
        }
    }

    public var isRunning: Bool {
        server?.isRunning == true
    }

    private func start(port: Int) {
        stop()

        guard (1...65_535).contains(port) else {
            bindError = "Port must be between 1 and 65535"
            AppLog.network.error("MCP quota server: invalid port \(port)")
            return
        }

        let server = QuotaHTTPServer(port: UInt16(port), feedService: feedService)
        do {
            try server.start()
            self.server = server
            bindError = nil
            AppLog.network.info("MCP quota server started on port \(port)")
        } catch {
            bindError = "Could not bind port \(port) — it may already be in use"
            AppLog.network.error("MCP quota server failed to bind port \(port): \(error.localizedDescription)")
        }
    }

    private func stop() {
        server?.stop()
        server = nil
    }
}
