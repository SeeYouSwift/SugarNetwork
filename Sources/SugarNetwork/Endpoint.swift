import Foundation

/// Describes a single HTTP request: URL, method, headers, query, and body.
public struct Endpoint: Sendable {

    // MARK: - Core

    public let baseURL: String
    public let path: String
    public var method: HTTPMethod
    public var queryItems: [URLQueryItem]?

    // MARK: - Headers & Body

    /// Additional HTTP headers merged on top of any defaults set in `SugarNetwork`.
    public var headers: [String: String]?

    /// Raw body data. Set directly or via one of the convenience helpers below.
    public var body: Data?

    // MARK: - Init

    public init(
        baseURL: String,
        path: String,
        method: HTTPMethod = .get,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        body: Data? = nil
    ) {
        self.baseURL = baseURL
        self.path = path
        self.method = method
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }

    // MARK: - URL

    /// Assembled URL including query parameters.
    public var url: URL? {
        var components = URLComponents(string: baseURL)
        components?.path += path
        if let items = queryItems, !items.isEmpty {
            components?.queryItems = items
        }
        return components?.url
    }

    // MARK: - Convenience body helpers

    /// Create an endpoint with a JSON-encodable body.
    /// Sets `Content-Type: application/json` automatically.
    public static func json<Body: Encodable & Sendable>(
        baseURL: String,
        path: String,
        method: HTTPMethod = .post,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        body: Body,
        encoder: JSONEncoder = .init()
    ) throws -> Endpoint {
        let data = try encoder.encode(body)
        var h = headers ?? [:]
        h["Content-Type"] = "application/json"
        return Endpoint(
            baseURL: baseURL,
            path: path,
            method: method,
            queryItems: queryItems,
            headers: h,
            body: data
        )
    }

    /// Create an endpoint with a `application/x-www-form-urlencoded` body.
    public static func form(
        baseURL: String,
        path: String,
        method: HTTPMethod = .post,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String]? = nil,
        fields: [String: String]
    ) -> Endpoint {
        let bodyString = fields
            .map { k, v in
                let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
                let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
                return "\(ek)=\(ev)"
            }
            .joined(separator: "&")
        var h = headers ?? [:]
        h["Content-Type"] = "application/x-www-form-urlencoded"
        return Endpoint(
            baseURL: baseURL,
            path: path,
            method: method,
            queryItems: queryItems,
            headers: h,
            body: Data(bodyString.utf8)
        )
    }
}
