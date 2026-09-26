import Foundation
import Testing
@testable import Infrastructure
@testable import Domain

@Suite("runProcess")
struct RunProcessTests {

    @Test
    func `returns all of stdout larger than the pipe buffer`() async throws {
        let result = try await runProcess("/usr/bin/head", ["-c", "200000", "/dev/zero"])
        #expect(result.status == 0)
        #expect(result.stdout.count == 200_000)
    }

    @Test
    func `delivers stdin to the child`() async throws {
        let result = try await runProcess("/bin/cat", [], stdin: Data("hello".utf8))
        #expect(String(decoding: result.stdout, as: UTF8.self) == "hello")
    }

    @Test
    func `terminates a hung child at the timeout`() async throws {
        let start = ContinuousClock.now
        await #expect(throws: ProbeError.timeout) {
            try await runProcess("/bin/sleep", ["60"], timeout: 0.5)
        }
        #expect(ContinuousClock.now - start < .seconds(5))
    }
}
