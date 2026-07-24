import Testing
import Foundation
import Mockable
@testable import Domain
@testable import Infrastructure

/// Lifecycle tests for the MCP listener.
///
/// These exist because the original implementation shipped three defects that
/// unit tests over the pure request parser could never catch: a duplicate
/// `onChange` fired `sync` twice, the second bind lost the port to EADDRINUSE,
/// and the failure arrived asynchronously — after `start()` had already
/// reported success — leaving `isRunning` reporting true for a dead listener.
@Suite("MCPServerController lifecycle")
@MainActor
struct MCPServerControllerTests {

    private struct TestClock: Clock {
        func sleep(for duration: Duration) async throws {}
        func sleep(nanoseconds: UInt64) async throws {}
    }

    private func makeMonitor() -> QuotaMonitor {
        let settings = MockProviderSettingsRepository()
        given(settings).isEnabled(forProvider: .any, defaultValue: .any).willReturn(true)
        given(settings).isEnabled(forProvider: .any).willReturn(true)
        given(settings).setEnabled(.any, forProvider: .any).willReturn()

        let probe = MockUsageProbe()
        given(probe).isAvailable().willReturn(true)
        given(probe).probe().willReturn(.empty(for: "claude"))

        let claude = ClaudeProvider(probe: probe, settingsRepository: settings)
        return QuotaMonitor(providers: AIProviders(providers: [claude]), clock: TestClock())
    }

    /// Ports in the ephemeral range, chosen per-test to avoid collisions with
    /// anything actually running on the machine (including a real QuotaBar).
    private func freePort() -> Int { Int.random(in: 49_200...49_900) }

    /// Waits for a condition, polling — the NWListener state machine is
    /// asynchronous, so bind outcomes are never observable synchronously.
    private func eventually(
        timeout: TimeInterval = 3.0,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    /// Async variant, for conditions that require I/O to evaluate.
    private func eventuallyAsync(
        timeout: TimeInterval = 5.0,
        _ condition: () async -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    /// Issues a real request. `isRunning` is deliberately NOT used to decide
    /// health here — the bug under test is precisely that it can report true
    /// for a listener the network stack has already torn down. Only a byte off
    /// the socket proves the server is alive.
    private func canFetchQuotas(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/quotas") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    @Test
    func `repeated sync on the same port leaves the endpoint serving`() async {
        let controller = MCPServerController(monitor: makeMonitor())
        let port = freePort()

        controller.sync(enabled: true, port: port)
        #expect(await eventuallyAsync { await canFetchQuotas(port: port) })

        // The exact double-call the duplicate onChange produced in production.
        controller.sync(enabled: true, port: port)
        controller.sync(enabled: true, port: port)

        // Give any async bind failure time to land before asserting.
        try? await Task.sleep(for: .milliseconds(400))

        #expect(await canFetchQuotas(port: port))
        #expect(controller.bindError == nil)

        controller.sync(enabled: false, port: port)
    }

    @Test
    func `losing the port surfaces a bind error instead of reporting running`() async {
        let port = freePort()

        let first = MCPServerController(monitor: makeMonitor())
        first.sync(enabled: true, port: port)
        #expect(await eventually { first.isRunning })

        // A second controller cannot have the port. Whether NWListener rejects
        // it synchronously or asynchronously, the observable end state must be
        // the same: not running, and an error the UI can show.
        let second = MCPServerController(monitor: makeMonitor())
        second.sync(enabled: true, port: port)

        #expect(await eventually { second.bindError != nil })
        #expect(!second.isRunning)

        // The incumbent must survive a rival's failed bind.
        #expect(first.isRunning)

        first.sync(enabled: false, port: port)
        second.sync(enabled: false, port: port)
    }

    @Test
    func `disabling stops the server and clears any error`() async {
        let controller = MCPServerController(monitor: makeMonitor())
        let port = freePort()

        controller.sync(enabled: true, port: port)
        #expect(await eventually { controller.isRunning })

        controller.sync(enabled: false, port: port)

        #expect(!controller.isRunning)
        #expect(controller.bindError == nil)
    }

    @Test
    func `switching port moves the listener`() async {
        let controller = MCPServerController(monitor: makeMonitor())
        let firstPort = freePort()
        let secondPort = freePort()

        controller.sync(enabled: true, port: firstPort)
        #expect(await eventually { controller.isRunning })

        controller.sync(enabled: true, port: secondPort)
        #expect(await eventually { controller.isRunning })
        #expect(controller.bindError == nil)

        controller.sync(enabled: false, port: secondPort)
    }
}
