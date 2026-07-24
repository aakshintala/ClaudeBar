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
}

public enum QuotaHTTPMessageParser {
    public static let headerTerminator = Data("\r\n\r\n".utf8)

    public static func parseCompleteRequest(from buffer: Data) -> QuotaHTTPRequest? {
        guard let range = buffer.range(of: headerTerminator) else { return nil }
        let headerData = buffer[..<range.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        guard let requestLine = headerText.split(separator: "\r\n", omittingEmptySubsequences: false).first else {
            return nil
        }

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else { return nil }

        return QuotaHTTPRequest(method: String(parts[0]), path: String(parts[1]))
    }
}

public struct QuotaHTTPIncrementalParser: Sendable {
    private var buffer = Data()

    public init() {}

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
    public static func handle(_ requestData: Data, feedBody: Data) -> QuotaHTTPResponse {
        guard let request = QuotaHTTPMessageParser.parseCompleteRequest(from: requestData) else {
            return response(statusCode: 400, body: Data("Bad Request".utf8))
        }
        return respond(to: request, feedBody: feedBody)
    }

    public static func respond(to request: QuotaHTTPRequest, feedBody: Data) -> QuotaHTTPResponse {
        guard request.method == "GET" else {
            return response(statusCode: 405, body: Data("Method Not Allowed".utf8))
        }

        switch request.path {
        case "/quotas":
            return response(statusCode: 200, body: feedBody, contentType: "application/json")
        default:
            return response(statusCode: 404, body: Data("Not Found".utf8))
        }
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
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
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

    public init(port: UInt16, feedProvider: @escaping @Sendable () async -> Data) {
        self.port = port
        self.feedProvider = feedProvider
    }

    public convenience init(port: UInt16, feedService: QuotaFeedService, encoder: JSONEncoder = QuotaHTTPServer.makeEncoder()) {
        self.init(port: port) {
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
                    let feedBody = await self.feedProvider()
                    let response = QuotaHTTPRequestHandler.respond(to: request, feedBody: feedBody)
                    self.send(response: response, on: connection)
                }
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
