import Foundation
import Testing
@testable import SugarNetwork
import SugarNetworkMocks

// MARK: - Shared helpers

private struct Item: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

private let sampleItem = Item(id: 1, name: "Sugar")
private let sampleJSON = #"{"id":1,"name":"Sugar"}"#

private func makeEndpoint(_ path: String = "/test") -> Endpoint {
    Endpoint(baseURL: "https://api.example.com", path: path)
}

// MARK: - request<T> tests

struct RequestTests {

    @Test func decodesJSON() async throws {
        let session = MockNetworkSession.success(data: Data(sampleJSON.utf8))
        let sut = SugarNetwork(session: session)

        let result: Item = try await sut.request(makeEndpoint())
        #expect(result == sampleItem)
    }

    @Test func throwsOnNon2xx() async throws {
        let session = MockNetworkSession.success(data: Data(), statusCode: 404)
        let sut = SugarNetwork(session: session)

        await #expect(throws: NetworkError.notFound) {
            let _: Item = try await sut.request(makeEndpoint())
        }
    }

    @Test func throwsOnServerError() async throws {
        let session = MockNetworkSession.success(data: Data(), statusCode: 500)
        let sut = SugarNetwork(session: session)

        await #expect {
            let _: Item = try await sut.request(makeEndpoint())
        } throws: { error in
            guard let networkError = error as? NetworkError,
                  case .serverError(let code) = networkError else { return false }
            return code == 500
        }
    }

    @Test func throwsOnUnauthorized() async throws {
        let session = MockNetworkSession.success(data: Data(), statusCode: 401)
        let sut = SugarNetwork(session: session)

        await #expect(throws: NetworkError.unauthorized) {
            let _: Item = try await sut.request(makeEndpoint())
        }
    }

    @Test func throwsOnInvalidJSON() async throws {
        let session = MockNetworkSession.success(data: Data("not json".utf8))
        let sut = SugarNetwork(session: session)

        await #expect {
            let _: Item = try await sut.request(makeEndpoint())
        } throws: { error in
            guard case .decodingFailed = error as? NetworkError else { return false }
            return true
        }
    }

    @Test func throwsOnInvalidURL() async throws {
        let session = MockNetworkSession.success(data: Data())
        let sut = SugarNetwork(session: session)
        let bad = Endpoint(baseURL: "ht tp://bad url", path: "/x")

        await #expect(throws: NetworkError.invalidURL) {
            let _: Item = try await sut.request(bad)
        }
    }

    @Test func mapsNoConnectionError() async throws {
        let session = MockNetworkSession.urlError(.notConnectedToInternet)
        let sut = SugarNetwork(session: session)

        await #expect(throws: NetworkError.noConnection) {
            let _: Item = try await sut.request(makeEndpoint())
        }
    }

    @Test func mapsTimeoutError() async throws {
        let session = MockNetworkSession.urlError(.timedOut)
        let sut = SugarNetwork(session: session)

        await #expect(throws: NetworkError.timeout) {
            let _: Item = try await sut.request(makeEndpoint())
        }
    }

    @Test func throwsEmptyResponseWhenBodyIsEmpty() async throws {
        let session = MockNetworkSession.success(data: Data())
        let sut = SugarNetwork(session: session)

        await #expect(throws: NetworkError.emptyResponse) {
            let _: Item = try await sut.request(makeEndpoint())
        }
    }
}

// MARK: - NetworkResponse tests

struct NetworkResponseTests {

    @Test func responseIncludesMetadata() async throws {
        let session = MockNetworkSession.success(
            data: Data(sampleJSON.utf8),
            statusCode: 200,
            url: URL(string: "https://api.example.com/test")!
        )
        let sut = SugarNetwork(session: session)

        let result: NetworkResponse<Item> = try await sut.response(makeEndpoint())
        #expect(result.value == sampleItem)
        #expect(result.statusCode == 200)
        #expect(result.data == Data(sampleJSON.utf8))
    }

    @Test func rawResponseReturnsBytes() async throws {
        let body = Data("raw bytes".utf8)
        let session = MockNetworkSession.success(data: body)
        let sut = SugarNetwork(session: session)

        let result = try await sut.raw(makeEndpoint())
        #expect(result.data == body)
        #expect(result.statusCode == 200)
    }
}

// MARK: - Interceptor tests

private final class CapturingInterceptor: RequestInterceptor, @unchecked Sendable {
    private(set) var capturedRequests: [URLRequest] = []
    let headerKey: String
    let headerValue: String

    init(addHeader key: String = "X-Test", value: String = "1") {
        self.headerKey = key
        self.headerValue = value
    }

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        capturedRequests.append(request)
        var r = request
        r.setValue(headerValue, forHTTPHeaderField: headerKey)
        return r
    }
}

