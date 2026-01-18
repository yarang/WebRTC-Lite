// MARK: - Reconnection Manager Tests
// TRUST 5 Compliance: Testable, Trackable

import XCTest
import WebRTC
import Combine
@testable import WebRTCKit

// MARK: - Reconnection Manager Tests

/// Unit tests for ReconnectionManager
/// Tests state machine, exponential backoff, and reconnection strategies
@available(iOS 13.0, *)
final class ReconnectionManagerTests: XCTestCase {

    var sut: ReconnectionManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = ReconnectionManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        sut = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialStateIsStable() {
        // Then: Initial state should be stable
        XCTAssertEqual(sut.reconnectionState, .stable, "Initial state should be STABLE")
    }

    func testRetryCountStartsAtZero() {
        // Then: Initial retry count should be 0
        XCTAssertEqual(sut.retryCount, 0, "Initial retry count should be 0")
    }

    // MARK: - Failure Type Tests

    func testMinorFailureTriggersIceRestart() async {
        // Given: Minor failure type
        var strategyUsed: ReconnectionManager.ReconnectionStrategy?
        let expectation = XCTestExpectation(description: "Reconnection attempted")

        // When: Handle minor failure
        await sut.handleFailure(failureType: .minor) { strategy in
            strategyUsed = strategy
            expectation.fulfill()
        }

        // Then: Should use ICE restart
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(strategyUsed, .iceRestart, "Should use ICE restart for minor failure")
    }

    func testMajorFailureTriggersFullReconnection() async {
        // Given: Major failure type
        var strategyUsed: ReconnectionManager.ReconnectionStrategy?
        let expectation = XCTestExpectation(description: "Reconnection attempted")

        // When: Handle major failure
        await sut.handleFailure(failureType: .major) { strategy in
            strategyUsed = strategy
            expectation.fulfill()
        }

        // Then: Should use full reconnection
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(strategyUsed, .fullReconnection, "Should use full reconnection for major failure")
    }

    func testFatalFailureSetsStateToFailed() async {
        // Given: Fatal failure type
        let expectation = XCTestExpectation(description: "State changed")

        // When: Handle fatal failure
        sut.$reconnectionState
            .dropFirst()
            .sink { state in
                if state == .failed {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        await sut.handleFailure(failureType: .fatal) { _ in }

        // Then: State should be FAILED
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(sut.reconnectionState, .failed, "State should be FAILED after fatal error")
    }

    // MARK: - Successful Reconnection Tests

    func testSuccessfulReconnectionResetsState() async {
        // Given: Minor failure that succeeds
        let expectation = XCTestExpectation(description: "State reset to stable")

        sut.$reconnectionState
            .dropFirst()
            .sink { state in
                if state == .stable {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: Handle failure with successful reconnection
        await sut.handleFailure(failureType: .minor) { _ in
            // Successful reconnection
        }

        // Then: State should return to STABLE and retry count should reset
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(sut.reconnectionState, .stable, "State should be STABLE after successful reconnection")
        XCTAssertEqual(sut.retryCount, 0, "Retry count should reset to 0")
    }

    // MARK: - Failed Reconnection Tests

    func testFailedReconnectionIncrementsRetryCount() async {
        // Given: Reconnection that fails
        struct ReconnectionError: Error {}
        let expectation = XCTestExpectation(description: "Retry count incremented")

        sut.$retryCount
            .dropFirst()
            .sink { count in
                if count == 1 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: Handle failure with failed reconnection
        await sut.handleFailure(failureType: .minor) { _ in
            throw ReconnectionError()
        }

        // Then: Retry count should increment
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(sut.retryCount, 1, "Retry count should increment")
    }

    func testMaxRetryAttemptsSetsStateToFailed() async {
        // Given: Multiple failed attempts
        struct ReconnectionError: Error {}
        let expectation = XCTestExpectation(description: "State set to failed")

        sut.$reconnectionState
            .dropFirst()
            .sink { state in
                if state == .failed {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // When: Exhaust all retry attempts
        for _ in 0..<3 {
            await sut.handleFailure(failureType: .minor) { _ in
                throw ReconnectionError()
            }
        }

        // Then: State should be FAILED
        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertEqual(sut.reconnectionState, .failed, "State should be FAILED after max retries")
    }

    // MARK: - Exponential Backoff Tests

    func testExponentialBackoffDelays() {
        // Given: Initial state
        sut.reset()

        // When: Check backoff delays
        let delay1 = sut.getCurrentBackoffDelay()
        XCTAssertEqual(delay1, 1.0, "First attempt should have 1s delay")

        // Simulate first retry
        sut.retryCount = 1
        let delay2 = sut.getCurrentBackoffDelay()
        XCTAssertEqual(delay2, 2.0, "Second attempt should have 2s delay")

        // Simulate second retry
        sut.retryCount = 2
        let delay3 = sut.getCurrentBackoffDelay()
        XCTAssertEqual(delay3, 4.0, "Third attempt should have 4s delay")
    }

    // MARK: - CanReconnect Tests

    func testCanReconnectReturnsTrueWhenRetriesAvailable() {
        // Given: Initial state
        // When: Check if can reconnect
        let canReconnect = sut.canReconnect()

        // Then: Should be able to reconnect
        XCTAssertTrue(canReconnect, "Should be able to reconnect initially")
    }

    func testCanReconnectReturnsFalseWhenMaxRetriesReached() async {
        // Given: Exhaust all retries
        struct ReconnectionError: Error {}

        for _ in 0..<3 {
            await sut.handleFailure(failureType: .minor) { _ in
                throw ReconnectionError()
            }
        }

        // When: Check if can reconnect
        let canReconnect = sut.canReconnect()

        // Then: Should not be able to reconnect
        XCTAssertFalse(canReconnect, "Should not be able to reconnect after max retries")
    }

    // MARK: - Reset Tests

    func testResetClearsReconnectionState() async {
        // Given: Trigger a failure
        struct ReconnectionError: Error {}
        await sut.handleFailure(failureType: .minor) { _ in
            throw ReconnectionError()
        }

        // When: Reset
        sut.reset()

        // Then: State and retry count should be reset
        XCTAssertEqual(sut.reconnectionState, .stable, "State should reset to STABLE")
        XCTAssertEqual(sut.retryCount, 0, "Retry count should reset to 0")
        XCTAssertTrue(sut.canReconnect(), "Should be able to reconnect after reset")
    }
}
