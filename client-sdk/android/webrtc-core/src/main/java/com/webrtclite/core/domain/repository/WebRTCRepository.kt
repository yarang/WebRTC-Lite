package com.webrtclite.core.domain.repository

import kotlinx.coroutines.flow.Flow
import org.webrtc.SessionDescription
import org.webrtc.IceCandidate
import org.webrtc.MediaStream

/**
 * Repository interface for WebRTC peer connection management
 */
interface WebRTCRepository {
    /**
     * Initialize peer connection with STUN/TURN configuration
     */
    suspend fun initializePeerConnection(
        sessionId: String,
        stunTurnUrls: List<String>,
        username: String,
        password: String
    ): Result<Unit>

    /**
     * Create SDP offer for outgoing call
     */
    suspend fun createOffer(): Result<SessionDescription>

    /**
     * Create SDP answer for incoming call
     */
    suspend fun createAnswer(): Result<SessionDescription>

    /**
     * Set remote SDP description
     */
    suspend fun setRemoteDescription(description: SessionDescription): Result<Unit>

    /**
     * Set local SDP description
     */
    suspend fun setLocalDescription(description: SessionDescription): Result<Unit>

    /**
     * Add ICE candidate to peer connection
     */
    suspend fun addIceCandidate(candidate: IceCandidate): Result<Unit>

    /**
     * Observe ICE candidate generation
     */
    fun observeIceCandidates(): Flow<IceCandidate>

    /**
     * Observe remote media stream
     */
    fun observeRemoteMediaStream(): Flow<MediaStream>

    /**
     * Start local media capture (camera, microphone)
     */
    suspend fun startLocalCapture(): Result<Unit>

    /**
     * Stop local media capture
     */
    suspend fun stopLocalCapture(): Result<Unit>

    /**
     * Toggle camera on/off
     */
    suspend fun toggleCamera(enabled: Boolean): Result<Unit>

    /**
     * Toggle microphone on/off
     */
    suspend fun toggleMicrophone(enabled: Boolean): Result<Unit>

    /**
     * Switch camera (front/back)
     */
    suspend fun switchCamera(): Result<Unit>

    /**
     * Close peer connection and clean up resources
     */
    suspend fun closePeerConnection(): Result<Unit>

    /**
     * Get current peer connection state
     */
    fun getConnectionState(): String
}
