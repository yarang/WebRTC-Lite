package com.webrtclite.core.presentation.model

/**
 * Sealed class representing WebRTC call states
 */
sealed class CallState {
    /**
     * Initial state before call starts
     */
    object Idle : CallState()

    /**
     * Connecting to signaling server
     */
    object Connecting : CallState()

    /**
     * Waiting for remote peer to answer
     */
    data class WaitingForAnswer(val sessionId: String) : CallState()

    /**
     * Call is active and connected
     */
    data class Connected(
        val sessionId: String,
        val isRemoteVideoEnabled: Boolean = true,
        val isRemoteAudioEnabled: Boolean = true
    ) : CallState()

    /**
     * Call is being ended
     */
    object Ending : CallState()

    /**
     * Call has ended
     */
    data class Ended(val reason: String? = null) : CallState()

    /**
     * Error state
     */
    data class Error(val message: String, val throwable: Throwable? = null) : CallState()
}

/**
 * UI state for call controls
 */
data class CallControlsState(
    val isCameraEnabled: Boolean = true,
    val isMicrophoneEnabled: Boolean = true,
    val isSpeakerEnabled: Boolean = false,
    val isLocalVideoVisible: Boolean = true,
    val isRemoteVideoVisible: Boolean = false,
    val connectionDuration: Long = 0L,
    val localIceCandidates: Int = 0,
    val remoteIceCandidates: Int = 0
)
