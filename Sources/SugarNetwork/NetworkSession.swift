import Foundation

/// Abstraction over `URLSession` to allow injecting mock sessions in tests.
public protocol NetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse)
    func download(for request: URLRequest) async throws -> (URL, URLResponse)
}

extension URLSession: NetworkSession {
    public func upload(for request: URLRequest, from bodyData: Data) async throws -> (Data, URLResponse) {
        // URLSession.upload(for:from:delegate:) is the underlying method.
        // We call it explicitly to avoid infinite recursion in protocol conformance.
        try await upload(for: request, from: bodyData, delegate: nil)
    }

    public func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        // URLSession.download(for:delegate:) is the underlying method.
        try await download(for: request, delegate: nil)
    }
}
