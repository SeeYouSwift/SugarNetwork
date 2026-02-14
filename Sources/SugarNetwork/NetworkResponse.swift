import Foundation

/// A decoded response paired with its raw HTTP metadata.
public struct NetworkResponse<T: Sendable>: Sendable {
    /// The decoded body.
    public let value: T
    /// The underlying HTTP response (status code, headers, URL).
    public let httpResponse: HTTPURLResponse
    /// The raw response body bytes.
    public let data: Data

    public init(value: T, httpResponse: HTTPURLResponse, data: Data) {
        self.value = value
        self.httpResponse = httpResponse
        self.data = data
    }

    /// HTTP status code — shortcut for `httpResponse.statusCode`.
    public var statusCode: Int { httpResponse.statusCode }

    /// Value of a specific response header (case-insensitive).
    public func header(_ name: String) -> String? {
        httpResponse.value(forHTTPHeaderField: name)
    }
}

/// A raw response with no body decoding — just bytes and HTTP metadata.
public struct RawResponse: Sendable {
    public let data: Data
    public let httpResponse: HTTPURLResponse

    public init(data: Data, httpResponse: HTTPURLResponse) {
        self.data = data
        self.httpResponse = httpResponse
    }

    public var statusCode: Int { httpResponse.statusCode }

    public func header(_ name: String) -> String? {
        httpResponse.value(forHTTPHeaderField: name)
    }
}
