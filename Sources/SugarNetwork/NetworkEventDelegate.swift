import Foundation

// MARK: - NetworkEvent

/// A structured snapshot of a single HTTP transaction.
///
/// `SugarNetwork` produces one `NetworkEvent` per request/response cycle
/// and passes it to any attached `NetworkEventDelegate`.
///
/// Neither the request nor the response is mutated — this is purely observational.
public struct NetworkEvent: Sendable {

    // MARK: Identity

    /// Stable identifier shared between the "did start" and "did complete" events
    /// for the same HTTP transaction. Use it to correlate the two callbacks.
    public let requestID: UUID

    // MARK: Request

    /// The final adapted `URLRequest` that was actually sent.
    public let request: URLRequest

    // MARK: Response (nil until the server replies)

    /// HTTP status code. `nil` if the request failed before a response arrived.
    public let statusCode: Int?

    /// Raw response body. `nil` on failure or when the body is empty.
    public let responseData: Data?

    /// The raw `HTTPURLResponse`, if one was received.
    public let httpResponse: HTTPURLResponse?

    // MARK: Failure

    /// The error, if the request failed.
    public let error: Error?

    // MARK: Timing

    /// Wall-clock time when the request was sent (after interceptors ran).
    public let startedAt: Date

    /// Wall-clock time when the response (or error) arrived.
    public let finishedAt: Date

    /// Round-trip duration in milliseconds.
    public var durationMs: Int {
        Int(finishedAt.timeIntervalSince(startedAt) * 1_000)
    }

    // MARK: Computed helpers

    public var method: String { request.httpMethod ?? "?" }
    public var url: URL? { request.url }

    public var requestHeaders: [(key: String, value: String)] {
        (request.allHTTPHeaderFields ?? [:]).map { ($0.key, $0.value) }
            .sorted { $0.key < $1.key }
    }

    public var requestBody: String? {
        request.httpBody.flatMap { String(data: $0, encoding: .utf8) }
    }

    public var responseHeaders: [(key: String, value: String)] {
        guard let fields = httpResponse?.allHeaderFields else { return [] }
        return fields.compactMap { k, v -> (String, String)? in
            guard let key = k as? String else { return nil }
            return (key, "\(v)")
        }.sorted { $0.0 < $1.0 }
    }

    public var responseBody: String? {
        responseData.flatMap { $0.isEmpty ? nil : String(data: $0, encoding: .utf8) }
    }

    public var isSuccess: Bool { statusCode.map { (200...299).contains($0) } ?? false }
    public var isFailure: Bool { error != nil || (statusCode.map { $0 >= 400 } ?? false) }
}

// MARK: - NetworkEventDelegate

/// Observes HTTP transactions performed by `SugarNetwork`.
///
/// Conform any object to this protocol and assign it to `SugarNetwork.shared.delegate`
/// (or any `SugarNetwork` instance) to receive structured events for every request.
///
/// It is called from a background async context — implementations must be `Sendable`
/// and handle their own synchronisation.
///
/// ```swift
/// // Wire up once at startup:
/// SugarNetwork.shared.eventDelegate = SugarLogger.shared
/// ```
public protocol NetworkEventDelegate: AnyObject, Sendable {
    /// Called immediately before the request is sent.
    ///
    /// `event.requestID` is a stable identifier echoed back in `networkDidComplete`.
    /// `event.statusCode`, `event.responseData` etc. are all `nil` at this point.
    ///
    /// Async so implementations can `await` actor-isolated storage directly,
    /// guaranteeing this fully completes before URLSession fires.
    func networkDidStart(event: NetworkEvent) async

    /// Called once the HTTP transaction finishes (success or failure).
    /// `event.requestID` matches the one from the corresponding `networkDidStart`.
    func networkDidComplete(event: NetworkEvent) async
}
