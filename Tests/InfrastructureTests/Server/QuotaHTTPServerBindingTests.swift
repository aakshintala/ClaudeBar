import Testing
import Foundation
@testable import Infrastructure

/// The feed reports account tier and usage for every AI provider. The spec's
/// non-goal is explicit: never exposed beyond 127.0.0.1. `acceptLocalOnly` does
/// NOT achieve that — it means "local network", so the listener answered on the
/// LAN address and any machine on the same Wi-Fi could read the feed.
@Suite("QuotaHTTPServer binding")
struct QuotaHTTPServerBindingTests {

    /// A non-loopback IPv4 address for this machine, if it has one.
    private func lanAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard ptr.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                ptr.pointee.ifa_addr,
                socklen_t(ptr.pointee.ifa_addr.pointee.sa_len),
                &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            )
            if result == 0, let candidate = String(cString: host, encoding: .utf8),
               !candidate.isEmpty, candidate != "127.0.0.1" {
                address = candidate
                break
            }
        }
        return address
    }

    private func status(for urlString: String, timeout: TimeInterval = 4) async -> Int? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return nil
        }
        return (response as? HTTPURLResponse)?.statusCode
    }

    @Test
    func `serves on loopback but not on the LAN address`() async throws {
        let port = UInt16.random(in: 49_000...49_190)
        let server = QuotaHTTPServer(port: port) { Data("{\"ok\":true}".utf8) }
        try server.start()
        defer { server.stop() }

        // Wait for readiness rather than assuming it.
        var ready = false
        for _ in 0..<40 where !ready {
            if server.isRunning { ready = true; break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(ready)

        #expect(await status(for: "http://127.0.0.1:\(port)/quotas") == 200)

        guard let lan = lanAddress() else {
            // No non-loopback interface (e.g. isolated CI) — nothing to prove.
            return
        }

        let lanStatus = await status(for: "http://\(lan):\(port)/quotas")
        #expect(
            lanStatus == nil,
            "Feed answered on \(lan):\(port) — it must be bound to loopback only"
        )
    }
}
