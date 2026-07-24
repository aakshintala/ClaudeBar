import Testing
import Foundation
@testable import Infrastructure

@Suite("QuotaHTTPServer")
struct QuotaHTTPServerTests {

    private let sampleJSON = Data("{\"ok\":true}".utf8)

    @Test
    func `GET quotas returns 200`() {
        let request = Data("GET /quotas HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        let response = QuotaHTTPRequestHandler.handle(request, feedBody: sampleJSON)

        #expect(response.statusCode == 200)
        #expect(response.body == sampleJSON)
    }

    @Test
    func `unknown path returns 404`() {
        let request = Data("GET /unknown HTTP/1.1\r\n\r\n".utf8)
        let response = QuotaHTTPRequestHandler.handle(request, feedBody: sampleJSON)

        #expect(response.statusCode == 404)
    }

    @Test
    func `malformed request line returns 400`() {
        let request = Data("NOTVALID\r\n\r\n".utf8)
        let response = QuotaHTTPRequestHandler.handle(request, feedBody: sampleJSON)

        #expect(response.statusCode == 400)
    }

    @Test
    func `request split across reads still parses`() {
        let full = Data("GET /quotas HTTP/1.1\r\nHost: localhost\r\n\r\n".utf8)
        let splitIndex = full.index(full.startIndex, offsetBy: 10)
        let first = full[..<splitIndex]
        let second = full[splitIndex...]

        var parser = QuotaHTTPIncrementalParser()
        #expect(parser.append(Data(first)) == nil)
        let request = parser.append(Data(second))
        let response = request.map { QuotaHTTPRequestHandler.respond(to: $0, feedBody: sampleJSON) }

        #expect(response?.statusCode == 200)
        #expect(response?.body == sampleJSON)
    }
}
