import Foundation

/// Determines whether and how a failed request should be retried.
public struct RetryPolicy: Sendable {

    /// Maximum number of retry attempts (not counting the original request).
    public let maxAttempts: Int

    /// Delay before each retry. `.exponential` doubles the delay on each attempt.
    public let backoff: Backoff

    /// Only retry for these error types. `nil` means retry for all `isRetryable` errors.
    public let retryableErrors: Set<NetworkErrorKind>?

    public enum Backoff: Sendable {
        case constant(TimeInterval)
        case exponential(base: TimeInterval, max: TimeInterval)

        func delay(for attempt: Int) -> TimeInterval {
            switch self {
            case .constant(let t):
                return t
            case .exponential(let base, let maxDelay):
                return min(base * pow(2.0, Double(attempt - 1)), maxDelay)
            }
        }
    }

    /// Broad category of `NetworkError` used for retry matching.
    public enum NetworkErrorKind: Hashable, Sendable {
        case noConnection, timeout, serverError
    }

    public init(
        maxAttempts: Int = 3,
        backoff: Backoff = .exponential(base: 0.5, max: 30),
        retryableErrors: Set<NetworkErrorKind>? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.backoff = backoff
        self.retryableErrors = retryableErrors
    }

    /// Returns `true` if the given error should trigger a retry on this attempt.
    func shouldRetry(error: NetworkError, attempt: Int) -> Bool {
        guard attempt <= maxAttempts else { return false }
        if let kinds = retryableErrors {
            switch error {
            case .noConnection: return kinds.contains(.noConnection)
            case .timeout:      return kinds.contains(.timeout)
            case .serverError:  return kinds.contains(.serverError)
            default:            return false
            }
        }
        return error.isRetryable
    }

    /// Seconds to wait before the given attempt number (1-indexed).
    func delay(for attempt: Int) -> TimeInterval {
        backoff.delay(for: attempt)
    }

    /// No retries.
    public static let none = RetryPolicy(maxAttempts: 0)

    /// 3 attempts with exponential backoff starting at 0.5 s.
    public static let `default` = RetryPolicy()
}
