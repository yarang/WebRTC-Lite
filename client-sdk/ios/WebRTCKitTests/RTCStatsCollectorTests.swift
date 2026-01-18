// MARK: - RTC Stats Collector Tests
// TRUST 5 Compliance: Testable, Trackable

import XCTest
import WebRTC
import Combine
@testable import WebRTCKit

// MARK: - RTC Stats Collector Tests

/// Unit tests for RTCStatsCollector
/// Tests stats collection, quality calculation, and state management
@available(iOS 13.0, *)
final class RTCStatsCollectorTests: XCTestCase {

    var sut: RTCStatsCollector!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        sut = RTCStatsCollector()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        sut = nil
        cancellables = nil
        super.tearDown()
    }

    // MARK: - Quality Score Tests

    func testQualityScoreCalculation_Excellent() {
        // Given: Excellent quality metrics
        let report = RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: 30.0,           // < 50ms
            packetLoss: 0.5,     // < 1%
            bitrate: 1_500_000.0, // > 1Mbps
            resolutionWidth: 1280,
            resolutionHeight: 720,
            bytesReceived: 10_000_000,
            bytesSent: 5_000_000,
            framesDecoded: 3000,
            framesEncoded: 3000
        )

        // When: Calculate quality score
        let score = report.calculateQualityScore()
        let state = report.getQualityState()

        // Then: Score should be >= 85 and state should be excellent
        XCTAssertTrue(score >= 85, "Score should be >= 85 for excellent quality")
        XCTAssertEqual(state, .excellent, "State should be EXCELLENT")
    }

    func testQualityScoreCalculation_Good() {
        // Given: Good quality metrics
        let report = RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: 75.0,           // < 100ms
            packetLoss: 2.0,     // < 3%
            bitrate: 750_000.0,  // > 500Kbps
            resolutionWidth: 1280,
            resolutionHeight: 720,
            bytesReceived: 10_000_000,
            bytesSent: 5_000_000,
            framesDecoded: 3000,
            framesEncoded: 3000
        )

        // When: Calculate quality score
        let score = report.calculateQualityScore()
        let state = report.getQualityState()

        // Then: Score should be 70-84 and state should be good
        XCTAssertTrue((70...84).contains(score), "Score should be 70-84 for good quality")
        XCTAssertEqual(state, .good, "State should be GOOD")
    }

    func testQualityScoreCalculation_Fair() {
        // Given: Fair quality metrics
        let report = RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: 150.0,          // < 200ms
            packetLoss: 4.0,     // < 5%
            bitrate: 300_000.0,  // > 250Kbps
            resolutionWidth: 640,
            resolutionHeight: 480,
            bytesReceived: 5_000_000,
            bytesSent: 2_500_000,
            framesDecoded: 1500,
            framesEncoded: 1500
        )

        // When: Calculate quality score
        let score = report.calculateQualityScore()
        let state = report.getQualityState()

        // Then: Score should be 50-69 and state should be fair
        XCTAssertTrue((50...69).contains(score), "Score should be 50-69 for fair quality")
        XCTAssertEqual(state, .fair, "State should be FAIR")
    }

    func testQualityScoreCalculation_Poor() {
        // Given: Poor quality metrics
        let report = RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: 250.0,          // >= 200ms
            packetLoss: 6.0,     // >= 5%
            bitrate: 100_000.0,  // <= 250Kbps
            resolutionWidth: 320,
            resolutionHeight: 240,
            bytesReceived: 1_000_000,
            bytesSent: 500_000,
            framesDecoded: 300,
            framesEncoded: 300
        )

        // When: Calculate quality score
        let score = report.calculateQualityScore()
        let state = report.getQualityState()

        // Then: Score should be < 50 and state should be poor
        XCTAssertTrue(score < 50, "Score should be < 50 for poor quality")
        XCTAssertEqual(state, .poor, "State should be POOR")
    }

    func testQualityScoreIsNeverNegative() {
        // Given: Worst possible metrics
        let report = RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: 1000.0,         // Very high
            packetLoss: 100.0,   // 100% loss
            bitrate: 0.0,        // No bitrate
            resolutionWidth: 0,
            resolutionHeight: 0,
            bytesReceived: 0,
            bytesSent: 0,
            framesDecoded: 0,
            framesEncoded: 0
        )

        // When: Calculate quality score
        let score = report.calculateQualityScore()

        // Then: Score should be 0 at minimum
        XCTAssertEqual(score, 0, "Score should be 0 at minimum")
    }

    func testQualityStateTransitions() {
        // Given: Excellent and poor reports
        let excellent = RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: 30.0, packetLoss: 0.5, bitrate: 1_500_000.0,
            resolutionWidth: 1280, resolutionHeight: 720,
            bytesReceived: 10_000_000, bytesSent: 5_000_000,
            framesDecoded: 3000, framesEncoded: 3000
        )

        let poor = RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: 250.0, packetLoss: 6.0, bitrate: 100_000.0,
            resolutionWidth: 320, resolutionHeight: 240,
            bytesReceived: 1_000_000, bytesSent: 500_000,
            framesDecoded: 300, framesEncoded: 300
        )

        // When: Get quality states
        let excellentState = excellent.getQualityState()
        let poorState = poor.getQualityState()

        // Then: States should match
        XCTAssertEqual(excellentState, .excellent, "Excellent state")
        XCTAssertEqual(poorState, .poor, "Poor state")
    }

    func testQualityStateDisplayProperties() {
        // Given: All quality states
        let states: [QualityState] = [.excellent, .good, .fair, .poor]

        // When: Get display properties
        let displayNames = states.map { $0.displayName }
        let colors = states.map { $0.color }

        // Then: Should have non-empty display names and colors
        XCTAssertFalse(displayNames.contains { $0.isEmpty }, "All states should have display names")
        XCTAssertFalse(colors.contains { $0.isEmpty }, "All states should have colors")
    }
}