private final class CapturingResponseInterceptor: ResponseInterceptor, @unchecked Sendable {
    private(set) var capturedResponses: [HTTPURLResponse] = []

    func process(response: HTTPURLResponse, data: Data, for request: URLRequest) async throws {
        capturedResponses.append(response)
    }
}

struct InterceptorTests {

    @Test func requestInterceptorAddsHeader() async throws {
        let interceptor = CapturingInterceptor(addHeader: "X-Custom", value: "hello")
        let session = MockNetworkSession.success(data: Data(sampleJSON.utf8))
        let sut = SugarNetwork(session: session, requestInterceptors: [interceptor])

        let _: Item = try await sut.request(makeEndpoint())

        let sentRequest = session.receivedRequests.first
        #expect(sentRequest?.value(forHTTPHeaderField: "X-Custom") == "hello")
    }

    @Test func multipleRequestInterceptorsAppliedInOrder() async throws {
        let first = CapturingInterceptor(addHeader: "X-First", value: "1")
        let second = CapturingInterceptor(addHeader: "X-Second", value: "2")
        let session = MockNetworkSession.success(data: Data(sampleJSON.utf8))
        let sut = SugarNetwork(session: session, requestInterceptors: [first, second])

        let _: Item = try await sut.request(makeEndpoint())

        let sent = session.receivedRequests.first
        #expect(sent?.value(forHTTPHeaderField: "X-First") == "1")
        #expect(sent?.value(forHTTPHeaderField: "X-Second") == "2")
    }

    @Test func responseInterceptorIsCalledOnSuccess() async throws {
        let interceptor = CapturingResponseInterceptor()
        let session = MockNetworkSession.success(data: Data(sampleJSON.utf8))
        let sut = SugarNetwork(session: session, responseInterceptors: [interceptor])

        let _: Item = try await sut.request(makeEndpoint())
        #expect(interceptor.capturedResponses.count == 1)
        #expect(interceptor.capturedResponses.first?.statusCode == 200)
    }

    @Test func bearerTokenInterceptorAttachesToken() async throws {
        let interceptor = BearerTokenInterceptor(tokenProvider: { "my-secret-token" })
        let session = MockNetworkSession.success(data: Data(sampleJSON.utf8))
        let sut = SugarNetwork(session: session, requestInterceptors: [interceptor])

        let _: Item = try await sut.request(makeEndpoint())

        let header = session.receivedRequests.first?.value(forHTTPHeaderField: "Authorization")
        #expect(header == "Bearer my-secret-token")
    }

    @Test func headersInterceptorAddsStaticHeaders() async throws {
        let interceptor = HeadersInterceptor(["X-App-Version": "2.0", "X-Platform": "iOS"])
        let session = MockNetworkSession.success(data: Data(sampleJSON.utf8))
        let sut = SugarNetwork(session: session, requestInterceptors: [interceptor])

        let _: Item = try await sut.request(makeEndpoint())

        let sent = session.receivedRequests.first
        #expect(sent?.value(forHTTPHeaderField: "X-App-Version") == "2.0")
        #expect(sent?.value(forHTTPHeaderField: "X-Platform") == "iOS")
    }
}

// MARK: - RetryPolicy tests

private final class CountingSession: NetworkSession, @unchecked Sendable {
    var callCount = 0
    var stubbedResults: [Result<(Data, URLResponse), Error>]
    var index = 0

    init(_ results: [Result<(Data, URLResponse), Error>]) {
        self.stubbedResults = results
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        callCount += 1
        let result = stubbedResults[min(index, stubbedResults.count - 1)]
        index += 1
        return try result.get()
    }

    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        _ = try await data(for: request)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (url, URLResponse())
    }
}

private func makeSuccessResponse(data: Data = Data(sampleJSON.utf8), code: Int = 200) -> (Data, URLResponse) {
    let http = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: code,
        httpVersion: nil,
        headerFields: nil
    )!
    return (data, http)
}

struct RetryPolicyTests {

