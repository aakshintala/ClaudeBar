import Foundation
import Domain

/// Parses an ISO-8601 timestamp with or without fractional seconds.
func parseISO8601(_ string: String?) -> Date? {
    guard let string else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
}

extension NetworkClient {
    /// Sends `request` and returns the body and response of an HTTP 200.
    /// Anything else throws: `mapStatus` gets first say, then 401/403 become
    /// `.authenticationRequired` and other statuses `.executionFailed`.
    /// Transport errors become `.executionFailed`. `label` prefixes log lines.
    func send(
        _ request: URLRequest,
        label: String,
        mapStatus: (HTTPURLResponse) -> ProbeError? = { _ in nil }
    ) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.request(request)
        } catch {
            AppLog.probes.error("\(label): Network error: \(error.localizedDescription)")
            throw ProbeError.executionFailed("Network error: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProbeError.executionFailed("Invalid response")
        }
        AppLog.probes.debug("\(label): Response status \(http.statusCode)")
        if http.statusCode == 200 { return (data, http) }
        AppLog.probes.error("\(label): HTTP error \(http.statusCode)")
        if let error = mapStatus(http) { throw error }
        if http.statusCode == 401 || http.statusCode == 403 { throw ProbeError.authenticationRequired }
        throw ProbeError.executionFailed("HTTP error: \(http.statusCode)")
    }
}
