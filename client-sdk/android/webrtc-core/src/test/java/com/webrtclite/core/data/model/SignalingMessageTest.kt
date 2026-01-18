package com.webrtclite.core.data.model

import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * Characterization tests for SignalingMessage data model
 * Tests the structure and serialization of WebRTC signaling messages
 */
class SignalingMessageTest {

    @Test
    fun `test characterize OfferMessage structure`() {
        // Given: An offer message with required fields
        val offer = SignalingMessage.Offer(
            sessionId = "test-session-123",
            sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...",
            callerId = "user-abc"
        )

        // Then: Verify structure matches expected format
        assertThat(offer.sessionId).isEqualTo("test-session-123")
        assertThat(offer.sdp).startsWith("v=0")
        assertThat(offer.callerId).isEqualTo("user-abc")
        assertThat(offer.type).isEqualTo("offer")
    }

    @Test
    fun `test characterize AnswerMessage structure`() {
        // Given: An answer message
        val answer = SignalingMessage.Answer(
            sessionId = "test-session-123",
            sdp = "v=0\r\no=- 654321 2 IN IP4 127.0.0.1\r\n...",
            calleeId = "user-def"
        )

        // Then: Verify structure
        assertThat(answer.sessionId).isEqualTo("test-session-123")
        assertThat(answer.sdp).startsWith("v=0")
        assertThat(answer.calleeId).isEqualTo("user-def")
        assertThat(answer.type).isEqualTo("answer")
    }

    @Test
    fun `test characterize IceCandidateMessage structure`() {
        // Given: An ICE candidate message
        val candidate = SignalingMessage.IceCandidate(
            sessionId = "test-session-123",
            sdpMid = "audio",
            sdpMLineIndex = 0,
            sdpCandidate = "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host"
        )

        // Then: Verify structure
        assertThat(candidate.sessionId).isEqualTo("test-session-123")
        assertThat(candidate.sdpMid).isEqualTo("audio")
        assertThat(candidate.sdpMLineIndex).isEqualTo(0)
        assertThat(candidate.sdpCandidate).contains("candidate:")
        assertThat(candidate.type).isEqualTo("ice-candidate")
    }

    @Test
    fun `test characterize TurnCredentialMessage structure`() {
        // Given: TURN credential message
        val credential = SignalingMessage.TurnCredential(
            username = "user:timestamp",
            password = "base64encodedsecret",
            ttl = 86400,
            urls = listOf("turn:turn.example.com:3478?transport=udp")
        )

        // Then: Verify structure
        assertThat(credential.username).contains(":")
        assertThat(credential.password).isNotEmpty()
        assertThat(credential.ttl).isEqualTo(86400)
        assertThat(credential.urls).isNotEmpty()
        assertThat(credential.urls.first()).contains("turn:")
        assertThat(credential.type).isEqualTo("turn-credential")
    }
}
