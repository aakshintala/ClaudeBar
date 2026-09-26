import Testing
import Foundation
@testable import Infrastructure

@Suite("QuotaHTTPServer")
@MainActor
struct QuotaHTTPServerTests {

    private let sampleJSON = Data("{\"ok\":true}".utf8)

    private func respond(_ raw: String, hooks: QuotaHooks? = nil) async -> QuotaHTTPResponse {
        let json = sampleJSON
        return await QuotaHTTPRequestHandler.handle(Data(raw.utf8), feedBody: { json }, hooks: hooks)
    }

    private func makeHooks() -> QuotaHooks {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return QuotaHooks(
            feed: { QuotaFeedDTO(generatedAt: now, providers: [], disabledProviderIds: []) },
            now: { now }
        )
    }

    @Test
    func `GET quotas returns 200`() async {
        let response = await respond("GET /quotas HTTP/1.1\r\nHost: localhost\r\n\r\n")

        #expect(response.statusCode == 200)
        #expect(response.body == sampleJSON)
    }

    @Test
    func `GET quotas with the Host header Node fetch sends returns 200`() async {
        let response = await respond("GET /quotas HTTP/1.1\r\nhost: 127.0.0.1:8787\r\n\r\n")

        #expect(response.statusCode == 200)
    }

    @Test
    func `non-loopback Host is rejected to block DNS rebinding`() async {
        let response = await respond("GET /quotas HTTP/1.1\r\nHost: evil.example:8787\r\n\r\n")

        #expect(response.statusCode == 403)
    }

    @Test
    func `missing Host is rejected`() async {
        let response = await respond("GET /quotas HTTP/1.1\r\n\r\n")

        #expect(response.statusCode == 403)
    }

    @Test
    func `unknown path returns 404`() async {
        let response = await respond("GET /unknown HTTP/1.1\r\nHost: localhost\r\n\r\n")

        #expect(response.statusCode == 404)
    }

    @Test
    func `wrong method on a known path returns 405`() async {
        let post = await respond("POST /quotas HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n")
        let get = await respond("GET /hooks/prompt HTTP/1.1\r\nHost: localhost\r\n\r\n", hooks: makeHooks())

        #expect(post.statusCode == 405)
        #expect(get.statusCode == 405)
    }

    @Test
    func `malformed request line returns 400`() async {
        let response = await respond("NOTVALID\r\n\r\n")

        #expect(response.statusCode == 400)
    }

    @Test
    func `POST hook with an empty feed returns an empty hook response`() async throws {
        let body = #"{"session_id":"s1"}"#
        let response = await respond(
            "POST /hooks/session-start HTTP/1.1\r\nHost: 127.0.0.1:8787\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)",
            hooks: makeHooks()
        )

        #expect(response.statusCode == 200)
        let json = try #require(try JSONSerialization.jsonObject(with: response.body) as? [String: Any])
        #expect(json.isEmpty)
    }

    @Test
    func `request is incomplete until the whole body arrives`() {
        let body = #"{"session_id":"s1"}"#
        let head = "POST /hooks/prompt HTTP/1.1\r\nHost: localhost\r\nContent-Length: \(body.utf8.count)\r\n\r\n"

        var parser = QuotaHTTPIncrementalParser()
        #expect(parser.append(Data(head.utf8)) == nil)
        #expect(parser.append(Data(body.prefix(5).utf8)) == nil)
        let request = parser.append(Data(body.dropFirst(5).utf8))

        #expect(request?.method == "POST")
        #expect(request?.body == Data(body.utf8))
        #expect(request?.headers["host"] == "localhost")
    }

    @Test
    func `request split inside the headers still parses`() {
        let full = Data("GET /quotas HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        let splitIndex = full.index(full.startIndex, offsetBy: 10)

        var parser = QuotaHTTPIncrementalParser()
        #expect(parser.append(Data(full[..<splitIndex])) == nil)
        #expect(parser.append(Data(full[splitIndex...]))?.path == "/quotas")
    }

    @Test
    func `parser reports buffered size so the server can cap oversized requests`() {
        var parser = QuotaHTTPIncrementalParser()
        _ = parser.append(Data("POST /hooks/prompt HTTP/1.1\r\nHost: localhost\r\nContent-Length: 99999999\r\n\r\n".utf8))
        _ = parser.append(Data(repeating: 0x61, count: 1000))

        #expect(parser.bufferedByteCount > 1000)
    }
}
