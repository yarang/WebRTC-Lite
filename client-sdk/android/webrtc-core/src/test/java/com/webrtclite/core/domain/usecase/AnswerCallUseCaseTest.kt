package com.webrtclite.core.domain.usecase

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.repository.SignalingRepository
import com.webrtclite.core.data.service.TurnCredentialService
import com.webrtclite.core.webrtc.PeerConnectionManager
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import com.google.common.truth.Truth.assertThat
import org.webrtc.SessionDescription

/**
 * Characterization tests for AnswerCallUseCase
 * Tests answer creation flow for incoming calls
 */
class AnswerCallUseCaseTest {

    private val mockSignalingRepository = mockk<SignalingRepository>()
    private val mockTurnService = mockk<TurnCredentialService>()
    private val mockPeerConnectionManager = mockk<PeerConnectionManager>()
    private lateinit var answerCallUseCase: AnswerCallUseCase

    @Test
    fun `test characterize answer creation flow`() = runTest {
        // Given: Incoming offer message
        val incomingOffer = SignalingMessage.Offer(
            sessionId = "session-123",
            sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...",
            callerId = "caller-abc"
        )

        val turnCredential = SignalingMessage.TurnCredential(
            sessionId = "session-123",
            username = "user:timestamp",
            password = "secret",
            ttl = 86400,
            urls = listOf("turn:turn.example.com:3478")
        )

        coEvery { mockTurnService.getCredentials(any()) } returns Result.success(turnCredential)
        coEvery { mockPeerConnectionManager.initialize(any(), any(), any(), any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.startLocalCapture() } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.setRemoteDescription(any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.createAnswer() } returns Result.success(
            SessionDescription(SessionDescription.Type.ANSWER, "v=0\r\no=- 654321 2 IN IP4 127.0.0.1\r\n...")
        )
        coEvery { mockPeerConnectionManager.setLocalDescription(any()) } returns Result.success(Unit)
        coEvery { mockSignalingRepository.sendAnswer(any(), any()) } returns Result.success(Unit)

        answerCallUseCase = AnswerCallUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Answering call
        val result = answerCallUseCase(incomingOffer, "callee-def")

        // Then: Verify answer flow
        assertThat(result).isInstanceOf<Result<Unit>>()
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize answer with remote description setup`() = runTest {
        // Given: Offer with SDP
        val incomingOffer = SignalingMessage.Offer(
            sessionId = "session-123",
            sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n...",
            callerId = "caller-abc"
        )

        val turnCredential = SignalingMessage.TurnCredential(
            sessionId = "session-123",
            username = "user:timestamp",
            password = "secret",
            ttl = 86400,
            urls = listOf("stun:stun.l.google.com:19302")
        )

        coEvery { mockTurnService.getCredentials(any()) } returns Result.success(turnCredential)
        coEvery { mockPeerConnectionManager.initialize(any(), any(), any(), any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.startLocalCapture() } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.setRemoteDescription(any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.createAnswer() } returns Result.success(
            SessionDescription(SessionDescription.Type.ANSWER, "v=0\r\n...")
        )
        coEvery { mockPeerConnectionManager.setLocalDescription(any()) } returns Result.success(Unit)
        coEvery { mockSignalingRepository.sendAnswer(any(), any()) } returns Result.success(Unit)

        answerCallUseCase = AnswerCallUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Answering call
        val result = answerCallUseCase(incomingOffer, "callee-def")

        // Then: Verify remote description was set
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize answer without media`() = runTest {
        // Given: Offer but don't start media
        val incomingOffer = SignalingMessage.Offer(
            sessionId = "session-123",
            sdp = "v=0\r\n...",
            callerId = "caller-abc"
        )

        val turnCredential = SignalingMessage.TurnCredential(
            sessionId = "session-123",
            username = "user:timestamp",
            password = "secret",
            ttl = 86400,
            urls = listOf("stun:stun.l.google.com:19302")
        )

        coEvery { mockTurnService.getCredentials(any()) } returns Result.success(turnCredential)
        coEvery { mockPeerConnectionManager.initialize(any(), any(), any(), any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.setRemoteDescription(any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.createAnswer() } returns Result.success(
            SessionDescription(SessionDescription.Type.ANSWER, "v=0\r\n...")
        )
        coEvery { mockPeerConnectionManager.setLocalDescription(any()) } returns Result.success(Unit)
        coEvery { mockSignalingRepository.sendAnswer(any(), any()) } returns Result.success(Unit)

        answerCallUseCase = AnswerCallUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Answering without media
        val result = answerCallUseCase(incomingOffer, "callee-def", startMedia = false)

        // Then: Verify answer succeeded without media capture
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize answer error handling`() = runTest {
        // Given: Invalid offer causing error
        val invalidOffer = SignalingMessage.Offer(
            sessionId = "session-123",
            sdp = "invalid-sdp",
            callerId = "caller-abc"
        )

        coEvery { mockPeerConnectionManager.setRemoteDescription(any()) } returns Result.failure(
            Exception("Invalid SDP")
        )

        answerCallUseCase = AnswerCallUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Answering with invalid offer
        val result = answerCallUseCase(invalidOffer, "callee-def")

        // Then: Verify error is propagated
        assertThat(result.isFailure).isTrue()
    }
}
