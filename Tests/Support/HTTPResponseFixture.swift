import Foundation

/// Shared `HTTPURLResponse` builder for probe tests, replacing dozens of
/// six-line `HTTPURLResponse(url:statusCode:httpVersion:headerFields:)!` copies.
func httpResponse(
    _ url: String,
    statusCode: Int,
    headerFields: [String: String]? = nil
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: url)!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: headerFields
    )!
}
