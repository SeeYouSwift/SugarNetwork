# SugarNetwork

A production-ready, generic HTTP client for Swift. Wraps `URLSession` with full async/await support, typed response models, request/response interceptors, automatic retry with backoff, multipart upload, file download, and first-class mock support for testing.

## Features

- **Typed decoding** — `request<T: Decodable>` and `response<T>` returning `NetworkResponse<T>` (decoded value + raw HTTP metadata)
- **Raw access** — `raw(_:)` returns bytes + HTTP metadata without any JSON decoding
- **Interceptor chain** — `RequestInterceptor` and `ResponseInterceptor` for auth headers, logging, token refresh, etc.
- **Auto-retry** — `RetryPolicy` with `.constant` or `.exponential` backoff; per-error-kind filtering
- **Upload** — raw data upload and `multipart/form-data` with `MultipartPart` helpers
- **Download** — download any file to a local temporary URL
- **RequestBuilder** — fluent API for constructing `Endpoint` step by step
- **Friendly errors** — `NetworkError` with specific cases for 401, 403, 404, 429, 5xx, no-connection, timeout, and more
- **Protocol-based** — inject `MockNetworkService` or `MockNetworkSession` in tests, zero real HTTP needed

## Requirements

- iOS 18+ / macOS 15+
- Swift 6+

## Installation

### Swift Package Manager

**Via Xcode:**
1. File → Add Package Dependencies
2. Enter the repository URL:
   ```
   https://github.com/SeeYouSwift/SugarNetwork
   ```
3. Select version rule and click **Add Package**

**Via `Package.swift`:**

```swift
dependencies: [
    .package(url: "https://github.com/SeeYouSwift/SugarNetwork", from: "1.0.0")
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["SugarNetwork"]
    ),
    // For test targets — add the mock library:
    .testTarget(
        name: "YourTargetTests",
        dependencies: [
            "YourTarget",
            .product(name: "SugarNetworkMocks", package: "SugarNetwork")
        ]
    )
]
```

---

## Quick Start

```swift
import SugarNetwork

// 1. Create a client
let network = SugarNetwork(
    requestInterceptors: [
        BearerTokenInterceptor { await tokenStore.accessToken },
        LoggingInterceptor(verbose: true)
    ],
    retryPolicy: .default   // 3 retries, exponential backoff starting at 0.5s
)

// 2. Define an endpoint
let endpoint = Endpoint(baseURL: "https://api.example.com", path: "/users")

// 3. Decode directly into your model
let users: [User] = try await network.request(endpoint)

// 4. Or get the full HTTP response
let response: NetworkResponse<[User]> = try await network.response(endpoint)
print(response.statusCode)                         // 200
print(response.header("X-Request-Id") ?? "none")  // request-id header
```

---

## Usage

### Endpoint

Describe any HTTP request with `Endpoint`:

```swift
// Simple GET
let list = Endpoint(baseURL: "https://api.example.com", path: "/dogs")

// POST with JSON body
let create = try Endpoint.json(
    baseURL: "https://api.example.com",
    path: "/dogs",
    method: .post,
    body: NewDog(name: "Rex", breed: "Husky")
)

// POST with form body
let login = Endpoint.form(
    baseURL: "https://api.example.com",
    path: "/auth/login",
    fields: ["username": "user@example.com", "password": "secret"]
)
```

### RequestBuilder

Use `RequestBuilder` for a fluent construction style:

```swift
let endpoint = try RequestBuilder(baseURL: "https://api.example.com")
    .path("/search")
    .method(.get)
    .query("q", value: "labrador")
    .query("page", value: "2")
    .header("Accept-Language", value: "en")
    .bearer(accessToken)
    .build()
```

### Typed Response

`NetworkResponse<T>` gives you the decoded value **and** HTTP metadata:

```swift
let response: NetworkResponse<Dog> = try await network.response(endpoint)

print(response.value)                   // Dog model
print(response.statusCode)              // 200
print(response.header("ETag") ?? "-")  // response header
print(response.data)                    // raw bytes
```

### Raw Bytes

Skip JSON decoding and get the raw body:

```swift
let raw: RawResponse = try await network.raw(endpoint)
print(raw.statusCode)
// process raw.data yourself
```

### Upload

```swift
// Raw data
let pngData: Data = ...
let result: UploadResponse = try await network.upload(
    data: pngData,
    to: Endpoint(baseURL: "https://api.example.com", path: "/photos", method: .post),
    mimeType: "image/png"
)

// Multipart form-data
let result: UploadResponse = try await network.uploadMultipart(
    parts: [
        .jpeg(photoData, name: "avatar"),
        .text("Rex", name: "name")
    ],
    to: Endpoint(baseURL: "https://api.example.com", path: "/profile", method: .post)
)
```

### Download

```swift
let fileURL: URL = try await network.download(
    Endpoint(baseURL: "https://files.example.com", path: "/report.pdf")
)
// fileURL is a temporary local path — copy it before it is cleaned up
```

---

## Interceptors

### Built-in interceptors

```swift
// Attach a bearer token from an async provider
BearerTokenInterceptor(tokenProvider: { await tokenStore.accessToken })

// Inject static headers on every request
HeadersInterceptor([
    "X-App-Version": Bundle.main.appVersion,
    "X-Platform": "iOS"
])

// Log requests and responses to the console
LoggingInterceptor(verbose: true)  // verbose = include body
```

### Custom interceptors

