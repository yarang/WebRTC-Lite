// MARK: - CallState
// TRUST 5 Compliance: Testable, Readable

import Foundation
import SwiftUI

// MARK: - Call State

/// WebRTC call states
enum CallState: Equatable {
    /// Initial state before call starts
    case idle
    /// Connecting to signaling server
    case connecting
    /// Waiting for remote peer to answer
    case waitingForAnswer(sessionId: String)
    /// Call is active and connected
    case connected(sessionId: String)
    /// Call is being ended
    case ending
    /// Call has ended
    case ended(reason: String?)
    /// Error state
    case error(message: String)

    static func == (lhs: CallState, rhs: CallState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.connecting, .connecting),
             (.ending, .ending):
            return true
        case (.waitingForAnswer(let lhsId), .waitingForAnswer(let rhsId)),
             (.connected(let lhsId), .connected(let rhsId)):
            return lhsId == rhsId
        case (.ended(let lhsReason), .ended(let rhsReason)):
            return lhsReason == rhsReason
        case (.error(let lhsMessage), .error(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - Call Controls State

/// UI state for call controls
struct CallControlsState: Equatable {
    var isCameraEnabled: Bool = true
    var isMicrophoneEnabled: Bool = true
    var isSpeakerEnabled: Bool = false
    var isLocalVideoVisible: Bool = true
    var isRemoteVideoVisible: Bool = false
    var connectionDuration: TimeInterval = 0
    var localIceCandidates: Int = 0
    var remoteIceCandidates: Int = 0
}

// MARK: - Call UI Event

/// UI events for call interaction
enum CallUiEvent {
    /// Start outgoing call
    case startCall(targetUserId: String)
    /// Answer incoming call
    case answerCall(offer: SignalingMessage.Offer)
    /// End active call
    case endCall
    /// Toggle camera
    case toggleCamera(enabled: Bool)
    /// Toggle microphone
    case toggleMicrophone(enabled: Bool)
    /// Switch camera
    case switchCamera
    /// Toggle speaker
    case toggleSpeaker(enabled: Bool)
    /// Dismiss error
    case dismissError
}

// MARK: - Call Permission

/// Camera and microphone permission state
enum CallPermission {
    case notDetermined
    case authorized
    case denied
    case restricted
}

// MARK: - Media Track State

/// Media track state for local and remote tracks
struct MediaTrackState {
    let isVideoEnabled: Bool
    let isAudioEnabled: Bool
    let videoTrack: RTCVideoTrack?
    let audioTrack: RTCAudioTrack?

    static let empty = MediaTrackState(
        isVideoEnabled: false,
        isAudioEnabled: false,
        videoTrack: nil,
        audioTrack: nil
    )
}
