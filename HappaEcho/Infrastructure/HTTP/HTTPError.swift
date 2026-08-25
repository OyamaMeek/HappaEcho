import Foundation

/// Transport-level errors produced by the endpoint-agnostic HTTP layer.
enum HTTPError: Error, Equatable {
    /// The server's response was not an HTTP response.
    case invalidResponse
    /// The server returned a non-2xx status. Carries the provider's error
    /// message when one can be parsed from the response body.
    case statusCode(Int, message: String?)
}
