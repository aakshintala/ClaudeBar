import Foundation
import Network

public struct QuotaHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public struct QuotaHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    /// Header names lowercased.
    public var headers: [String: String] = [:]
    public var body = Data()

    /// Browsers always send the Host they resolved. A DNS-rebinding page that
    /// reaches this loopback listener still carries its own domain here.
    public var hasLoopbackHost: Bool {
        guard let host = headers["host"] else { return false }
        let name = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        return name == "127.0.0.1" || name == "localhost"
    }
}

public enum QuotaHTTPMessageParser {
    public static let headerTerminator = Data("\r\n\r\n".utf8)

    /// Nil until the headers and the full `Content-Length` body have arrived.
    public static func parseCompleteRequest(from buffer: Data) -> QuotaHTTPRequest? {
        guard let range = buffer.range(of: headerTerminator) else { return nil }
        guard let headerText = String(data: buffer[..<range.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")

        let parts = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length = headers["content-length"].flatMap { Int($0) } ?? 0
        guard buffer.distance(from: range.upperBound, to: buffer.endIndex) >= length else { return nil }
        let bodyStart = range.upperBound
        let body = buffer[bodyStart..<buffer.index(bodyStart, offsetBy: length)]

        return QuotaHTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers, body: Data(body))
    }
}

public struct QuotaHTTPIncrementalParser: Sendable {
    private var buffer = Data()

    public init() {}

    public var bufferedByteCount: Int { buffer.count }

    public mutating func append(_ chunk: Data) -> QuotaHTTPRequest? {
        buffer.append(chunk)
        guard let request = QuotaHTTPMessageParser.parseCompleteRequest(from: buffer) else {
            return nil
        }
        buffer.removeAll(keepingCapacity: true)
        return request
    }
}

public enum QuotaHTTPRequestHandler {
    /// Hook bodies carry the user's prompt, so this is generous; it only stops
    /// a web page from making the app buffer an unbounded POST.
    public static let maxRequestBytes = 1_048_576

    public static func handle(
        _ requestData: Data,
        feedBody: @Sendable () async -> Data,
        hooks: QuotaHooks?
    ) async -> QuotaHTTPResponse {
        guard let request = QuotaHTTPMessageParser.parseCompleteRequest(from: requestData) else {
            return response(statusCode: 400, body: Data("Bad Request".utf8))
        }
        return await respond(to: request, feedBody: feedBody, hooks: hooks)
    }

    public static func respond(
        to request: QuotaHTTPRequest,
        feedBody: @Sendable () async -> Data,
        hooks: QuotaHooks?
    ) async -> QuotaHTTPResponse {
        guard request.hasLoopbackHost else {
            return response(statusCode: 403, body: Data("Forbidden".utf8))
        }

        switch (request.method, request.path) {
        case ("GET", "/quotas"):
            return response(statusCode: 200, body: await feedBody())
        case ("POST", "/hooks/session-start"):
            guard let hooks else { break }
            return response(statusCode: 200, body: await hooks.sessionStart(request.body))
        case ("POST", "/hooks/prompt"):
            guard let hooks else { break }
            return response(statusCode: 200, body: await hooks.prompt(request.body))
        case (_, "/quotas"), (_, "/hooks/session-start"), (_, "/hooks/prompt"):
            return response(statusCode: 405, body: Data("Method Not Allowed".utf8))
        default:
            break
        }
        return response(statusCode: 404, body: Data("Not Found".utf8))
    }

    public static func response(
        statusCode: Int,
        body: Data,
        contentType: String = "text/plain; charset=utf-8"
    ) -> QuotaHTTPResponse {
        QuotaHTTPResponse(statusCode: statusCode, body: body)
    }

    public static func encodedResponse(
        statusCode: Int,
        body: Data,
        contentType: String = "text/plain; charset=utf-8"
    ) -> Data {
        let statusText: String
        switch statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 413: statusText = "Content Too Large"
        default: statusText = "Error"
        }

        let header = """
        HTTP/1.1 \(statusCode) \(statusText)\r\n\
        Content-Type: \(contentType)\r\n\
        Content-Length: \(body.count)\r\n\
        Connection: close\r\n\
        \r\n
        """
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}

public final class QuotaHTTPServer: @unchecked Sendable {
    public enum ServerError: Error {
        case failedToBind(Error)
    }

    private final class ConnectionState: @unchecked Sendable {
        var parser = QuotaHTTPIncrementalParser()
    }

    public let port: UInt16
    private let feedProvider: @Sendable () async -> Data
    private let hooks: QuotaHooks?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.tddworks.ClaudeBar.quota-http")

