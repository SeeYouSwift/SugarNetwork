import Foundation

// MARK: - Protocol

/// Full interface for an HTTP client. Conform to this to enable mock injection in tests.
public protocol SugarNetworkProtocol: Sendable {

    // MARK: Decoded responses

    /// Perform a request and decode the response body as `T`.
    func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T

    /// Perform a request and return both the decoded body and raw HTTP metadata.
    func response<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> NetworkResponse<T>

    // MARK: Raw responses

    /// Perform a request and return raw bytes with HTTP metadata, skipping JSON decoding.
    func raw(_ endpoint: Endpoint) async throws -> RawResponse

    // MARK: Upload

    /// Upload `data` to the endpoint. Returns the decoded server response.
    func upload<T: Decodable & Sendable>(data: Data, to endpoint: Endpoint, mimeType: String) async throws -> NetworkResponse<T>

    /// Upload a multipart/form-data body built from the given parts.
    func uploadMultipart<T: Decodable & Sendable>(parts: [MultipartPart], to endpoint: Endpoint) async throws -> NetworkResponse<T>

    // MARK: Download

    /// Download a file to a temporary location. Returns the local `URL`.
    func download(_ endpoint: Endpoint) async throws -> URL
}

// MARK: - Multipart helpers

/// A single field in a `multipart/form-data` request.
public struct MultipartPart: Sendable {
    public let name: String
    public let filename: String?
    public let mimeType: String
    public let data: Data

    public init(name: String, filename: String? = nil, mimeType: String, data: Data) {
        self.name = name
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }

    /// Convenience: a plain text field.
    public static func text(_ value: String, name: String) -> MultipartPart {
        MultipartPart(name: name, mimeType: "text/plain", data: Data(value.utf8))
    }

    /// Convenience: a file field with a specific MIME type.
    public static func file(_ data: Data, name: String, filename: String, mimeType: String) -> MultipartPart {
        MultipartPart(name: name, filename: filename, mimeType: mimeType, data: data)
    }

    /// Convenience: a JPEG image field.
    public static func jpeg(_ data: Data, name: String, filename: String = "image.jpg") -> MultipartPart {
        MultipartPart(name: name, filename: filename, mimeType: "image/jpeg", data: data)
    }

    /// Convenience: a PNG image field.
    public static func png(_ data: Data, name: String, filename: String = "image.png") -> MultipartPart {
        MultipartPart(name: name, filename: filename, mimeType: "image/png", data: data)
    }
}

// MARK: - SugarNetwork

/// A production-ready, generic HTTP client built on `URLSession`.
///
/// Features:
/// - Typed JSON decoding with `NetworkResponse<T>` (value + HTTP metadata)
/// - Raw byte access via `RawResponse`
/// - `RequestInterceptor` chain (auth, logging, header injection, …)
/// - `ResponseInterceptor` chain (token refresh, response logging, …)
/// - Automatic retry with configurable `RetryPolicy` and exponential backoff
/// - Upload: raw data and multipart/form-data
/// - Download: file to a temporary URL
/// - Friendly `NetworkError` mapping for common HTTP status codes
///
/// ```swift
/// let network = SugarNetwork(
///     requestInterceptors: [BearerTokenInterceptor { await tokenStore.token }],
///     retryPolicy: .default
/// )
/// let dogs: [Dog] = try await network.request(DogEndpoints.list)
/// ```
public final class SugarNetwork: SugarNetworkProtocol, @unchecked Sendable {

    // MARK: Shared instance

    /// A default shared `SugarNetwork` instance.
    ///
    /// Attach an event delegate once at app startup:
    /// ```swift
    /// SugarNetwork.shared.eventDelegate = SugarLogger.shared
    /// ```
    public static let shared = SugarNetwork()

    // MARK: Event delegate

    /// Receives a structured `NetworkEvent` after every HTTP transaction.
    ///
    /// Set this once at app launch to observe all requests made through this instance.
    /// The delegate is weakly held — it will be cleared automatically when deallocated.
    /// Use `init(eventDelegate:...)` to pass a delegate that is strongly retained.
    public weak var eventDelegate: (any NetworkEventDelegate)? {
        get { _weakDelegate ?? _strongDelegate }
        set { _weakDelegate = newValue; _strongDelegate = nil }
    }

    // Holds a delegate passed via init — prevents premature deallocation.
    private var _strongDelegate: (any NetworkEventDelegate)?
    private weak var _weakDelegate: (any NetworkEventDelegate)?

