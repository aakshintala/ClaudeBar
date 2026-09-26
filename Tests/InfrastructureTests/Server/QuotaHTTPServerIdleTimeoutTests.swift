import Testing
import Foundation
import Network
@testable import Infrastructure

/// A client that connects and never sends anything must not be left open
/// forever (it used to sit idle indefinitely). Mirrors the manual check:
/// `nc 127.0.0.1 <port>` left idle, then the connection disappears from `lsof`.
@Suite("QuotaHTTPServer idle timeout")
struct QuotaHTTPServerIdleTimeoutTests {

    // Generous budgets: a slow start under full-suite load must not fail the
    // test; only a connection that is never closed should, via the time limit.
    @Test(.timeLimit(.minutes(1)))
    func `a connection that sends nothing is cancelled after the idle timeout`() async throws {
        // Disjoint from the other server tests' port ranges, which run in parallel.
        let port = UInt16.random(in: 50_000...50_190)
        let server = QuotaHTTPServer(port: port, idleTimeout: 0.2) { Data() }
        try server.start()
        defer { server.stop() }

        var ready = false
        for _ in 0..<200 where !ready {
            if server.isRunning { ready = true; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try #require(ready)

        let clientQueue = DispatchQueue(label: "quota-http-idle-test-client")
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        connection.start(queue: clientQueue)
        defer { connection.cancel() }

        var connected = false
        for _ in 0..<200 where !connected {
            if case .ready = connection.state { connected = true; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try #require(connected)

        // Send nothing. A pending receive completes (EOF or error) only once the
        // server closes its side after the idle timeout; no fixed sleep.
        let closed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
                continuation.resume(returning: isComplete || error != nil)
            }
        }

        #expect(closed, "expected the idle connection to be closed by the server")
    }
}
