import Testing
import Foundation
import Network
@testable import Infrastructure

/// A client that connects and never sends anything must not be left open
/// forever (it used to sit idle indefinitely). Mirrors the manual check:
/// `nc 127.0.0.1 <port>` left idle, then the connection disappears from `lsof`.
@Suite("QuotaHTTPServer idle timeout")
struct QuotaHTTPServerIdleTimeoutTests {

    @Test
    func `a connection that sends nothing is cancelled after the idle timeout`() async throws {
        let port = UInt16.random(in: 49_200...49_390)
        let server = QuotaHTTPServer(port: port, idleTimeout: 0.2) { Data() }
        try server.start()
        defer { server.stop() }

        var ready = false
        for _ in 0..<40 where !ready {
            if server.isRunning { ready = true; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(ready)

        let clientQueue = DispatchQueue(label: "quota-http-idle-test-client")
        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        connection.start(queue: clientQueue)
        defer { connection.cancel() }

        var connected = false
        for _ in 0..<40 where !connected {
            if case .ready = connection.state { connected = true; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(connected)

        // Send nothing. Wait past the idle timeout, then confirm the server
        // closed its side: a pending receive completes (EOF or error) instead
        // of hanging.
        let closed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let deadline = DispatchTime.now() + 1.0
            clientQueue.asyncAfter(deadline: deadline) {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, isComplete, error in
                    continuation.resume(returning: isComplete || error != nil)
                }
            }
        }

        #expect(closed, "expected the idle connection to be closed by the server")
    }
}
