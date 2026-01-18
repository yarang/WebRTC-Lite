// MARK: - SignalingMessageTests
// TRUST 5 Compliance: Testable, Readable

import XCTest
@testable import WebRTCKit

/// Characterization tests for SignalingMessage serialization/deserialization
final class SignalingMessageTests: XCTestCase {

    // MARK: - Offer Tests

    func testOfferSerialization() throws {
        // Given
        let offer = SignalingMessage.Offer(
            sessionId: "test-session-123",
            sdp: "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...",
            callerId: "user-abc"
        )

        // When
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(offer)
        let jsonString = String(data: jsonData, encoding: .utf8)

        // Then
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("test-session-123"))
        XCTAssertTrue(jsonString!.contains("user-abc"))
        XCTAssertTrue(jsonString!.contains("offer"))
    }

    func testOfferDeserialization() throws {
        // Given
        let jsonString = """
        {
            "type": "offer",
            "sessionId": "test-session-123",
            "sdp": "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...",
            "callerId": "user-abc",
            "timestamp": 1234567890
        }
        """

        // When
        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let offer = try decoder.decode(SignalingMessage.Offer.self, from: jsonData)

        // Then
        XCTAssertEqual(offer.sessionId, "test-session-123")
        XCTAssertEqual(offer.callerId, "user-abc")
        XCTAssertEqual(offer.sdp, "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...")
        XCTAssertEqual(offer.timestamp, 1234567890)
    }

    func testOfferEnumWrapping() throws {
        // Given
        let offerMessage = SignalingMessage.offer(
            SignalingMessage.Offer(
                sessionId: "session-123",
                sdp: "test-sdp",
                callerId: "caller-abc"
            )
        )

        // When
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(offerMessage)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SignalingMessage.self, from: jsonData)

        // Then
        if case .offer(let offer) = decoded {
            XCTAssertEqual(offer.sessionId, "session-123")
            XCTAssertEqual(offer.callerId, "caller-abc")
        } else {
            XCTFail("Expected .offer case")
        }
    }

    // MARK: - Answer Tests

    func testAnswerSerialization() throws {
        // Given
        let answer = SignalingMessage.Answer(
            sessionId: "test-session-456",
            sdp: "v=0\r\no=- 789012 2 IN IP4 127.0.0.1\r\n...",
            calleeId: "user-xyz"
        )

        // When
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(answer)
        let jsonString = String(data: jsonData, encoding: .utf8)

        // Then
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("test-session-456"))
        XCTAssertTrue(jsonString!.contains("user-xyz"))
        XCTAssertTrue(jsonString!.contains("answer"))
    }

    func testAnswerDeserialization() throws {
        // Given
        let jsonString = """
        {
            "type": "answer",
            "sessionId": "test-session-456",
            "sdp": "v=0\r\no=- 789012 2 IN IP4 127.0.0.1\r\n...",
            "calleeId": "user-xyz",
            "timestamp": 1234567890
        }
        """

        // When
        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let answer = try decoder.decode(SignalingMessage.Answer.self, from: jsonData)

        // Then
        XCTAssertEqual(answer.sessionId, "test-session-456")
        XCTAssertEqual(answer.calleeId, "user-xyz")
        XCTAssertEqual(answer.sdp, "v=0\r\no=- 789012 2 IN IP4 127.0.0.1\r\n...")
    }

    // MARK: - ICE Candidate Tests

    func testIceCandidateSerialization() throws {
        // Given
        let candidate = SignalingMessage.IceCandidate(
            sessionId: "session-789",
            sdpMid: "0",
            sdpMLineIndex: 0,
            sdpCandidate: "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host"
        )

        // When
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(candidate)
        let jsonString = String(data: jsonData, encoding: .utf8)

        // Then
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("session-789"))
        XCTAssertTrue(jsonString!.contains("192.168.1.1"))
        XCTAssertTrue(jsonString!.contains("ice-candidate"))
    }

    func testIceCandidateDeserialization() throws {
        // Given
        let jsonString = """
        {
            "type": "ice-candidate",
            "sessionId": "session-789",
            "sdpMid": "0",
            "sdpMLineIndex": 0,
            "sdpCandidate": "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host",
            "timestamp": 1234567890
        }
        """

        // When
        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let candidate = try decoder.decode(SignalingMessage.IceCandidate.self, from: jsonData)

        // Then
        XCTAssertEqual(candidate.sessionId, "session-789")
        XCTAssertEqual(candidate.sdpMid, "0")
        XCTAssertEqual(candidate.sdpMLineIndex, 0)
        XCTAssertEqual(candidate.sdpCandidate, "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host")
    }

    // MARK: - TURN Credential Tests

    func testTurnCredentialSerialization() throws {
        // Given
        let credential = SignalingMessage.TurnCredential(
            sessionId: "session-999",
            username: "turn-user",
            password: "turn-pass",
            ttl: 86400,
            urls: ["turn:turn.example.com:3478?transport=udp"]
        )

        // When
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(credential)
        let jsonString = String(data: jsonData, encoding: .utf8)

        // Then
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("session-999"))
        XCTAssertTrue(jsonString!.contains("turn-user"))
        XCTAssertTrue(jsonString!.contains("turn-credential"))
    }

    func testTurnCredentialDeserialization() throws {
        // Given
        let jsonString = """
        {
            "type": "turn-credential",
            "sessionId": "session-999",
            "username": "turn-user",
            "password": "turn-pass",
            "ttl": 86400,
            "urls": ["turn:turn.example.com:3478?transport=udp"],
            "timestamp": 1234567890
        }
        """

        // When
        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let credential = try decoder.decode(SignalingMessage.TurnCredential.self, from: jsonData)

        // Then
        XCTAssertEqual(credential.sessionId, "session-999")
        XCTAssertEqual(credential.username, "turn-user")
        XCTAssertEqual(credential.password, "turn-pass")
        XCTAssertEqual(credential.ttl, 86400)
        XCTAssertEqual(credential.urls.count, 1)
    }

    // MARK: - Hangup Tests

    func testHangupSerialization() throws {
        // Given
        let hangup = SignalingMessage.Hangup(
            sessionId: "session-end",
            userId: "user-123",
            reason: "User ended call"
        )

        // When
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(hangup)
        let jsonString = String(data: jsonData, encoding: .utf8)

        // Then
        XCTAssertNotNil(jsonString)
        XCTAssertTrue(jsonString!.contains("session-end"))
        XCTAssertTrue(jsonString!.contains("user-123"))
        XCTAssertTrue(jsonString!.contains("hangup"))
    }

    func testHangupDeserialization() throws {
        // Given
        let jsonString = """
        {
            "type": "hangup",
            "sessionId": "session-end",
            "userId": "user-123",
            "reason": "User ended call",
            "timestamp": 1234567890
        }
        """

        // When
        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let hangup = try decoder.decode(SignalingMessage.Hangup.self, from: jsonData)

        // Then
        XCTAssertEqual(hangup.sessionId, "session-end")
        XCTAssertEqual(hangup.userId, "user-123")
        XCTAssertEqual(hangup.reason, "User ended call")
    }

    // MARK: - Edge Cases

    func testSignalingMessageWithSpecialCharacters() throws {
        // Given
        let offer = SignalingMessage.Offer(
            sessionId: "session-with-\"quotes\"",
            sdp: "sdp-with-\n-newlines",
            callerId: "user-with-unicode-\u{1F4DE}"
        )

        // When
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(offer)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SignalingMessage.Offer.self, from: jsonData)

        // Then
        XCTAssertEqual(decoded.sessionId, offer.sessionId)
        XCTAssertEqual(decoded.sdp, offer.sdp)
        XCTAssertEqual(decoded.callerId, offer.callerId)
    }

    func testSignalingMessageTimestampDefaults() throws {
        // Given
        let before = Int64(Date().timeIntervalSince1970 * 1000)
        let offer = SignalingMessage.Offer(
            sessionId: "session-timestamp",
            sdp: "test-sdp",
            callerId: "caller-timestamp"
        )
        let after = Int64(Date().timeIntervalSince1970 * 1000)

        // Then
        XCTAssertGreaterThanOrEqual(offer.timestamp, before)
        XCTAssertLessThanOrEqual(offer.timestamp, after)
    }
}
