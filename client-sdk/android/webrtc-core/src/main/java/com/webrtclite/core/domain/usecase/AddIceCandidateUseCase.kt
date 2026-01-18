package com.webrtclite.core.domain.usecase

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.repository.SignalingRepository
import com.webrtclite.core.webrtc.PeerConnectionManager
import org.webrtc.IceCandidate
import java.util.UUID
import javax.inject.Inject

/**
 * Use case for handling ICE candidates
 * Manages adding remote candidates and signaling local candidates
 */
class AddIceCandidateUseCase @Inject constructor(
    private val signalingRepository: SignalingRepository,
    private val peerConnectionManager: PeerConnectionManager
) {
    /**
     * Add remote ICE candidate to peer connection
     * @param candidate ICE candidate message from signaling
     * @return Result indicating success or failure
     */
    suspend operator fun invoke(candidate: SignalingMessage.IceCandidate): Result<Unit> = runCatching {
        // Convert signaling message to WebRTC ICE candidate
        val webrtcCandidate = IceCandidate(
            candidate.sdpMid,
            candidate.sdpMLineIndex,
            candidate.sdpCandidate
        )

        // Add to peer connection
        peerConnectionManager.addIceCandidate(webrtcCandidate).getOrThrow()
    }

    /**
     * Signal local ICE candidate to remote peer
     * @param sessionId Session identifier
     * @param candidateId Unique candidate ID
     * @param webrtcCandidate Local WebRTC ICE candidate
     * @return Result indicating success or failure
     */
    suspend fun signalLocalCandidate(
        sessionId: String,
        candidateId: String = UUID.randomUUID().toString(),
        webrtcCandidate: IceCandidate
    ): Result<Unit> = runCatching {
        // Convert to signaling message
        val candidateMessage = SignalingMessage.IceCandidate(
            sessionId = sessionId,
            sdpMid = webrtcCandidate.sdpMid,
            sdpMLineIndex = webrtcCandidate.sdpMLineIndex,
            sdpCandidate = webrtcCandidate.sdp
        )

        // Send via signaling channel
        signalingRepository.sendIceCandidate(sessionId, candidateId, candidateMessage)
            .getOrThrow()
    }

    /**
     * Start observing local ICE candidates and automatically signal them
     * This should be called after peer connection is initialized
     */
    suspend fun startLocalCandidateSignaling(sessionId: String) {
        // In actual implementation, observe PeerConnectionManager's ICE candidate flow
        // and automatically call signalLocalCandidate for each emitted candidate
        // This is typically done in the ViewModel or a dedicated coroutine
    }
}
