package com.webrtclite.core.data.repository

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.source.FirestoreDataSource
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * Characterization tests for SignalingRepository
 * Tests repository abstraction and Flow APIs
 */
class SignalingRepositoryTest {

    private val mockDataSource = mockk<FirestoreDataSource>()
    private lateinit var repository: SignalingRepositoryImpl

    @Test
    fun `test characterize offer sending flow`() = runTest {
        // Given: Repository with mocked data source
        coEvery { mockDataSource.sendOffer(any(), any()) } returns Unit
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Sending offer
        val offer = SignalingMessage.Offer(
            sessionId = "session-123",
            sdp = "v=0\r\no=- 123456 2 IN IP4 127.0.0.1\r\n...",
            callerId = "user-abc"
        )

        val result = repository.sendOffer("session-123", offer)

        // Then: Verify result type
        assertThat(result).isInstanceOf<Result<Unit>>()
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize answer sending flow`() = runTest {
        // Given: Repository setup
        coEvery { mockDataSource.sendAnswer(any(), any()) } returns Unit
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Sending answer
        val answer = SignalingMessage.Answer(
            sessionId = "session-123",
            sdp = "v=0\r\no=- 654321 2 IN IP4 127.0.0.1\r\n...",
            calleeId = "user-def"
        )

        val result = repository.sendAnswer("session-123", answer)

        // Then: Verify result
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize ICE candidate sending flow`() = runTest {
        // Given: Repository setup
        coEvery { mockDataSource.sendIceCandidate(any(), any(), any()) } returns Unit
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Sending ICE candidate
        val candidate = SignalingMessage.IceCandidate(
            sessionId = "session-123",
            sdpMid = "audio",
            sdpMLineIndex = 0,
            sdpCandidate = "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host"
        )

        val result = repository.sendIceCandidate("session-123", "candidate-1", candidate)

        // Then: Verify result
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize offer observation flow`() = runTest {
        // Given: Repository with Flow setup
        val expectedOffer = SignalingMessage.Offer(
            sessionId = "session-123",
            sdp = "v=0\r\n...",
            callerId = "user-abc"
        )
        coEvery { mockDataSource.observeOffer(any()) } returns flowOf(expectedOffer)
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Observing offers
        val offers = repository.observeOffer("session-123").toList()

        // Then: Verify emissions
        assertThat(offers).isNotEmpty()
        assertThat(offers.first()).isEqualTo(expectedOffer)
    }

    @Test
    fun `test characterize answer observation flow`() = runTest {
        // Given: Repository setup
        val expectedAnswer = SignalingMessage.Answer(
            sessionId = "session-123",
            sdp = "v=0\r\n...",
            calleeId = "user-def"
        )
        coEvery { mockDataSource.observeAnswer(any()) } returns flowOf(expectedAnswer)
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Observing answers
        val answers = repository.observeAnswer("session-123").toList()

        // Then: Verify emissions
        assertThat(answers).isNotEmpty()
        assertThat(answers.first()).isEqualTo(expectedAnswer)
    }

    @Test
    fun `test characterize ICE candidate observation flow`() = runTest {
        // Given: Repository setup
        val expectedCandidate = SignalingMessage.IceCandidate(
            sessionId = "session-123",
            sdpMid = "audio",
            sdpMLineIndex = 0,
            sdpCandidate = "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host"
        )
        coEvery { mockDataSource.observeIceCandidates(any()) } returns flowOf(expectedCandidate)
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Observing candidates
        val candidates = repository.observeIceCandidates("session-123").toList()

        // Then: Verify emissions
        assertThat(candidates).isNotEmpty()
        assertThat(candidates.first()).isEqualTo(expectedCandidate)
    }

    @Test
    fun `test characterize session deletion`() = runTest {
        // Given: Repository setup
        coEvery { mockDataSource.deleteSession(any()) } returns Unit
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Deleting session
        val result = repository.deleteSession("session-123")

        // Then: Verify result
        assertThat(result.isSuccess).isTrue()
    }

    @Test
    fun `test characterize error handling`() = runTest {
        // Given: Repository with error simulation
        coEvery { mockDataSource.sendOffer(any(), any()) } throws Exception("Network error")
        repository = SignalingRepositoryImpl(mockDataSource)

        // When: Sending offer with error
        val offer = SignalingMessage.Offer(
            sessionId = "session-123",
            sdp = "v=0\r\n...",
            callerId = "user-abc"
        )

        val result = repository.sendOffer("session-123", offer)

        // Then: Verify error is wrapped in Result
        assertThat(result.isFailure).isTrue()
        assertThat(result.exceptionOrNull()).isInstanceOf(Exception::class.java)
    }
}
