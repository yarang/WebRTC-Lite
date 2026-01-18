package com.webrtclite.core.domain.usecase

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.repository.SignalingRepository
import com.webrtclite.core.data.service.TurnCredentialService
import com.webrtclite.core.webrtc.PeerConnectionManager
import org.webrtc.SessionDescription
import javax.inject.Inject

/**
 * Use case for answering incoming WebRTC call
 * Orchestrates peer connection setup, remote description, and answer creation
 */
class AnswerCallUseCase @Inject constructor(
    private val signalingRepository: SignalingRepository,
    private val turnCredentialService: TurnCredentialService,
    private val peerConnectionManager: PeerConnectionManager
) {
    /**
     * Execute answer call flow
     * @param offer Incoming offer message from caller
     * @param calleeId Callee user ID
     * @param startMedia Whether to start local media capture (default: true)
     * @return Result indicating success or failure
     */
    suspend operator fun invoke(
        offer: SignalingMessage.Offer,
        calleeId: String,
        startMedia: Boolean = true
    ): Result<Unit> = runCatching {
        // Step 1: Get TURN credentials
        val turnCredential = turnCredentialService.getCredentials(offer.sessionId)
            .getOrThrow()

        // Step 2: Initialize peer connection
        peerConnectionManager.initialize(
            sessionId = offer.sessionId,
            stunTurnUrls = turnCredential.urls,
            username = turnCredential.username,
            password = turnCredential.password
        ).getOrThrow()

        // Step 3: Start local media if requested
        if (startMedia) {
            peerConnectionManager.startLocalCapture().getOrThrow()
        }

        // Step 4: Set remote description from offer
        val remoteDescription = SessionDescription(
            SessionDescription.Type.OFFER,
            offer.sdp
        )
        peerConnectionManager.setRemoteDescription(remoteDescription).getOrThrow()

        // Step 5: Create SDP answer
        val answer = peerConnectionManager.createAnswer().getOrThrow()

        // Step 6: Set local description
        peerConnectionManager.setLocalDescription(answer).getOrThrow()

        // Step 7: Send answer via signaling channel
        val answerMessage = SignalingMessage.Answer(
            sessionId = offer.sessionId,
            sdp = answer.description,
            calleeId = calleeId
        )

        signalingRepository.sendAnswer(offer.sessionId, answerMessage).getOrThrow()
    }
}