    @Test func doesNotRetryWhenPolicyIsNone() async throws {
        let session = CountingSession([.failure(URLError(.notConnectedToInternet))])
        let sut = SugarNetwork(session: session, retryPolicy: .none)

        await #expect(throws: NetworkError.noConnection) {
            let _: Item = try await sut.request(makeEndpoint())
        }
        #expect(session.callCount == 1)
    }

    @Test func retriesUpToMaxAttempts() async throws {
        // Fails twice, succeeds on 3rd
        let session = CountingSession([
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet)),
            .success(makeSuccessResponse())
        ])
        let policy = RetryPolicy(maxAttempts: 3, backoff: .constant(0))
        let sut = SugarNetwork(session: session, retryPolicy: policy)

        let result: Item = try await sut.request(makeEndpoint())
        #expect(result == sampleItem)
        #expect(session.callCount == 3)
    }

    @Test func throwsAfterExhaustingRetries() async throws {
        let session = CountingSession([
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet)),
            .failure(URLError(.notConnectedToInternet))
        ])
        let policy = RetryPolicy(maxAttempts: 2, backoff: .constant(0))
        let sut = SugarNetwork(session: session, retryPolicy: policy)

        await #expect(throws: NetworkError.noConnection) {
            let _: Item = try await sut.request(makeEndpoint())
        }
        #expect(session.callCount == 3) // 1 original + 2 retries
    }

    @Test func doesNotRetryNonRetryableErrors() async throws {
        let session = CountingSession([.failure(URLError(.badURL))])
        let policy = RetryPolicy(maxAttempts: 3, backoff: .constant(0))
        let sut = SugarNetwork(session: session, retryPolicy: policy)

        await #expect {
            let _: Item = try await sut.request(makeEndpoint())
        } throws: { _ in true }
        #expect(session.callCount == 1)
    }

    @Test func retryableErrorsFilterLimitsScope() async throws {
        // Policy only retries .serverError, not .noConnection
        let session = CountingSession([.failure(URLError(.notConnectedToInternet))])
        let policy = RetryPolicy(
            maxAttempts: 3,
            backoff: .constant(0),
            retryableErrors: [.serverError]
        )
        let sut = SugarNetwork(session: session, retryPolicy: policy)

        await #expect(throws: NetworkError.noConnection) {
            let _: Item = try await sut.request(makeEndpoint())
        }
        #expect(session.callCount == 1) // no retries
    }

    @Test func backoffExponentialDelayCalculation() {
        let policy = RetryPolicy(
            maxAttempts: 5,
            backoff: .exponential(base: 1.0, max: 10),
            retryableErrors: nil
        )
        #expect(policy.delay(for: 1) == 1.0)   // 1 * 2^0
        #expect(policy.delay(for: 2) == 2.0)   // 1 * 2^1
        #expect(policy.delay(for: 3) == 4.0)   // 1 * 2^2
        #expect(policy.delay(for: 4) == 8.0)   // 1 * 2^3
        #expect(policy.delay(for: 5) == 10.0)  // capped at max
    }

    @Test func backoffConstantDelayCalculation() {
        let policy = RetryPolicy(maxAttempts: 3, backoff: .constant(2.5))
        #expect(policy.delay(for: 1) == 2.5)
        #expect(policy.delay(for: 2) == 2.5)
        #expect(policy.delay(for: 3) == 2.5)
    }
}

// MARK: - Endpoint & URL tests

struct EndpointTests {

    @Test func buildsURLWithQueryItems() {
        let ep = Endpoint(
            baseURL: "https://api.example.com",
            path: "/v1/items",
            queryItems: [URLQueryItem(name: "page", value: "2"), URLQueryItem(name: "limit", value: "10")]
        )
        let url = ep.url?.absoluteString ?? ""
        #expect(url.contains("page=2"))
        #expect(url.contains("limit=10"))
    }

    @Test func buildsURLWithoutQueryItems() {
        let ep = Endpoint(baseURL: "https://api.example.com", path: "/health")
        #expect(ep.url?.absoluteString == "https://api.example.com/health")
    }

    @Test func jsonFactoryEncodesBody() throws {
        let ep = try Endpoint.json(
            baseURL: "https://api.example.com",
            path: "/items",
            body: sampleItem
        )
        #expect(ep.body != nil)
        #expect(ep.headers?["Content-Type"] == "application/json")
        let decoded = try JSONDecoder().decode(Item.self, from: ep.body!)
        #expect(decoded == sampleItem)
    }

    @Test func formFactoryEncodesBody() {
        let ep = Endpoint.form(
            baseURL: "https://api.example.com",
            path: "/form",
            fields: ["name": "Sugar", "type": "network"]
        )
        let bodyString = String(data: ep.body!, encoding: .utf8) ?? ""
        #expect(ep.headers?["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(bodyString.contains("name=Sugar"))
        #expect(bodyString.contains("type=network"))
    }
}

// MARK: - RequestBuilder tests

struct RequestBuilderTests {

