// MARK: - PeerConnectionManager
// TRUST 5 Compliance: Testable, Unified, Trackable

import Foundation
import WebRTC
import Combine
import AVFoundation

// MARK: - Peer Connection Manager

/// Manager for WebRTC PeerConnection lifecycle
/// Handles peer connection creation, media capture, and ICE negotiation
final class PeerConnectionManager: NSObject {

    // MARK: - Properties

    private(set) var connectionState: RTCIceConnectionState = .new
    private(set) var signalingState: RTCSignalingState = .stable

    private var peerConnectionFactory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var videoCapturer: RTCVideoCapturer?
    private var localAudioTrack: RTCAudioTrack?
    private var localVideoTrack: RTCVideoTrack?
    private var remoteVideoTrack: RTCVideoTrack?

    // ICE Candidate Publisher
    private let iceCandidateSubject = PassthroughSubject<RTCIceCandidate, Never>()
    var iceCandidatePublisher: AnyPublisher<RTCIceCandidate, Never> {
        iceCandidateSubject.eraseToAnyPublisher()
    }

    // Remote Stream Publisher
    private let remoteStreamSubject = PassthroughSubject<RTCMediaStream, Never>()
    var remoteStreamPublisher: AnyPublisher<RTCMediaStream, Never> {
        remoteStreamSubject.eraseToAnyPublisher()
    }

