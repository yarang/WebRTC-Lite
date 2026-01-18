package com.webrtclite.core.data.model

/**
 * Sealed class representing WebRTC signaling messages
 * Used for Firestore-based signaling exchange
 */
sealed class SignalingMessage {
    abstract val type: String
    abstract val sessionId: String

    /**
     * SDP Offer message from caller
     */
    data class Offer(
        override val sessionId: String,
        val sdp: String,
        val callerId: String,
        val timestamp: Long = System.currentTimeMillis()
    ) : SignalingMessage() {
        override val type: String = "offer"
    }

    /**
     * SDP Answer message from callee
     */
    data class Answer(
        override val sessionId: String,
        val sdp: String,
        val calleeId: String,
        val timestamp: Long = System.currentTimeMillis()
    ) : SignalingMessage() {
        override val type: String = "answer"
    }

    /**
     * ICE Candidate message for establishing connection
     */
    data class IceCandidate(
        override val sessionId: String,
        val sdpMid: String,
        val sdpMLineIndex: Int,
        val sdpCandidate: String,
        val timestamp: Long = System.currentTimeMillis()
    ) : SignalingMessage() {
        override val type: String = "ice-candidate"
    }

    /**
     * TURN server credentials for NAT traversal
     */
    data class TurnCredential(
        override val sessionId: String,
        val username: String,
        val password: String,
        val ttl: Int,
        val urls: List<String>,
        val timestamp: Long = System.currentTimeMillis()
    ) : SignalingMessage() {
        override val type: String = "turn-credential"
    }

    /**
     * Hangup message to end call
     */
    data class Hangup(
        override val sessionId: String,
        val userId: String,
        val reason: String? = null,
        val timestamp: Long = System.currentTimeMillis()
    ) : SignalingMessage() {
        override val type: String = "hangup"
    }
}