    /// NWListener reports bind failures (EADDRINUSE in particular) through its
    /// state handler *after* `start()` has already returned successfully. Without
    /// this callback the failure is invisible to the caller, which then reports a
    /// healthy server while nothing is bound.
    public var onFailure: (@Sendable (Error) -> Void)?

    /// Set only once the listener actually reaches `.ready`. `listener != nil` is
    /// not a readiness signal — it is true between `start()` and the state
    /// machine's verdict, and stays true after an async failure.
    private var isReadyFlag = false

    /// `listener` and `isReadyFlag` are written from the NWListener state
    /// handler (on `queue`) and read from the main actor. Without this lock the
    /// readiness write is not guaranteed visible to the reader.
    private let stateLock = NSLock()

    public init(port: UInt16, hooks: QuotaHooks? = nil, feedProvider: @escaping @Sendable () async -> Data) {
        self.port = port
        self.hooks = hooks
        self.feedProvider = feedProvider
    }

    @MainActor
    public convenience init(port: UInt16, feedService: QuotaFeedService, encoder: JSONEncoder = QuotaHTTPServer.makeEncoder()) {
        self.init(port: port, hooks: QuotaHooks(feed: { feedService.cachedFeed() })) {
            let feed = await feedService.currentFeed()
            return (try? encoder.encode(feed)) ?? Data()
        }
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public func start() throws {
        stop()

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.failedToBind(NSError(domain: "QuotaHTTPServer", code: 1))
        }

        // Pin the socket to 127.0.0.1. `acceptLocalOnly` is NOT sufficient: it
        // means "local network", so the listener answers on the LAN address and
        // anyone on the same Wi-Fi can read this machine's quota and tier data.
        // `requiredLocalEndpoint` already carries the port, so it must not be
        // combined with `NWListener(using:on:)` — that pairing returns EINVAL.
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)

        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }
            listener.stateUpdateHandler = { [weak self] (state: NWListener.State) in
                guard let self else { return }
                switch state {
                case .ready:
                    self.stateLock.withLock { self.isReadyFlag = true }
                    AppLog.network.info("Quota HTTP server ready on 127.0.0.1:\(self.port)")
                case .failed(let error):
                    // Tear down rather than leaving a dead listener in place —
                    // otherwise `isRunning` keeps reporting true forever.
                    AppLog.network.error("Quota HTTP server failed: \(error.localizedDescription)")
                    let dead = self.stateLock.withLock { () -> NWListener? in
                        self.isReadyFlag = false
                        let l = self.listener
                        self.listener = nil
                        return l
                    }
                    dead?.cancel()
                    self.onFailure?(error)
                case .cancelled:
                    self.stateLock.withLock { self.isReadyFlag = false }
                default:
                    break
                }
            }
            listener.start(queue: queue)
            stateLock.withLock { self.listener = listener }
            AppLog.network.info("Quota HTTP server listening on 127.0.0.1:\(port)")
        } catch {
            throw ServerError.failedToBind(error)
        }
    }

    public func stop() {
        let existing = stateLock.withLock { () -> NWListener? in
            isReadyFlag = false
            let l = listener
            listener = nil
            return l
        }
        existing?.cancel()
    }

    /// True only while the listener has reached `.ready` and has not since
    /// failed or been cancelled.
    public var isRunning: Bool {
        stateLock.withLock { listener != nil && isReadyFlag }
    }

    private func handle(connection: NWConnection) {
        let state = ConnectionState()
        connection.start(queue: queue)
        receive(on: connection, state: state)
    }

    private func receive(on connection: NWConnection, state: ConnectionState) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let error {
                AppLog.network.error("Quota HTTP connection error: \(error.localizedDescription)")
                connection.cancel()
                return
            }

            if let data, let request = state.parser.append(data) {
                Task {
                    let response = await QuotaHTTPRequestHandler.respond(
                        to: request, feedBody: self.feedProvider, hooks: self.hooks
                    )
                    self.send(response: response, on: connection)
                }
                return
            }

            if state.parser.bufferedByteCount > QuotaHTTPRequestHandler.maxRequestBytes {
                let response = QuotaHTTPRequestHandler.response(statusCode: 413, body: Data("Content Too Large".utf8))
                self.send(response: response, on: connection)
                return
            }

            if isComplete {
                let response = QuotaHTTPRequestHandler.response(statusCode: 400, body: Data("Bad Request".utf8))
                self.send(response: response, on: connection)
                return
            }

            self.receive(on: connection, state: state)
        }
    }

    private func send(response: QuotaHTTPResponse, on connection: NWConnection) {
        let data = QuotaHTTPRequestHandler.encodedResponse(
            statusCode: response.statusCode,
            body: response.body,
            contentType: response.statusCode == 200 ? "application/json" : "text/plain; charset=utf-8"
        )
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