    @Test func buildsEndpointFromBuilder() throws {
        let ep = try RequestBuilder(baseURL: "https://api.example.com")
            .path("/search")
            .method(.post)
            .query("q", value: "swift")
            .header("Accept", value: "application/json")
            .bearer("tok123")
            .jsonBody(sampleItem)
            .build()

        #expect(ep.path == "/search")
        #expect(ep.method == .post)
        #expect(ep.headers?["Authorization"] == "Bearer tok123")
        #expect(ep.headers?["Content-Type"] == "application/json")
        #expect(ep.headers?["Accept"] == "application/json")
        #expect(ep.queryItems?.first?.name == "q")
        #expect(ep.body != nil)
    }

    @Test func basicAuthBuilder() {
        let ep = RequestBuilder(baseURL: "https://api.example.com")
            .path("/login")
            .basicAuth(username: "user", password: "pass")
            .build()

        let expected = Data("user:pass".utf8).base64EncodedString()
        #expect(ep.headers?["Authorization"] == "Basic \(expected)")
    }

    @Test func formBodyBuilder() {
        let ep = RequestBuilder(baseURL: "https://api.example.com")
            .path("/submit")
            .formBody(["key": "value"])
            .build()

        #expect(ep.headers?["Content-Type"] == "application/x-www-form-urlencoded")
        let body = String(data: ep.body!, encoding: .utf8) ?? ""
        #expect(body.contains("key=value"))
    }
}

// MARK: - MockNetworkService tests

struct MockNetworkServiceTests {

    @Test func returnsRegisteredResponse() async throws {
        let mock = MockNetworkService()
        mock.register(sampleItem, for: "/items")

        let result: Item = try await mock.request(makeEndpoint("/items/1"))
        #expect(result == sampleItem)
    }

    @Test func throwsNotFoundForUnregisteredPath() async throws {
        let mock = MockNetworkService()

        await #expect(throws: NetworkError.notFound) {
            let _: Item = try await mock.request(makeEndpoint("/unknown"))
        }
    }

    @Test func forcedErrorOverridesResponse() async throws {
        let mock = MockNetworkService()
        mock.register(sampleItem, for: "/items")
        mock.forcedError = .timeout

        await #expect(throws: NetworkError.timeout) {
            let _: Item = try await mock.request(makeEndpoint("/items"))
        }
    }

    @Test func recordsEndpoints() async throws {
        let mock = MockNetworkService()
        mock.register(sampleItem, for: "/items")

        let ep = makeEndpoint("/items")
        let _: Item = try await mock.request(ep)

        #expect(mock.recordedEndpoints.count == 1)
        #expect(mock.recordedEndpoints.first?.path == "/items")
    }

    @Test func resetClearsState() async throws {
        let mock = MockNetworkService()
        mock.register(sampleItem, for: "/items")
        mock.forcedError = .timeout
        let ep = makeEndpoint("/items")
        _ = try? await mock.request(ep) as Item

        mock.reset()

        #expect(mock.recordedEndpoints.isEmpty)
        #expect(mock.forcedError == nil)
        await #expect(throws: NetworkError.notFound) {
            let _: Item = try await mock.request(ep)
        }
    }
}

// MARK: - NetworkError tests

struct NetworkErrorTests {

    @Test func isRetryableForTransientErrors() {
        #expect(NetworkError.noConnection.isRetryable)
        #expect(NetworkError.timeout.isRetryable)
        #expect(NetworkError.serverError(statusCode: 503).isRetryable)
    }

    @Test func isNotRetryableForClientErrors() {
        #expect(!NetworkError.unauthorized.isRetryable)
        #expect(!NetworkError.forbidden.isRetryable)
        #expect(!NetworkError.notFound.isRetryable)
        #expect(!NetworkError.invalidURL.isRetryable)
        #expect(!NetworkError.decodingFailed("x").isRetryable)
    }

    @Test func fromStatusCodeMapsCorrectly() {
        #expect(NetworkError.from(statusCode: 401) == .unauthorized)
        #expect(NetworkError.from(statusCode: 403) == .forbidden)
        #expect(NetworkError.from(statusCode: 404) == .notFound)
        if case .serverError(let code) = NetworkError.from(statusCode: 500) {
            #expect(code == 500)
        } else {
            Issue.record("Expected .serverError for 500")
        }
        if case .invalidResponse(let code) = NetworkError.from(statusCode: 422) {
            #expect(code == 422)
        } else {
            Issue.record("Expected .invalidResponse for 422")
        }
    }

    @Test func rateLimitedParsesRetryAfterHeader() {
        let headers: [AnyHashable: Any] = ["Retry-After": "60"]
        if case .rateLimited(let after) = NetworkError.from(statusCode: 429, headers: headers) {
            #expect(after == 60)
        } else {
            Issue.record("Expected .rateLimited")
        }
    }
}
