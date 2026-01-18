// MARK: - CreateOfferUseCase
// TRUST 5 Compliance: Unified, Secured

import Foundation
import WebRTC
import Combine

// MARK: - Create Offer UseCase

/// Use case for creating and sending WebRTC offer
/// Orchestrates peer connection initialization, offer creation, and signaling
final class CreateOfferUseCase {

    // MARK: - Dependencies

    private let signalingRepository: SignalingRepositoryProtocol
    private let turnCredentialService: TurnCredentialServiceProtocol
    private let peerConnectionManager: PeerConnectionManager

    // MARK: - Initialization

    init(
        signalingRepository: SignalingRepositoryProtocol,
        turnCredentialService: TurnCredentialServiceProtocol,
        peerConnectionManager: PeerConnectionManager
    ) {
        self.signalingRepository = signalingRepository
        self.turnCredentialService = turnCredentialService
        self.peerConnectionManager = peerConnectionManager
    }

    // MARK: - Execute

    /// Execute offer creation flow
    /// - Parameters:
    ///   - sessionId: Unique session identifier
    ///   - callerId: Caller user ID
    ///   - startMedia: Whether to start local media capture (default: true)
    /// - Returns: Result indicating success or failure
    func execute(
        sessionId: String,
        callerId: String,
        startMedia: Bool = true
    ) async throws {
        // Step 1: Get TURN credentials for NAT traversal
        let turnCredential = try await turnCredentialService.getCredentials(sessionId: sessionId)

        // Step 2: Initialize peer connection with STUN/TURN servers
        try await peerConnectionManager.initialize(
            stunTurnUrls: turnCredential.uris,
            username: turnCredential.username,
            password: turnCredential.password
        )

        // Step 3: Start local media capture if requested
        if startMedia {
            try await peerConnectionManager.startLocalCapture()
        }

        // Step 4: Create SDP offer
        let offer = try await peerConnectionManager.createOffer()

        // Step 5: Set local description
        try await peerConnectionManager.setLocalDescription(offer)

        // Step 6: Send offer via signaling channel
        let offerMessage = SignalingMessage.Offer(
            sessionId: sessionId,
            sdp: offer.sdp,
            callerId: callerId
        )

        try await signalingRepository.sendOffer(sessionId: sessionId, offer: offerMessage)
    }
}

// MARK: - AnswerCallUseCase

/// Use case for answering an incoming WebRTC call
final class AnswerCallUseCase {

    // MARK: - Dependencies

    private let signalingRepository: SignalingRepositoryProtocol
    private let turnCredentialService: TurnCredentialServiceProtocol
    private let peerConnectionManager: PeerConnectionManager

    // MARK: - Initialization

    init(
        signalingRepository: SignalingRepositoryProtocol,
        turnCredentialService: TurnCredentialServiceProtocol,
        peerConnectionManager: PeerConnectionManager
    ) {
        self.signalingRepository = signalingRepository
        self.turnCredentialService = turnCredentialService
        self.peerConnectionManager = peerConnectionManager
    }

    // MARK: - Execute

    /// Execute answer call flow
    /// - Parameters:
    ///   - offer: Incoming offer message
    ///   - calleeId: Callee user ID
    ///   - startMedia: Whether to start local media capture (default: true)
    /// - Returns: Result indicating success or failure
    func execute(
        offer: SignalingMessage.Offer,
        calleeId: String,
        startMedia: Bool = true
    ) async throws {
        // Step 1: Get TURN credentials for NAT traversal
        let turnCredential = try await turnCredentialService.getCredentials(sessionId: offer.sessionId)

        // Step 2: Initialize peer connection with STUN/TURN servers
        try await peerConnectionManager.initialize(
            stunTurnUrls: turnCredential.uris,
            username: turnCredential.username,
            password: turnCredential.password
        )

        // Step 3: Start local media capture if requested
        if startMedia {
            try await peerConnectionManager.startLocalCapture()
        }

        // Step 4: Set remote description (the offer)
        let remoteDescription = RTCSessionDescription(
            type: .offer,
            sdp: offer.sdp
        )
        try await peerConnectionManager.setRemoteDescription(remoteDescription)

        // Step 5: Create SDP answer
        let answer = try await peerConnectionManager.createAnswer()

        // Step 6: Set local description
        try await peerConnectionManager.setLocalDescription(answer)

        // Step 7: Send answer via signaling channel
        let answerMessage = SignalingMessage.Answer(
            sessionId: offer.sessionId,
            sdp: answer.sdp,
            calleeId: calleeId
        )

        try await signalingRepository.sendAnswer(sessionId: offer.sessionId, answer: answerMessage)
    }
}

