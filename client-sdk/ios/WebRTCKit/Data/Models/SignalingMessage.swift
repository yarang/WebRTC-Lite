// MARK: - SignalingMessage
// TRUST 5 Compliance: Testable, Readable

import Foundation

/// WebRTC signaling messages for Firestore-based signaling exchange
enum SignalingMessage: Codable, Equatable {
    // MARK: - Types

    /// SDP Offer message from caller
    case offer(Offer)
    /// SDP Answer message from callee
    case answer(Answer)
    /// ICE Candidate message for establishing connection
    case iceCandidate(IceCandidate)
    /// TURN server credentials for NAT traversal
    case turnCredential(TurnCredential)
    /// Hangup message to end call
    case hangup(Hangup)

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case type
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "offer":
            self = try .offer(from: decoder)
        case "answer":
            self = try .answer(from: decoder)
        case "ice-candidate":
            self = try .iceCandidate(from: decoder)
        case "turn-credential":
            self = try .turnCredential(from: decoder)
        case "hangup":
            self = try .hangup(from: decoder)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid signaling message type: \(type)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .offer(let offer):
            try container.encode(offer.type, forKey: .type)
            try offer.encode(to: encoder)
        case .answer(let answer):
            try container.encode(answer.type, forKey: .type)
            try answer.encode(to: encoder)
        case .iceCandidate(let candidate):
            try container.encode(candidate.type, forKey: .type)
            try candidate.encode(to: encoder)
        case .turnCredential(let credential):
            try container.encode(credential.type, forKey: .type)
            try credential.encode(to: encoder)
        case .hangup(let hangup):
            try container.encode(hangup.type, forKey: .type)
            try hangup.encode(to: encoder)
        }
    }

    // MARK: - Base Protocol

    var type: String {
        switch self {
        case .offer: return "offer"
        case .answer: return "answer"
        case .iceCandidate: return "ice-candidate"
        case .turnCredential: return "turn-credential"
        case .hangup: return "hangup"
        }
    }

    var sessionId: String {
        switch self {
        case .offer(let offer): return offer.sessionId
        case .answer(let answer): return answer.sessionId
        case .iceCandidate(let candidate): return candidate.sessionId
        case .turnCredential(let credential): return credential.sessionId
        case .hangup(let hangup): return hangup.sessionId
        }
    }
}

// MARK: - Message Types

extension SignalingMessage {

    /// SDP Offer message from caller
    struct Offer: Codable, Equatable {
        let sessionId: String
        let sdp: String
        let callerId: String
        let timestamp: Int64

        var type: String { "offer" }

        init(sessionId: String, sdp: String, callerId: String, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
            self.sessionId = sessionId
            self.sdp = sdp
            self.callerId = callerId
            self.timestamp = timestamp
        }

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case sdp
            case callerId
            case timestamp
        }
    }

    /// SDP Answer message from callee
    struct Answer: Codable, Equatable {
        let sessionId: String
        let sdp: String
        let calleeId: String
        let timestamp: Int64

        var type: String { "answer" }

        init(sessionId: String, sdp: String, calleeId: String, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
            self.sessionId = sessionId
            self.sdp = sdp
            self.calleeId = calleeId
            self.timestamp = timestamp
        }

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case sdp
            case calleeId
            case timestamp
        }
    }

    /// ICE Candidate message for establishing connection
    struct IceCandidate: Codable, Equatable {
        let sessionId: String
        let sdpMid: String
        let sdpMLineIndex: Int32
        let sdpCandidate: String
        let timestamp: Int64

        var type: String { "ice-candidate" }

        init(sessionId: String, sdpMid: String, sdpMLineIndex: Int32, sdpCandidate: String, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
            self.sessionId = sessionId
            self.sdpMid = sdpMid
            self.sdpMLineIndex = sdpMLineIndex
            self.sdpCandidate = sdpCandidate
            self.timestamp = timestamp
        }

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case sdpMid
            case sdpMLineIndex
            case sdpCandidate
            case timestamp
        }
    }

    /// TURN server credentials for NAT traversal
    struct TurnCredential: Codable, Equatable {
        let sessionId: String
        let username: String
        let password: String
        let ttl: Int
        let urls: [String]
        let timestamp: Int64

        var type: String { "turn-credential" }

        init(sessionId: String, username: String, password: String, ttl: Int, urls: [String], timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
            self.sessionId = sessionId
            self.username = username
            self.password = password
            self.ttl = ttl
            self.urls = urls
            self.timestamp = timestamp
        }

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case username
            case password
            case ttl
            case urls
            case timestamp
        }
    }

    /// Hangup message to end call
    struct Hangup: Codable, Equatable {
        let sessionId: String
        let userId: String
        let reason: String?
        let timestamp: Int64

        var type: String { "hangup" }

        init(sessionId: String, userId: String, reason: String? = nil, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
            self.sessionId = sessionId
            self.userId = userId
            self.reason = reason
            self.timestamp = timestamp
        }

        private enum CodingKeys: String, CodingKey {
            case sessionId
            case userId
            case reason
            case timestamp
        }
    }
}

// MARK: - SessionDescription (WebRTC)

/// WebRTC Session Description wrapper
struct RTCSessionDescription: Codable, Equatable {
    let type: SdpType
    let sdp: String

    enum SdpType: String, Codable {
        case offer
        case answer
        case prAnswer
        case rollback
    }

    init(type: SdpType, sdp: String) {
        self.type = type
        self.sdp = sdp
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case sdp
    }
}
