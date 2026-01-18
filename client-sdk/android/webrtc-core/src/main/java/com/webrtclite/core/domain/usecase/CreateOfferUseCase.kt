package com.webrtclite.core.domain.usecase

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.repository.SignalingRepository
import com.webrtclite.core.data.service.TurnCredentialService
import com.webrtclite.core.webrtc.PeerConnectionManager
import org.webrtc.SessionDescription
import javax.inject.Inject

/**
 * Use case for creating and sending WebRTC offer
 * Orchestrates peer connection initialization, offer creation, and signaling
 */
class CreateOfferUseCase @Inject constructor(
    private val signalingRepository: SignalingRepository,
    private val turnCredentialService: TurnCredentialService,
    private val peerConnectionManager: PeerConnectionManager
) {
    /**
     * Execute offer creation flow
     * @param sessionId Unique session identifier
     * @param callerId Caller user ID
     * @param startMedia Whether to start local media capture (default: true)
     * @return Result indicating success or failure
     */
    suspend operator fun invoke(
        sessionId: String,
        callerId: String,
        startMedia: Boolean = true
    ): Result<Unit> = runCatching {
        // Step 1: Get TURN credentials for NAT traversal
        val turnCredential = turnCredentialService.getCredentials(sessionId)
            .getOrThrow()

        // Step 2: Initialize peer connection with STUN/TURN servers
        peerConnectionManager.initialize(
            sessionId = sessionId,
            stunTurnUrls = turnCredential.urls,
            username = turnCredential.username,
            password = turnCredential.password
        ).getOrThrow()

        // Step 3: Start local media capture if requested
        if (startMedia) {
            peerConnectionManager.startLocalCapture().getOrThrow()
        }

        // Step 4: Create SDP offer
        val offer = peerConnectionManager.createOffer().getOrThrow()

        // Step 5: Set local description
        peerConnectionManager.setLocalDescription(offer).getOrThrow()

        // Step 6: Send offer via signaling channel
        val offerMessage = SignalingMessage.Offer(
            sessionId = sessionId,
            sdp = offer.description,
            callerId = callerId
        )

        signalingRepository.sendOffer(sessionId, offerMessage).getOrThrow()
    }
}
