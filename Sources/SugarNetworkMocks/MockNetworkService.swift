import Foundation
import SugarNetwork

/// Mock implementation of `SugarNetworkProtocol` for unit testing.
///
/// Register canned responses by path substring; inject the mock into any service
/// that depends on `SugarNetworkProtocol`.
///
/// ```swift
/// let mock = MockNetworkService()
/// mock.register(Dog(name: "Rex"), for: "/dogs")
/// let sut = DogService(network: mock)
/// ```
public final class MockNetworkService: SugarNetworkProtocol, @unchecked Sendable {

    // MARK: State

    /// Registered canned responses keyed by path substring.
    private var responses: [String: Any] = [:]

    /// Registered raw `RawResponse` overrides keyed by path substring.
    private var rawResponses: [String: RawResponse] = [:]

    /// If set, every call will throw this error (after a registered response check).
    public var forcedError: NetworkError?

    /// URLs returned by `download(_:)`. Key = path substring.
    private var downloadURLs: [String: URL] = [:]

    /// Recorded calls for assertion in tests.
    public private(set) var recordedEndpoints: [Endpoint] = []

    public init() {}

    // MARK: - Registration

    /// Register a decoded response to return when the endpoint path contains `pathContaining`.
    public func register<T: Decodable>(_ response: T, for pathContaining: String) {
        responses[pathContaining] = response
    }

    /// Register a `RawResponse` to return when the endpoint path contains `pathContaining`.
    public func registerRaw(_ response: RawResponse, for pathContaining: String) {
        rawResponses[pathContaining] = response
    }

    /// Register a local URL to return from `download(_:)` for a matching path.
    public func registerDownload(_ url: URL, for pathContaining: String) {
        downloadURLs[pathContaining] = url
    }

    /// Remove all registered responses and reset recorded calls.
    public func reset() {
        responses.removeAll()
        rawResponses.removeAll()
        downloadURLs.removeAll()
        recordedEndpoints.removeAll()
        forcedError = nil
    }

    // MARK: - SugarNetworkProtocol

    public func request<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> T {
        try await response(endpoint).value
    }

    public func response<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws -> NetworkResponse<T> {
        recordedEndpoints.append(endpoint)
        if let error = forcedError { throw error }

        let path = endpoint.path
        for (key, value) in responses {
            if path.contains(key), let typed = value as? T {
                let http = makeHTTPResponse()
                return NetworkResponse(value: typed, httpResponse: http, data: Data())
            }
        }
        throw NetworkError.notFound
    }

    public func raw(_ endpoint: Endpoint) async throws -> RawResponse {
        recordedEndpoints.append(endpoint)
        if let error = forcedError { throw error }

        let path = endpoint.path
        for (key, value) in rawResponses {
            if path.contains(key) { return value }
        }
        throw NetworkError.notFound
    }

    public func upload<T: Decodable & Sendable>(
        data: Data,
        to endpoint: Endpoint,
        mimeType: String
    ) async throws -> NetworkResponse<T> {
        try await response(endpoint)
    }

    public func uploadMultipart<T: Decodable & Sendable>(
        parts: [MultipartPart],
        to endpoint: Endpoint
    ) async throws -> NetworkResponse<T> {
        try await response(endpoint)
    }

    public func download(_ endpoint: Endpoint) async throws -> URL {
        recordedEndpoints.append(endpoint)
        if let error = forcedError { throw error }

        let path = endpoint.path
        for (key, url) in downloadURLs {
            if path.contains(key) { return url }
        }
        throw NetworkError.notFound
    }

    // MARK: - Helpers

    private func makeHTTPResponse(statusCode: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://mock.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
