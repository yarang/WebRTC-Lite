// MARK: - CallViewModel
// TRUST 5 Compliance: Testable, Unified, Trackable

import Foundation
import Combine
import SwiftUI
import WebRTC

// MARK: - Call ViewModel

/// ViewModel for managing WebRTC call state and UI interactions
@MainActor
final class CallViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var callState: CallState = .idle
    @Published var controlsState: CallControlsState = CallControlsState()
    @Published var permissionState: CallPermission = .notDetermined

    // MARK: - Dependencies

    private let createOfferUseCase: CreateOfferUseCase
    private let answerCallUseCase: AnswerCallUseCase
    private let addIceCandidateUseCase: AddIceCandidateUseCase
    private let endCallUseCase: EndCallUseCase
    private let peerConnectionManager: PeerConnectionManager

    // MARK: - Private Properties

    private var currentSessionId: String?
    private var callStartTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var connectionDurationTimer: Timer?

    // MARK: - Initialization

    init(
        createOfferUseCase: CreateOfferUseCase,
        answerCallUseCase: AnswerCallUseCase,
        addIceCandidateUseCase: AddIceCandidateUseCase,
        endCallUseCase: EndCallUseCase,
        peerConnectionManager: PeerConnectionManager
    ) {
        self.createOfferUseCase = createOfferUseCase
        self.answerCallUseCase = answerCallUseCase
        self.addIceCandidateUseCase = addIceCandidateUseCase
        self.endCallUseCase = endCallUseCase
        self.peerConnectionManager = peerConnectionManager

        setupBindings()
    }

    // MARK: - Public Methods

    /// Handle UI events
    func handleEvent(_ event: CallUiEvent) {
        switch event {
        case .startCall(let targetUserId):
            Task { await startCall(targetUserId: targetUserId) }
        case .answerCall(let offer):
            Task { await answerCall(offer: offer) }
        case .endCall:
            Task { await endCall() }
        case .toggleCamera(let enabled):
            Task { await toggleCamera(enabled: enabled) }
        case .toggleMicrophone(let enabled):
            Task { await toggleMicrophone(enabled: enabled) }
        case .switchCamera:
            Task { await switchCamera() }
        case .toggleSpeaker(let enabled):
            toggleSpeaker(enabled: enabled)
        case .dismissError:
            dismissError()
        }
    }

    /// Handle incoming ICE candidate
    func handleIceCandidate(_ candidate: SignalingMessage.IceCandidate) {
        Task {
            do {
                try await addIceCandidateUseCase.execute(candidate: candidate)
                controlsState.remoteIceCandidates += 1
            } catch {
                updateError("ICE candidate error: \(error.localizedDescription)")
            }
        }
    }

    /// Get local video track
    func getLocalVideoTrack() -> RTCVideoTrack? {
        return peerConnectionManager.getLocalVideoTrack()
    }

    /// Get remote video track
    func getRemoteVideoTrack() -> RTCVideoTrack? {
        return peerConnectionManager.getRemoteVideoTrack()
    }

    // MARK: - Private Methods - Call Flow

    private func startCall(targetUserId: String) async {
        callState = .connecting

        let sessionId = UUID().uuidString
        currentSessionId = sessionId
        callStartTime = Date()

        do {
            try await createOfferUseCase.execute(
                sessionId: sessionId,
                callerId: "current-user-id", // TODO: Get from Auth
                startMedia: true
            )

            callState = .waitingForAnswer(sessionId: sessionId)
            startIceCandidateObservation(sessionId: sessionId)
            startConnectionDurationTracking()
        } catch {
            updateError("Failed to start call: \(error.localizedDescription)")
        }
    }

    private func answerCall(offer: SignalingMessage.Offer) async {
        callState = .connecting

        currentSessionId = offer.sessionId
        callStartTime = Date()

        do {
            try await answerCallUseCase.execute(
                offer: offer,
                calleeId: "current-user-id", // TODO: Get from Auth
                startMedia: true
            )

            callState = .connected(sessionId: offer.sessionId)
            startIceCandidateObservation(sessionId: offer.sessionId)
            startConnectionDurationTracking()
        } catch {
            updateError("Failed to answer call: \(error.localizedDescription)")
        }
    }

    private func endCall() async {
        guard let sessionId = currentSessionId else {
            return
        }

        callState = .ending
        stopConnectionDurationTracking()

        do {
            try await endCallUseCase.execute(
                sessionId: sessionId,
                userId: "current-user-id", // TODO: Get from Auth
                reason: nil
            )

            callState = .ended(reason: nil)
            resetCallState()
        } catch {
            updateError("Failed to end call: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods - Media Controls

    private func toggleCamera(enabled: Bool) async {
        peerConnectionManager.toggleCamera(enabled)
        controlsState.isCameraEnabled = enabled
        controlsState.isLocalVideoVisible = enabled
    }

    private func toggleMicrophone(enabled: Bool) async {
        peerConnectionManager.toggleMicrophone(enabled)
        controlsState.isMicrophoneEnabled = enabled
    }

    private func switchCamera() async {
        do {
            try await peerConnectionManager.switchCamera()
        } catch {
            updateError("Failed to switch camera: \(error.localizedDescription)")
        }
    }

    private func toggleSpeaker(enabled: Bool) {
        controlsState.isSpeakerEnabled = enabled
        // TODO: Implement audio routing
    }

    private func dismissError() {
        if case .error = callState {
            callState = .idle
        }
    }

    // MARK: - Private Methods - Observation

    private func setupBindings() {
        // Observe ICE connection state
        peerConnectionManager.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleConnectionStateChange(state)
            }
            .store(in: &cancellables)

        // Observe remote media stream
        peerConnectionManager.remoteStreamPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stream in
                self?.handleRemoteStream(stream)
            }
            .store(in: &cancellables)
    }

    private func startIceCandidateObservation(sessionId: String) {
        peerConnectionManager.iceCandidatePublisher
            .sink { [weak self] candidate in
                Task { [weak self] in
                    guard let self = self else { return }
                    do {
                        try await self.addIceCandidateUseCase.signalLocalCandidate(
                            sessionId: sessionId,
                            candidateId: UUID().uuidString,
                            candidate: candidate
                        )
                        self.controlsState.localIceCandidates += 1
                    } catch {
                        // Log error but don't disrupt call
                        print("Failed to signal ICE candidate: \(error)")
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func startConnectionDurationTracking() {
        connectionDurationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self,
                  case .connected = self.callState,
                  let startTime = self.callStartTime else {
                return
            }

            self.controlsState.connectionDuration = Date().timeIntervalSince(startTime)
        }
    }

    private func stopConnectionDurationTracking() {
        connectionDurationTimer?.invalidate()
        connectionDurationTimer = nil
    }

    // MARK: - Private Methods - Handlers

    private func handleConnectionStateChange(_ state: RTCIceConnectionState) {
        switch state {
        case .connected:
            if let sessionId = currentSessionId {
                callState = .connected(sessionId: sessionId)
            }
        case .disconnected:
            callState = .ended(reason: "Connection lost")
        case .failed:
            updateError("Connection failed")
        default:
            break
        }
    }

    private func handleRemoteStream(_ stream: RTCMediaStream) {
        if let videoTracks = stream.videoTracks as? [RTCVideoTrack],
           !videoTracks.isEmpty {
            controlsState.isRemoteVideoVisible = true
        }
    }

    private func updateError(_ message: String) {
        callState = .error(message: message)
    }

    private func resetCallState() {
        currentSessionId = nil
        callStartTime = nil
        controlsState = CallControlsState()
        stopConnectionDurationTracking()
    }

    // MARK: - Cleanup

    deinit {
        cancellables.removeAll()
        stopConnectionDurationTracking()
    }
}

// MARK: - Factory Extension

extension CallViewModel {
    /// Create ViewModel with all dependencies
    static func create(
        signalingRepository: SignalingRepositoryProtocol = SignalingRepository(),
        turnCredentialService: TurnCredentialServiceProtocol = CachedTurnCredentialService(),
        peerConnectionManager: PeerConnectionManager = PeerConnectionManager()
    ) -> CallViewModel {
        let createOfferUseCase = CreateOfferUseCase(
            signalingRepository: signalingRepository,
            turnCredentialService: turnCredentialService,
            peerConnectionManager: peerConnectionManager
        )

        let answerCallUseCase = AnswerCallUseCase(
            signalingRepository: signalingRepository,
            turnCredentialService: turnCredentialService,
            peerConnectionManager: peerConnectionManager
        )

        let addIceCandidateUseCase = AddIceCandidateUseCase(
            signalingRepository: signalingRepository,
            peerConnectionManager: peerConnectionManager
        )

        let endCallUseCase = EndCallUseCase(
            signalingRepository: signalingRepository,
            peerConnectionManager: peerConnectionManager
        )

        return CallViewModel(
            createOfferUseCase: createOfferUseCase,
            answerCallUseCase: answerCallUseCase,
            addIceCandidateUseCase: addIceCandidateUseCase,
            endCallUseCase: endCallUseCase,
            peerConnectionManager: peerConnectionManager
        )
    }
}
