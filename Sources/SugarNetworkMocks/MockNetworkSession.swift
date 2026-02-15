import Foundation
import SugarNetwork

/// Mock `NetworkSession` for injecting controlled HTTP responses in tests.
///
/// Supply a `Result` for `data(for:)`. Upload and download use the same
/// backing result so you can test the full request pipeline without a live server.
public final class MockNetworkSession: NetworkSession, @unchecked Sendable {

    // MARK: State

    public var dataResult: Result<(Data, URLResponse), Error>
    public var uploadResult: Result<(Data, URLResponse), Error>?
    public var downloadResult: Result<(URL, URLResponse), Error>?

    /// All requests that were passed to any of the session methods.
    public private(set) var receivedRequests: [URLRequest] = []

    // MARK: Init

    public init(dataResult: Result<(Data, URLResponse), Error>) {
        self.dataResult = dataResult
        self.uploadResult = nil
        self.downloadResult = nil
    }

    // MARK: - NetworkSession

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        return try dataResult.get()
    }

    public func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        receivedRequests.append(request)
        return try (uploadResult ?? dataResult).get()
    }

    public func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        receivedRequests.append(request)
        if let result = downloadResult {
            return try result.get()
        }
        // Fallback: write data result to a temp file
        let (data, response) = try dataResult.get()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: tempURL)
        return (tempURL, response)
    }
}

// MARK: - Convenience factories

extension MockNetworkSession {

    /// Successful `data(for:)` response with given JSON-encoded model.
    public static func success<T: Encodable>(
        model: T,
        statusCode: Int = 200,
        url: URL = URL(string: "https://example.com")!,
        headers: [String: String]? = nil
    ) throws -> MockNetworkSession {
        let data = try JSONEncoder().encode(model)
        return success(data: data, statusCode: statusCode, url: url, headers: headers)
    }

    /// Successful `data(for:)` response with raw data.
    public static func success(
        data: Data,
        statusCode: Int = 200,
        url: URL = URL(string: "https://example.com")!,
        headers: [String: String]? = nil
    ) -> MockNetworkSession {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return MockNetworkSession(dataResult: .success((data, response)))
    }

    /// Failed response that throws the given error.
    public static func failure(_ error: Error) -> MockNetworkSession {
        MockNetworkSession(dataResult: .failure(error))
    }

    /// Convenience for a `URLError`.
    public static func urlError(_ code: URLError.Code) -> MockNetworkSession {
        failure(URLError(code))
    }
}
