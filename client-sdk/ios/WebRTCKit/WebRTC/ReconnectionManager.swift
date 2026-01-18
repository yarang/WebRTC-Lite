// MARK: - Reconnection Manager
// TRUST 5 Compliance: Testable, Unified, Trackable

import Foundation
import WebRTC
import Combine

// MARK: - Reconnection Manager

/// Manager for automatic reconnection with state machine
/// Handles reconnection states: Stable, Reconnecting, Failed
/// Implements exponential backoff and ICE restart logic
@available(iOS 13.0, *)
final class ReconnectionManager {

    // MARK: - Properties

    @Published private(set) var reconnectionState: ReconnectionState = .stable
    @Published private(set) var retryCount: Int = 0

    private let mutex = NSLock()
    private var currentAttempt: ReconnectionAttempt?

    private enum Constants {
        static let maxRetryAttempts = 3
        static let backoffDelays: [TimeInterval] = [1.0, 2.0, 4.0] // 1s, 2s, 4s
    }

    // MARK: - Nested Types

    /// Reconnection states
    enum ReconnectionState {
        case stable       // Connection is stable
        case reconnecting // Attempting to reconnect
        case failed       // All reconnection attempts failed
    }

    /// Reconnection failure types
    enum FailureType {
        case minor   // ICE restart can fix (e.g., candidate pair failure)
        case major   // Full reconnection needed (e.g., peer connection closed)
        case fatal   // Cannot recover (e.g., authentication failure)
    }

    /// Reconnection strategies
    enum ReconnectionStrategy {
        case iceRestart        // Restart ICE only (keep peer connection)
        case fullReconnection  // Full reconnection (create new peer connection)
    }

    private struct ReconnectionAttempt {
        let attemptNumber: Int
        let failureType: FailureType
        let timestamp: Date
    }

    // MARK: - Public Methods

    /// Handle connection failure and attempt reconnection
    /// - Parameters:
    ///   - failureType: Type of failure that occurred
    ///   - onReconnect: Callback to perform reconnection
    /// - Returns: Result of reconnection attempt
    func handleFailure(
        failureType: FailureType,
        onReconnect: @escaping (ReconnectionStrategy) async throws -> Void
    ) async {
        mutex.lock()

        // Check if already reconnecting
        guard reconnectionState != .reconnecting else {
            mutex.unlock()
            return
        }

        // Check if max attempts reached
        guard retryCount < Constants.maxRetryAttempts else {
            reconnectionState = .failed
            mutex.unlock()
            return
        }

        // Update state to reconnecting
        reconnectionState = .reconnecting
        let attemptNumber = retryCount + 1
        currentAttempt = ReconnectionAttempt(
            attemptNumber: attemptNumber,
            failureType: failureType,
            timestamp: Date()
        )
        retryCount = attemptNumber
        mutex.unlock()

        // Determine reconnection strategy
        let strategy: ReconnectionStrategy
        switch failureType {
        case .minor:
            strategy = .iceRestart
        case .major:
            strategy = .fullReconnection
        case .fatal:
            reconnectionState = .failed
            return
        }

        // Get backoff delay
        let backoffDelay = getCurrentBackoffDelay()

        // Wait before attempting reconnection
        try? await Task.sleep(nanoseconds: UInt64(backoffDelay * 1_000_000_000))

        // Attempt reconnection
        do {
            try await onReconnect(strategy)

            // Reconnection successful
            mutex.lock()
            reconnectionState = .stable
            retryCount = 0
            currentAttempt = nil
            mutex.unlock()

        } catch {
            // Reconnection failed
            mutex.lock()

            if attemptNumber >= Constants.maxRetryAttempts {
                reconnectionState = .failed
            } else {
                // Stay in reconnecting state for next attempt
                reconnectionState = .reconnecting
            }

            mutex.unlock()
        }
    }

    /// Reset reconnection state (call when connection is stable)
    func reset() {
        mutex.lock()
        reconnectionState = .stable
        retryCount = 0
        currentAttempt = nil
        mutex.unlock()
    }

    /// Get current backoff delay for logging
    func getCurrentBackoffDelay() -> TimeInterval {
        let attempt = retryCount
        if attempt <= Constants.backoffDelays.count {
            return Constants.backoffDelays[attempt - 1]
        } else {
            let multiplier = 1 << (attempt - Constants.backoffDelays.count)
            return Constants.backoffDelays.last! * TimeInterval(multiplier)
        }
    }

    /// Check if reconnection is possible
    func canReconnect() -> Bool {
        mutex.lock()
        let canRetry = retryCount < Constants.maxRetryAttempts &&
                       reconnectionState != .failed
        mutex.unlock()
        return canRetry
    }
}