Implement `RequestInterceptor` to modify outgoing requests:

```swift
struct LocaleInterceptor: RequestInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var r = request
        r.setValue(Locale.current.identifier, forHTTPHeaderField: "Accept-Language")
        return r
    }
}
```

Implement `ResponseInterceptor` to react to responses (e.g. refresh tokens on 401):

```swift
struct TokenRefreshInterceptor: ResponseInterceptor {
    func process(response: HTTPURLResponse, data: Data, for request: URLRequest) async throws {
        if response.statusCode == 401 {
            await tokenStore.refresh()
        }
    }
}
```

Combine multiple interceptors:

```swift
let network = SugarNetwork(
    requestInterceptors: [
        HeadersInterceptor(["X-Platform": "iOS"]),
        BearerTokenInterceptor { await tokenStore.token },
        LoggingInterceptor()
    ],
    responseInterceptors: [
        TokenRefreshInterceptor()
    ]
)
```

---

## Retry Policy

```swift
// No retries (default)
RetryPolicy.none

// 3 retries with exponential backoff starting at 0.5s, max 30s (library default)
RetryPolicy.default

// Custom: 5 retries, constant 1-second delay, only for server errors
RetryPolicy(
    maxAttempts: 5,
    backoff: .constant(1.0),
    retryableErrors: [.serverError]
)

// Exponential: 0.5s, 1s, 2s, 4s — capped at 10s
RetryPolicy(
    maxAttempts: 4,
    backoff: .exponential(base: 0.5, max: 10)
)
```

Retryable errors by default: `.noConnection`, `.timeout`, `.serverError` (5xx).

---

## Error Handling

```swift
do {
    let user: User = try await network.request(endpoint)
} catch NetworkError.unauthorized {
    // Redirect to login
} catch NetworkError.notFound {
    // Show 404 message
} catch NetworkError.rateLimited(let retryAfter) {
    // Wait retryAfter seconds
} catch NetworkError.noConnection {
    // Show offline banner
} catch NetworkError.decodingFailed(let description) {
    // Log decoding mismatch
} catch {
    // Unexpected error
}
```

### `NetworkError` cases

| Case | Description |
|------|-------------|
| `.invalidURL` | `Endpoint.url` resolved to `nil` |
| `.invalidResponse(statusCode:)` | Unmapped non-2xx status |
| `.decodingFailed(String)` | `JSONDecoder` threw an error |
| `.emptyResponse` | Body was empty when decoding was expected |
| `.unauthorized` | HTTP 401 |
| `.forbidden` | HTTP 403 |
| `.notFound` | HTTP 404 |
| `.rateLimited(retryAfter:)` | HTTP 429 — includes `Retry-After` if present |
| `.serverError(statusCode:)` | HTTP 5xx |
| `.noConnection` | Device is offline |
| `.timeout` | Request exceeded timeout |
| `.cancelled` | Task was cancelled |
| `.underlying(Error)` | Other URLSession / system error |

---

## Testing

### MockNetworkService

Inject `MockNetworkService` to test services without real HTTP:

```swift
import SugarNetworkMocks

let mock = MockNetworkService()
mock.register(Dog(name: "Rex", breed: "Husky"), for: "/dogs")

let repo = DogRepository(network: mock)
let dogs = try await repo.fetchDogs()  // hits the mock

// Assert which endpoints were called
print(mock.recordedEndpoints.map(\.path))

// Simulate errors
mock.forcedError = .timeout

// Clean up between tests
mock.reset()
```

### MockNetworkSession

For lower-level pipeline tests (interceptors, retry, error mapping):

```swift
import SugarNetworkMocks

// Successful JSON response
let session = MockNetworkSession.success(data: Data(json.utf8))

// Successful response from an Encodable model
let session = try MockNetworkSession.success(model: myModel, statusCode: 201)

// Simulate URLError
let session = MockNetworkSession.urlError(.notConnectedToInternet)

// Check what was sent
let sut = SugarNetwork(session: session, requestInterceptors: [myInterceptor])
let _: MyModel = try await sut.request(endpoint)
let sentHeader = session.receivedRequests.first?.value(forHTTPHeaderField: "Authorization")
```

---

## API Reference

### `SugarNetwork` initializer

| Parameter | Default | Description |
|-----------|---------|-------------|
| `session` | `URLSession.shared` | Injectable for testing |
| `decoder` | `JSONDecoder()` | Custom date strategies, key decoding, etc. |
| `timeoutInterval` | `30` seconds | Per-request timeout |
| `requestInterceptors` | `[]` | Applied in order before sending |
| `responseInterceptors` | `[]` | Applied in order after receiving |
| `retryPolicy` | `.none` | Retry strategy for transient failures |

### `SugarNetworkProtocol` methods

| Method | Description |
|--------|-------------|
| `request<T: Decodable>(_ endpoint:)` | Decode response directly to `T` |
| `response<T: Decodable & Sendable>(_ endpoint:)` | Return `NetworkResponse<T>` with metadata |
| `raw(_ endpoint:)` | Return `RawResponse` (no decoding) |
| `upload<T>(data:to:mimeType:)` | Upload raw `Data`, decode response |
| `uploadMultipart<T>(parts:to:)` | Upload `multipart/form-data`, decode response |
| `download(_ endpoint:)` | Download file to a temporary `URL` |

### `HTTPMethod`

`GET` · `POST` · `PUT` · `PATCH` · `DELETE` · `HEAD` · `OPTIONS`
