import Foundation

/// Hook called before every request is sent.
/// Use to inject auth headers, log requests, modify URLs, etc.
public protocol RequestInterceptor: Sendable {
    /// Mutate the `URLRequest` before it is sent.
    func adapt(_ request: URLRequest) async throws -> URLRequest
}

/// Hook called after every response is received.
/// Use to refresh tokens on 401, log responses, etc.
public protocol ResponseInterceptor: Sendable {
    /// Inspect the response. Throw to surface an error; return normally to continue.
    func process(response: HTTPURLResponse, data: Data, for request: URLRequest) async throws
}

// MARK: - Built-in interceptors

/// Adds a static set of HTTP headers to every request.
public struct HeadersInterceptor: RequestInterceptor {
    public let headers: [String: String]

    public init(_ headers: [String: String]) {
        self.headers = headers
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        var r = request
        headers.forEach { r.setValue($1, forHTTPHeaderField: $0) }
        return r
    }
}

/// Attaches a Bearer token to every request.
public struct BearerTokenInterceptor: RequestInterceptor {
    private let tokenProvider: @Sendable () async -> String?

    public init(tokenProvider: @escaping @Sendable () async -> String?) {
        self.tokenProvider = tokenProvider
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        guard let token = await tokenProvider() else { return request }
        var r = request
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
}

/// Logs every request and response to `print`.
public struct LoggingInterceptor: RequestInterceptor, ResponseInterceptor {
    public let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    public func adapt(_ request: URLRequest) async throws -> URLRequest {
        print("[SugarNetwork] → \(request.httpMethod ?? "?") \(request.url?.absoluteString ?? "-")")
        if verbose, let body = request.httpBody, let text = String(data: body, encoding: .utf8) {
            print("[SugarNetwork]   Body: \(text)")
        }
        return request
    }

    public func process(response: HTTPURLResponse, data: Data, for request: URLRequest) async throws {
        print("[SugarNetwork] ← \(response.statusCode) \(request.url?.absoluteString ?? "-")")
        if verbose, let text = String(data: data, encoding: .utf8) {
            print("[SugarNetwork]   Response: \(text)")
        }
    }
}
