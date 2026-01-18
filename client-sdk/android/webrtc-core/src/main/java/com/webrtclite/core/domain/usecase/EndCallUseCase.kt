package com.webrtclite.core.domain.usecase

import com.webrtclite.core.data.repository.SignalingRepository
import com.webrtclite.core.webrtc.PeerConnectionManager
import javax.inject.Inject

/**
 * Use case for ending WebRTC call
 * Handles cleanup of peer connection and signaling resources
 */
class EndCallUseCase @Inject constructor(
    private val signalingRepository: SignalingRepository,
    private val peerConnectionManager: PeerConnectionManager
) {
    /**
     * Execute end call flow
     * @param sessionId Session identifier to terminate
     * @param graceful Whether to perform graceful shutdown (default: true)
     * @return Result indicating success or failure
     */
    suspend operator fun invoke(
        sessionId: String,
        graceful: Boolean = true
    ): Result<Unit> = runCatching {
        if (graceful) {
            // Step 1: Stop media capture
            peerConnectionManager.stopLocalCapture().getOrThrow()
        }

        // Step 2: Close peer connection
        peerConnectionManager.close().getOrThrow()

        // Step 3: Clean up signaling session
        signalingRepository.deleteSession(sessionId).getOrThrow()
    }
}
