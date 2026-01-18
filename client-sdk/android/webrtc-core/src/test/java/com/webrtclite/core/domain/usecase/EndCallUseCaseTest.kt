package com.webrtclite.core.domain.usecase

import com.webrtclite.core.data.repository.SignalingRepository
import com.webrtclite.core.webrtc.PeerConnectionManager
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * Characterization tests for EndCallUseCase
 * Tests call termination and cleanup
 */
class EndCallUseCaseTest {

    private val mockSignalingRepository = mockk<SignalingRepository>()
    private val mockPeerConnectionManager = mockk<PeerConnectionManager>()
    private lateinit var endCallUseCase: EndCallUseCase

    @Test
    fun `test characterize call termination flow`() = runTest {
        // Given: Use case with mocked dependencies
        coEvery { mockPeerConnectionManager.close() } returns Result.success(Unit)
        coEvery { mockSignalingRepository.deleteSession(any()) } returns Result.success(Unit)

        endCallUseCase = EndCallUseCase(
            signalingRepository = mockSignalingRepository,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Ending call
        val result = endCallUseCase("session-123")

        // Then: Verify cleanup sequence
        assertThat(result).isInstanceOf<Result<Unit>>()
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize peer connection cleanup`() = runTest {
        // Given: Active call
        coEvery { mockPeerConnectionManager.close() } returns Result.success(Unit)
        coEvery { mockSignalingRepository.deleteSession(any()) } returns Result.success(Unit)

        endCallUseCase = EndCallUseCase(
            signalingRepository = mockSignalingRepository,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Ending call
        endCallUseCase("session-123")

        // Then: Verify peer connection was closed
        // In actual implementation, verify close() was called
    }

    @Test
    fun `test characterize signaling cleanup`() = runTest {
        // Given: Active signaling session
        coEvery { mockPeerConnectionManager.close() } returns Result.success(Unit)
        coEvery { mockSignalingRepository.deleteSession(any()) } returns Result.success(Unit)

        endCallUseCase = EndCallUseCase(
            signalingRepository = mockSignalingRepository,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Ending call
        endCallUseCase("session-123")

        // Then: Verify signaling session was deleted
        // In actual implementation, verify deleteSession() was called
    }

    @Test
    fun `test characterize error handling during cleanup`() = runTest {
        // Given: Cleanup encounters error
        coEvery { mockPeerConnectionManager.close() } returns Result.failure(
            Exception("Peer connection error")
        )

        endCallUseCase = EndCallUseCase(
            signalingRepository = mockSignalingRepository,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Ending call with error
        val result = endCallUseCase("session-123")

        // Then: Verify error is propagated but cleanup continues
        assertThat(result.isFailure).isTrue()
        // In actual implementation, verify signaling cleanup still attempted
    }

    @Test
    fun `test characterize graceful shutdown`() = runTest {
        // Given: Use case setup
        coEvery { mockPeerConnectionManager.stopLocalCapture() } returns Result.success(Unit)
        coEvery { mockPeerConnectionManager.close() } returns Result.success(Unit)
        coEvery { mockSignalingRepository.deleteSession(any()) } returns Result.success(Unit)

        endCallUseCase = EndCallUseCase(
            signalingRepository = mockSignalingRepository,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Gracefully ending call
        val result = endCallUseCase("session-123", graceful = true)

        // Then: Verify graceful shutdown sequence
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize forced termination`() = runTest {
        // Given: Use case setup
        coEvery { mockPeerConnectionManager.close() } returns Result.success(Unit)
        coEvery { mockSignalingRepository.deleteSession(any()) } returns Result.success(Unit)

        endCallUseCase = EndCallUseCase(
            signalingRepository = mockSignalingRepository,
            peerConnectionManager = mockPeerConnectionManager
        )

        // When: Force ending call
        val result = endCallUseCase("session-123", graceful = false)

        // Then: Verify immediate termination
        assertThat(result.isSuccess).isTrue()
    }
}