    // Connection State Publisher
    private let connectionStateSubject = PassthroughSubject<RTCIceConnectionState, Never>()
    var connectionStatePublisher: AnyPublisher<RTCIceConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }

    // Control flags
    private var isCameraEnabled = true
    private var isMicrophoneEnabled = true

    // MARK: - Constants

    private enum Constants {
        static let audioTrackId = "audio_track"
        static let videoTrackId = "video_track"
        static let streamId = "webrtc_stream"
    }

    // MARK: - Initialization

    override init() {
        super.init()
        initializePeerConnectionFactory()
    }

    deinit {
        cleanup()
    }

    // MARK: - Public Methods

    /// Initialize peer connection with STUN/TURN configuration
    func initialize(
        stunTurnUrls: [String],
        username: String,
        password: String
    ) async throws {
        // Create ICE servers
        let iceServers = stunTurnUrls.map { url -> RTCIceServer in
            RTCIceServer(url: url, username: username, credential: password)
        }

        // Create configuration
        let config = RTCConfiguration()
        config.iceServers = iceServers
        config.sdpSemantics = .unifiedPlan
        config.iceCandidatePoolSize = 10
        config.tcpCandidatePolicy = .enabled
        config.continualGatheringPolicy = .gatherContinually

        // Create constraints
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )

        // Create peer connection
        peerConnection = peerConnectionFactory?.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        )

        guard peerConnection != nil else {
            throw PeerConnectionError.initializationFailed
        }
    }

    /// Create SDP offer
    func createOffer() async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnection else {
            throw PeerConnectionError.notInitialized
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                RTCPair(key: "OfferToReceiveAudio", value: "true"),
                RTCPair(key: "OfferToReceiveVideo", value: "true")
            ],
            optionalConstraints: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.offer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: PeerConnectionError.offerCreationFailed)
                }
            }
        }
    }

    /// Create SDP answer
    func createAnswer() async throws -> RTCSessionDescription {
        guard let peerConnection = peerConnection else {
            throw PeerConnectionError.notInitialized
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                RTCPair(key: "OfferToReceiveAudio", value: "true"),
                RTCPair(key: "OfferToReceiveVideo", value: "true")
            ],
            optionalConstraints: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: PeerConnectionError.answerCreationFailed)
                }
            }
        }
    }

    /// Set remote description
    func setRemoteDescription(_ description: RTCSessionDescription) async throws {
        guard let peerConnection = peerConnection else {
            throw PeerConnectionError.notInitialized
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Set local description
    func setLocalDescription(_ description: RTCSessionDescription) async throws {
        guard let peerConnection = peerConnection else {
            throw PeerConnectionError.notInitialized
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Add ICE candidate
    func addIceCandidate(_ candidate: RTCIceCandidate) async throws {
        guard let peerConnection = peerConnection else {
            throw PeerConnectionError.notInitialized
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.add(candidate) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Start local media capture
    func startLocalCapture() async throws {
        guard let factory = peerConnectionFactory else {
            throw PeerConnectionError.factoryNotInitialized
        }

        // Request permissions
        try await requestMediaPermissions()

        // Create audio track
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        let audioSource = factory.audioSource(with: audioConstraints)
        localAudioTrack = factory.audioTrack(with: audioSource, trackId: Constants.audioTrackId)

        // Create video track
        let videoSource = factory.videoSource()
        videoCapturer = RTCVideoCapturer(delegate: videoSource)

        // Use camera
        if let camera = try getCamera() {
            videoCapturer?.startCapture(
                with: camera,
                format: try getVideoFormat(),
                fps: 30
            )
        }

        localVideoTrack = factory.videoTrack(with: videoSource, trackId: Constants.videoTrackId)

        // Add tracks to peer connection
        if let peerConnection = peerConnection {
            if let audioTrack = localAudioTrack {
                peerConnection.add(audioTrack, streamIds: [Constants.streamId])
            }
            if let videoTrack = localVideoTrack {
                peerConnection.add(videoTrack, streamIds: [Constants.streamId])
            }
        }
    }

    /// Stop local media capture
    func stopLocalCapture() async throws {
        videoCapturer?.stopCapture()
        videoCapturer = nil

        localAudioTrack = nil
        localVideoTrack = nil
    }

    /// Toggle camera
    func toggleCamera(_ enabled: Bool) {
        isCameraEnabled = enabled
        localVideoTrack?.isEnabled = enabled
    }

    /// Toggle microphone
    func toggleMicrophone(_ enabled: Bool) {
        isMicrophoneEnabled = enabled
        localAudioTrack?.isEnabled = enabled
    }

    /// Switch camera
    func switchCamera() async throws {
        // Implementation depends on video capturer type
        // For RTCVideoCapturer, camera switching requires re-initialization
        // This is a simplified version
        throw PeerConnectionError.operationNotSupported
    }

    /// Get local video track
    func getLocalVideoTrack() -> RTCVideoTrack? {
        return localVideoTrack
    }

    /// Get remote video track
    func getRemoteVideoTrack() -> RTCVideoTrack? {
        return remoteVideoTrack
    }

    /// Close peer connection and cleanup
    func close() async throws {
        try? await stopLocalCapture()

        peerConnection?.close()
        peerConnection = nil

        connectionState = .new
        signalingState = .stable
    }

    // MARK: - Private Methods

    private func initializePeerConnectionFactory() {
        RTCInitializeSSL()
        peerConnectionFactory = RTCPeerConnectionFactory()
    }

    private func requestMediaPermissions() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else {
                throw PeerConnectionError.permissionDenied
            }

            let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
            guard audioGranted else {
                throw PeerConnectionError.permissionDenied
            }
        case .denied, .restricted:
            throw PeerConnectionError.permissionDenied
        @unknown default:
            throw PeerConnectionError.permissionDenied
        }
    }

    private func getCamera() throws -> AVCaptureDevice {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInTelephotoCamera],
            mediaType: .video,
            position: .front
        )

        guard let camera = discoverySession.devices.first else {
            throw PeerConnectionError.cameraNotFound
        }

        return camera
    }

    private func getVideoFormat() throws -> CMFormatDescription {
        guard let formatDescription = CMVideoFormatDescription.create(
            formatType: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            width: 1280,
            height: 720
        ) else {
            throw PeerConnectionError.invalidVideoFormat
        }

        return formatDescription
    }

    private func cleanup() {
        RTCDeinitializeSSL()
    }
}

// MARK: - RTCPeerConnectionDelegate

extension PeerConnectionManager: RTCPeerConnectionDelegate {

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        signalingState = state
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        remoteStreamSubject.send(stream)

        // Extract remote video track
        if let videoTracks = stream.videoTracks as? [RTCVideoTrack], let videoTrack = videoTracks.first {
            remoteVideoTrack = videoTrack
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // Handle stream removal
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // Handle renegotiation
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceConnectionState) {
        connectionState = state
        connectionStateSubject.send(state)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCIceGatheringState) {
        // Handle ICE gathering state change
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        iceCandidateSubject.send(candidate)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Handle candidate removal
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // Handle data channel
    }
}

// MARK: - Errors

enum PeerConnectionError: LocalizedError {
    case notInitialized
    case factoryNotInitialized
    case initializationFailed
    case offerCreationFailed
    case answerCreationFailed
    case permissionDenied
    case cameraNotFound
    case invalidVideoFormat
    case operationNotSupported

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Peer connection not initialized"
        case .factoryNotInitialized:
            return "Peer connection factory not initialized"
        case .initializationFailed:
            return "Failed to initialize peer connection"
        case .offerCreationFailed:
            return "Failed to create offer"
        case .answerCreationFailed:
            return "Failed to create answer"
        case .permissionDenied:
            return "Camera or microphone permission denied"
        case .cameraNotFound:
            return "Camera not found"
        case .invalidVideoFormat:
            return "Invalid video format"
        case .operationNotSupported:
            return "Operation not supported"
        }
    }
}
