import Foundation

/// Fluent builder for constructing an `Endpoint`.
///
/// ```swift
/// let endpoint = RequestBuilder(baseURL: "https://api.example.com")
///     .path("/users")
///     .method(.post)
///     .header("Authorization", value: "Bearer \(token)")
///     .query("page", value: "2")
///     .jsonBody(payload, encoder: encoder)
///     .build()
/// ```
public struct RequestBuilder: Sendable {

    private var baseURL: String
    private var path: String = "/"
    private var method: HTTPMethod = .get
    private var queryItems: [URLQueryItem] = []
    private var headers: [String: String] = [:]
    private var body: Data?

    public init(baseURL: String) {
        self.baseURL = baseURL
    }

    public func path(_ path: String) -> Self {
        var copy = self; copy.path = path; return copy
    }

    public func method(_ method: HTTPMethod) -> Self {
        var copy = self; copy.method = method; return copy
    }

    public func header(_ name: String, value: String) -> Self {
        var copy = self; copy.headers[name] = value; return copy
    }

    public func headers(_ dict: [String: String]) -> Self {
        var copy = self
        dict.forEach { copy.headers[$0] = $1 }
        return copy
    }

    public func query(_ name: String, value: String) -> Self {
        var copy = self
        copy.queryItems.append(URLQueryItem(name: name, value: value))
        return copy
    }

    public func queryItems(_ items: [URLQueryItem]) -> Self {
        var copy = self; copy.queryItems += items; return copy
    }

    /// Attach a raw `Data` body and set `Content-Type`.
    public func body(_ data: Data, contentType: String) -> Self {
        var copy = self
        copy.body = data
        copy.headers["Content-Type"] = contentType
        return copy
    }

    /// Encode an `Encodable` value as JSON and attach it as the body.
    public func jsonBody<T: Encodable>(_ value: T, encoder: JSONEncoder = .init()) throws -> Self {
        let data = try encoder.encode(value)
        return body(data, contentType: "application/json")
    }

    /// Attach a `application/x-www-form-urlencoded` body.
    public func formBody(_ fields: [String: String]) -> Self {
        let encoded = fields.map { k, v -> String in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        return body(Data(encoded.utf8), contentType: "application/x-www-form-urlencoded")
    }

    /// Attach a Bearer token in the `Authorization` header.
    public func bearer(_ token: String) -> Self {
        header("Authorization", value: "Bearer \(token)")
    }

    /// Attach a Basic auth header from username and password.
    public func basicAuth(username: String, password: String) -> Self {
        let raw = "\(username):\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return header("Authorization", value: "Basic \(encoded)")
    }

    /// Finalise and return the `Endpoint`.
    public func build() -> Endpoint {
        Endpoint(
            baseURL: baseURL,
            path: path,
            method: method,
            queryItems: queryItems.isEmpty ? nil : queryItems,
            headers: headers.isEmpty ? nil : headers,
            body: body
        )
    }
}
