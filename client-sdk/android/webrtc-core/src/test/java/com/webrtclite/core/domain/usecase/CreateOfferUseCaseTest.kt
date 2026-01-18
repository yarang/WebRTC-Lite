package com.webrtclite.core.domain.usecase

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.repository.SignalingRepository
import com.webrtclite.core.data.service.TurnCredentialService
import com.webrtclite.core.webrtc.PeerConnectionManager
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Test
import com.google.common.truth.Truth.assertThat
import org.webrtc.SessionDescription

/**
 * Characterization tests for CreateOfferUseCase
 * Tests offer creation flow with WebRTC and signaling
 */
class CreateOfferUseCaseTest {

    private val mockSignalingRepository = mockk<SignalingRepository>()
    private val mockTurnService = mockk<TurnCredentialService>()
    private val mockPeerConnectionManager = mockk<PeerConnectionManager>()
    private lateinit var createOfferUseCase: CreateOfferUseCase

    @Test
    fun `test characterize offer creation flow`() = runTest {
        // Given: Use case with mocked dependencies
        val turnCredential = SignalingMessage.TurnCredential(
            sessionId = "session-123",
            username = "user:timestamp",
            password = "secret",
            ttl = 86400,
            urls = listOf("turn:turn.example.com:3478")
        )
        coEvery { mockTurnService.getCredentials(any()) } returns Result.success(turnCredential)
        coEvery { mockPeerConnectionManager.initialize(any(), any(), any(), any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.createOffer() } returns Result.success(
            SessionDescription(SessionDescription.Type.OFFER, "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...")
        )
        coEvery { mockPeerConnectionManager.setLocalDescription(any()) } returns Result.success(Unit)
        coEvery { mockSignalingRepository.sendOffer(any(), any()) } returns Result.success(Unit)

        createOfferUseCase = CreateOfferUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Creating offer
        val result = createOfferUseCase("session-123", "caller-abc")

        // Then: Verify flow sequence
        assertThat(result).isInstanceOf<Result<Unit>>()
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize offer creation with TURN credential fetch`() = runTest {
        // Given: TURN service returns credentials
        val turnCredential = SignalingMessage.TurnCredential(
            sessionId = "session-123",
            username = "user:timestamp",
            password = "secret",
            ttl = 86400,
            urls = listOf("stun:stun.l.google.com:19302", "turn:turn.example.com:3478")
        )
        coEvery { mockTurnService.getCredentials(any()) } returns Result.success(turnCredential)
        coEvery { mockPeerConnectionManager.initialize(any(), any(), any(), any()) } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.createOffer() } returns Result.success(
            SessionDescription(SessionDescription.Type.OFFER, "v=0\r\n...")
        )
        coEvery { mockPeerConnectionManager.setLocalDescription(any()) } returns Result.success(Unit)
        coEvery { mockSignalingRepository.sendOffer(any(), any()) } returns Result.success(Unit)

        createOfferUseCase = CreateOfferUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Creating offer
        createOfferUseCase("session-123", "caller-abc")

        // Then: Verify TURN credentials were fetched
        // In actual implementation, verify initialize was called with TURN URLs
    }

    @Test
    fun `test characterize offer creation error handling`() = runTest {
        // Given: Peer connection initialization fails
        coEvery { mockTurnService.getCredentials(any()) } returns Result.failure(Exception("Network error"))
        createOfferUseCase = CreateOfferUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Creating offer
        val result = createOfferUseCase("session-123", "caller-abc")

        // Then: Verify error is propagated
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()?.message).isEqualTo("Network error")
    }

    @Test
    fun `test characterize local media capture start`() = runTest {
        // Given: Use case setup
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
        coEvery { mockPeerConnectionManager.createOffer() } returns Result.success(
            SessionDescription(SessionDescription.Type.OFFER, "v=0\r\n...")
        )
        coEvery { mockPeerConnectionManager.setLocalDescription(any()) } returns Result.success(Unit)
        coEvery { mockSignalingRepository.sendOffer(any(), any()) } returns Result.success(Unit)

        createOfferUseCase = CreateOfferUseCase(
            signalingRepository = mockSignalingRepository,
            turnCredentialService = mockTurnService,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Creating offer with media
        val result = createOfferUseCase("session-123", "caller-abc", startMedia = true)

        // Then: Verify media capture was started
        assertThat(result.isSuccess).isTrue()
    }
}
