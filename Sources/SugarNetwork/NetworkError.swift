import Foundation

public enum NetworkError: LocalizedError, Equatable {
    /// The `Endpoint.url` resolved to `nil`.
    case invalidURL
    /// Server returned a non-2xx status code.
    case invalidResponse(statusCode: Int)
    /// JSON decoding failed.
    case decodingFailed(String)
    /// The request was cancelled.
    case cancelled
    /// No internet connection or host unreachable.
    case noConnection
    /// Request exceeded the configured timeout.
    case timeout
    /// Server returned 401 — authentication required.
    case unauthorized
    /// Server returned 403 — insufficient permissions.
    case forbidden
    /// Server returned 404 — resource not found.
    case notFound
    /// Server returned 429 — too many requests.
    case rateLimited(retryAfter: TimeInterval?)
    /// Server returned a 5xx error.
    case serverError(statusCode: Int)
    /// The response body was empty when a body was expected.
    case emptyResponse
    /// An underlying system or URLSession error.
    case underlying(Error)

    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.cancelled, .cancelled),
             (.noConnection, .noConnection),
             (.timeout, .timeout),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.notFound, .notFound),
             (.emptyResponse, .emptyResponse):
            return true
        case (.invalidResponse(let a), .invalidResponse(let b)): return a == b
        case (.decodingFailed(let a),  .decodingFailed(let b)):  return a == b
        case (.serverError(let a),     .serverError(let b)):     return a == b
        case (.rateLimited(let a),     .rateLimited(let b)):     return a == b
        default: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL:                return "Invalid URL"
        case .invalidResponse(let c):   return "HTTP error \(c)"
        case .decodingFailed(let m):    return "Decoding failed: \(m)"
        case .cancelled:                return "Request cancelled"
        case .noConnection:             return "No internet connection"
        case .timeout:                  return "Request timed out"
        case .unauthorized:             return "Unauthorized (401)"
        case .forbidden:                return "Forbidden (403)"
        case .notFound:                 return "Not found (404)"
        case .rateLimited(let after):
            if let after { return "Rate limited — retry after \(Int(after))s" }
            return "Rate limited (429)"
        case .serverError(let c):       return "Server error \(c)"
        case .emptyResponse:            return "Empty response body"
        case .underlying(let e):        return e.localizedDescription
        }
    }

    /// `true` for transient errors that are worth retrying.
    public var isRetryable: Bool {
        switch self {
        case .noConnection, .timeout, .serverError: return true
        default: return false
        }
    }

    /// Map an HTTP status code (and optional headers) to a `NetworkError`.
    public static func from(statusCode: Int, headers: [AnyHashable: Any] = [:]) -> NetworkError {
        switch statusCode {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429:
            let after = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: after)
        case 500...: return .serverError(statusCode: statusCode)
        default:    return .invalidResponse(statusCode: statusCode)
        }
    }
}