    // MARK: Dependencies

    private let session: NetworkSession
    private let decoder: JSONDecoder
    private let timeoutInterval: TimeInterval
    private let requestInterceptors: [RequestInterceptor]
    private let responseInterceptors: [ResponseInterceptor]
    private let retryPolicy: RetryPolicy

    // MARK: Init

    public init(
        session: NetworkSession = URLSession.shared,
        decoder: JSONDecoder = .init(),
        timeoutInterval: TimeInterval = 30,
        requestInterceptors: [RequestInterceptor] = [],
        responseInterceptors: [ResponseInterceptor] = [],
        retryPolicy: RetryPolicy = .none,
        eventDelegate: (any NetworkEventDelegate)? = nil
    ) {
        self.session = session
        self.decoder = decoder
        self.timeoutInterval = timeoutInterval
        self.requestInterceptors = requestInterceptors
        self.responseInterceptors = responseInterceptors
        self.retryPolicy = retryPolicy
        self._strongDelegate = eventDelegate
        self._weakDelegate = nil
    }

    // MARK: - SugarNetworkProtocol

    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        try await response(endpoint).value
    }

    public func response<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> NetworkResponse<T> {
        let raw = try await performDataRequest(endpoint: endpoint)
        let decoded = try decode(T.self, from: raw.data)
        return NetworkResponse(value: decoded, httpResponse: raw.httpResponse, data: raw.data)
    }

    public func raw(_ endpoint: Endpoint) async throws -> RawResponse {
        try await performDataRequest(endpoint: endpoint)
    }

    public func upload<T: Decodable & Sendable>(
        data: Data,
        to endpoint: Endpoint,
        mimeType: String
    ) async throws -> NetworkResponse<T> {
        var ep = endpoint
        ep.headers = (ep.headers ?? [:]).merging(["Content-Type": mimeType]) { _, new in new }
        var urlRequest = try buildURLRequest(for: ep)
        urlRequest = try await applyRequestInterceptors(urlRequest)

        let (responseData, urlResponse) = try await session.upload(for: urlRequest, from: data)
        let httpResponse = try validate(urlResponse, data: responseData)
        try await applyResponseInterceptors(httpResponse, data: responseData, for: urlRequest)

        let decoded = try decode(T.self, from: responseData)
        return NetworkResponse(value: decoded, httpResponse: httpResponse, data: responseData)
    }

    public func uploadMultipart<T: Decodable & Sendable>(
        parts: [MultipartPart],
        to endpoint: Endpoint
    ) async throws -> NetworkResponse<T> {
        let boundary = "SugarNetwork.\(UUID().uuidString)"
        let body = buildMultipartBody(parts: parts, boundary: boundary)

        var ep = endpoint
        ep.headers = (ep.headers ?? [:]).merging(
            ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
        ) { _, new in new }

        return try await upload(data: body, to: ep, mimeType: "multipart/form-data; boundary=\(boundary)")
    }

    public func download(_ endpoint: Endpoint) async throws -> URL {
        var urlRequest = try buildURLRequest(for: endpoint)
        urlRequest = try await applyRequestInterceptors(urlRequest)

        let (tempURL, urlResponse) = try await session.download(for: urlRequest)
        _ = try validate(urlResponse, data: Data())  // validate status code only

        return tempURL
    }

    // MARK: - Core request pipeline

    /// The central data-fetching method with retry support.
    private func performDataRequest(endpoint: Endpoint) async throws -> RawResponse {
        let urlRequest = try buildURLRequest(for: endpoint)
        return try await executeWithRetry(urlRequest: urlRequest, attempt: 1)
    }

    private func executeWithRetry(urlRequest: URLRequest, attempt: Int, requestID: UUID = UUID()) async throws -> RawResponse {
        let adaptedRequest = try await applyRequestInterceptors(urlRequest)
        let startedAt = Date()

        // Notify delegate that the request is about to be sent (first attempt only).
        // Awaited so the pending log entry is stored before URLSession fires.
        if attempt == 1 {
            await eventDelegate?.networkDidStart(event: NetworkEvent(
                requestID: requestID,
                request: adaptedRequest,
                statusCode: nil,
                responseData: nil,
                httpResponse: nil,
                error: nil,
                startedAt: startedAt,
                finishedAt: startedAt
            ))
        }

        do {
            let (data, urlResponse) = try await session.data(for: adaptedRequest)
            let httpResponse = try validate(urlResponse, data: data)
            try await applyResponseInterceptors(httpResponse, data: data, for: adaptedRequest)

            await eventDelegate?.networkDidComplete(event: NetworkEvent(
                requestID: requestID,
                request: adaptedRequest,
                statusCode: httpResponse.statusCode,
                responseData: data,
                httpResponse: httpResponse,
                error: nil,
                startedAt: startedAt,
                finishedAt: Date()
            ))

            return RawResponse(data: data, httpResponse: httpResponse)
        } catch {
            let networkError = map(error)

            if retryPolicy.shouldRetry(error: networkError, attempt: attempt) {
                let delay = retryPolicy.delay(for: attempt)
                if delay > 0 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                return try await executeWithRetry(urlRequest: urlRequest, attempt: attempt + 1, requestID: requestID)
            }

            // Extract status code from NetworkError if available (e.g. 4xx/5xx)
            let statusCode: Int?
            if case let NetworkError.invalidResponse(code) = networkError {
                statusCode = code
            } else {
                statusCode = nil
            }

            await eventDelegate?.networkDidComplete(event: NetworkEvent(
                requestID: requestID,
                request: adaptedRequest,
                statusCode: statusCode,
                responseData: nil,
                httpResponse: nil,
                error: networkError,
                startedAt: startedAt,
                finishedAt: Date()
            ))

            throw networkError
        }
    }

    // MARK: - URLRequest construction

    private func buildURLRequest(for endpoint: Endpoint) throws -> URLRequest {
        guard let url = endpoint.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.timeoutInterval = timeoutInterval
        request.httpBody = endpoint.body

        endpoint.headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        return request
    }

    // MARK: - Interceptors

    private func applyRequestInterceptors(_ request: URLRequest) async throws -> URLRequest {
        var current = request
        for interceptor in requestInterceptors {
            current = try await interceptor.adapt(current)
        }
        return current
    }

    private func applyResponseInterceptors(
        _ response: HTTPURLResponse,
        data: Data,
        for request: URLRequest
    ) async throws {
        for interceptor in responseInterceptors {
            try await interceptor.process(response: response, data: data, for: request)
        }
    }

    // MARK: - Validation & mapping

    /// Validate the response status code and cast to `HTTPURLResponse`.
    @discardableResult
    private func validate(_ response: URLResponse, data: Data) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse(statusCode: -1)
        }
        guard (200...299).contains(http.statusCode) else {
            throw NetworkError.from(statusCode: http.statusCode, headers: http.allHeaderFields)
        }
        return http
    }

    /// Map a thrown error (URLError, NetworkError, or other) to `NetworkError`.
    private func map(_ error: Error) -> NetworkError {
        if let ne = error as? NetworkError { return ne }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return .noConnection
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            default:
                return .underlying(urlError)
            }
        }
        return .underlying(error)
    }

    // MARK: - Decoding

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if data.isEmpty {
            throw NetworkError.emptyResponse
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw NetworkError.decodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Multipart builder

    private func buildMultipartBody(parts: [MultipartPart], boundary: String) -> Data {
        var body = Data()
        let crlf = "\r\n"
        let dashdash = "--"

        for part in parts {
            body.append("\(dashdash)\(boundary)\(crlf)")

            var disposition = "Content-Disposition: form-data; name=\"\(part.name)\""
            if let filename = part.filename {
                disposition += "; filename=\"\(filename)\""
            }
            body.append("\(disposition)\(crlf)")
            body.append("Content-Type: \(part.mimeType)\(crlf)")
            body.append(crlf)
            body.append(part.data)
            body.append(crlf)
        }

        body.append("\(dashdash)\(boundary)\(dashdash)\(crlf)")
        return body
    }
}

// MARK: - Convenience extensions

extension SugarNetwork {

    /// `SugarNetwork` pre-configured for a single base URL.
    /// Attach interceptors and retry policy as needed.
    public convenience init(
        baseURL: String,
        requestInterceptors: [RequestInterceptor] = [],
        responseInterceptors: [ResponseInterceptor] = [],
        retryPolicy: RetryPolicy = .none,
        timeoutInterval: TimeInterval = 30
    ) {
        // Note: baseURL is baked into each Endpoint; this init is a semantic shortcut.
        self.init(
            timeoutInterval: timeoutInterval,
            requestInterceptors: requestInterceptors,
            responseInterceptors: responseInterceptors,
            retryPolicy: retryPolicy
        )
    }
}

// MARK: - Data append helper

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