// MARK: - AddIceCandidateUseCase

/// Use case for handling ICE candidates during WebRTC connection
final class AddIceCandidateUseCase {

    // MARK: - Dependencies

    private let signalingRepository: SignalingRepositoryProtocol
    private let peerConnectionManager: PeerConnectionManager

    // MARK: - Initialization

    init(
        signalingRepository: SignalingRepositoryProtocol,
        peerConnectionManager: PeerConnectionManager
    ) {
        self.signalingRepository = signalingRepository
        self.peerConnectionManager = peerConnectionManager
    }

    // MARK: - Execute

    /// Add remote ICE candidate to peer connection
    /// - Parameter candidate: ICE candidate message
    /// - Returns: Result indicating success or failure
    func execute(candidate: SignalingMessage.IceCandidate) async throws {
        let rtcCandidate = RTCIceCandidate(
            sdp: candidate.sdpCandidate,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )

        try await peerConnectionManager.addIceCandidate(rtcCandidate)
    }

    /// Signal local ICE candidate to remote peer
    /// - Parameters:
    ///   - sessionId: Session identifier
    ///   - candidateId: Unique candidate identifier
    ///   - candidate: ICE candidate
    /// - Returns: Result indicating success or failure
    func signalLocalCandidate(
        sessionId: String,
        candidateId: String,
        candidate: RTCIceCandidate
    ) async throws {
        let candidateMessage = SignalingMessage.IceCandidate(
            sessionId: sessionId,
            sdpMid: candidate.sdpMid ?? "",
            sdpMLineIndex: candidate.sdpMLineIndex,
            sdpCandidate: candidate.sdp
        )

        try await signalingRepository.sendIceCandidate(
            sessionId: sessionId,
            candidateId: candidateId,
            candidate: candidateMessage
        )
    }
}

// MARK: - EndCallUseCase

/// Use case for ending an active WebRTC call
final class EndCallUseCase {

    // MARK: - Dependencies

    private let signalingRepository: SignalingRepositoryProtocol
    private let peerConnectionManager: PeerConnectionManager

    // MARK: - Initialization

    init(
        signalingRepository: SignalingRepositoryProtocol,
        peerConnectionManager: PeerConnectionManager
    ) {
        self.signalingRepository = signalingRepository
        self.peerConnectionManager = peerConnectionManager
    }

    // MARK: - Execute

    /// End call and cleanup resources
    /// - Parameters:
    ///   - sessionId: Session identifier
    ///   - userId: User ID ending the call
    ///   - reason: Optional reason for ending call
    /// - Returns: Result indicating success or failure
    func execute(
        sessionId: String,
        userId: String,
        reason: String? = nil
    ) async throws {
        // Step 1: Send hangup message
        let hangupMessage = SignalingMessage.Hangup(
            sessionId: sessionId,
            userId: userId,
            reason: reason
        )

        try? await signalingRepository.sendOffer(
            sessionId: sessionId,
            offer: SignalingMessage.Offer(
                sessionId: sessionId,
                sdp: "",
                callerId: userId
            )
        )

        // Step 2: Close peer connection
        try await peerConnectionManager.close()

        // Step 3: Delete session from Firestore
        try await signalingRepository.deleteSession(sessionId: sessionId)
    }
}

// MARK: - CallSession Entity

/// Represents an active WebRTC call session
struct CallSession: Equatable {
    let sessionId: String
    let peerId: String
    let state: CallState
    let direction: CallDirection
    let startTime: Date?
    let duration: TimeInterval?

    enum CallState {
        case idle
        case connecting
        case connected
        case ended
        case error(Error)
    }

    enum CallDirection {
        case incoming
        case outgoing
    }

    var isActive: Bool {
        switch state {
        case .connecting, .connected:
            return true
        default:
            return false
        }
    }

    static func == (lhs: CallSession, rhs: CallSession) -> Bool {
        lhs.sessionId == rhs.sessionId &&
        lhs.peerId == rhs.peerId &&
        lhs.direction == rhs.direction
    }
}

// MARK: - Errors

enum UseCaseError: LocalizedError {
    case turnCredentialFetchFailed
    case peerConnectionNotInitialized
    case offerCreationFailed
    case answerCreationFailed
    case signalingFailed
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .turnCredentialFetchFailed:
            return "Failed to fetch TURN credentials"
        case .peerConnectionNotInitialized:
            return "Peer connection not initialized"
        case .offerCreationFailed:
            return "Failed to create offer"
        case .answerCreationFailed:
            return "Failed to create answer"
        case .signalingFailed:
            return "Signaling operation failed"
        case .sessionNotFound:
            return "Session not found"
        }
    }
}
