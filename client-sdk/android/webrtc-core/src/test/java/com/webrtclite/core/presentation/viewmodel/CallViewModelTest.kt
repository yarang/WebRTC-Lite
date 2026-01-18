package com.webrtclite.core.presentation.viewmodel

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.domain.usecase.AddIceCandidateUseCase
import com.webrtclite.core.domain.usecase.AnswerCallUseCase
import com.webrtclite.core.domain.usecase.CreateOfferUseCase
import com.webrtclite.core.domain.usecase.EndCallUseCase
import com.webrtclite.core.presentation.model.CallState
import com.webrtclite.core.presentation.model.CallUiEvent
import com.webrtclite.core.webrtc.PeerConnectionManager
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Before
import org.junit.Test
import com.google.common.truth.Truth.assertThat

/**
 * Characterization tests for CallViewModel
 * Tests state management and UI event handling
 */
@OptIn(ExperimentalCoroutinesApi::class)
class CallViewModelTest {

    private lateinit var viewModel: CallViewModel

    private val mockCreateOfferUseCase = mockk<CreateOfferUseCase>()
    private val mockAnswerCallUseCase = mockk<AnswerCallUseCase>()
    private val mockAddIceCandidateUseCase = mockk<AddIceCandidateUseCase>()
    private val mockEndCallUseCase = mockk<EndCallUseCase>()
    private val mockPeerConnectionManager = mockk<PeerConnectionManager>()

    private val testDispatcher = UnconfinedTestDispatcher()

    @Before
    fun setup() {
        Dispatchers.setMain(testDispatcher)
        viewModel = CallViewModel(
            createOfferUseCase = mockCreateOfferUseCase,
            answerCallUseCase = mockAnswerCallUseCase,
            addIceCandidateUseCase = mockAddIceCandidateUseCase,
            endCallUseCase = mockEndCallUseCase,
            peerConnectionManager = mockPeerConnectionManager
        )
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `test characterize initial state`() {
        // Then: Verify initial state
        assertThat(viewModel.callState.value).isEqualTo(CallState.Idle)
        assertThat(viewModel.controlsState.value.isCameraEnabled).isTrue()
        assertThat(viewModel.controlsState.value.isMicrophoneEnabled).isTrue()
    }

    @Test
    fun `test characterize start call event`() = runTest {
        // Given: Offer creation succeeds
        coEvery { mockCreateOfferUseCase(any(), any()) } returns Result.success(Unit)

        // When: Starting call
        viewModel.onEvent(CallUiEvent.StartCall("user-123"))

        // Then: Verify state transitions
        assertThat(viewModel.callState.value).isInstanceOf(CallState.WaitingForAnswer::class.java)
    }

    @Test
    fun `test characterize answer call event`() = runTest {
        // Given: Answer call succeeds
        val offer = SignalingMessage.Offer("session-123", "v=0\r\n...", "caller-abc")
        coEvery { mockAnswerCallUseCase(any(), any()) } returns Result.success(Unit)

        // When: Answering call
        viewModel.onEvent(CallUiEvent.AnswerCall(offer))

        // Then: Verify state transitions to connected
        assertThat(viewModel.callState.value).isInstanceOf(CallState.Connected::class.java)
    }

    @Test
    fun `test characterize end call event`() = runTest {
        // Given: Active call
        val offer = SignalingMessage.Offer("session-123", "v=0\r\n...", "caller-abc")
        coEvery { mockAnswerCallUseCase(any(), any()) } returns Result.success(Unit)
        coEvery { mockEndCallUseCase(any()) } returns Result.success(Unit)
        viewModel.onEvent(CallUiEvent.AnswerCall(offer))

        // When: Ending call
        viewModel.onEvent(CallUiEvent.EndCall)

        // Then: Verify state transitions
        assertThat(viewModel.callState.value).isInstanceOf(CallState.Ended::class.java)
    }

    @Test
    fun `test characterize toggle camera event`() = runTest {
        // Given: Active call
        coEvery { mockPeerConnectionManager.toggleCamera(any()) } returns Result.success(Unit)
        val offer = SignalingMessage.Offer("session-123", "v=0\r\n...", "caller-abc")
        coEvery { mockAnswerCallUseCase(any(), any()) } returns Result.success(Unit)
        viewModel.onEvent(CallUiEvent.AnswerCall(offer))

        // When: Toggling camera off
        viewModel.onEvent(CallUiEvent.ToggleCamera(false))

        // Then: Verify camera state updated
        assertThat(viewModel.controlsState.value.isCameraEnabled).isFalse()
    }

    @Test
    fun `test characterize toggle microphone event`() = runTest {
        // Given: Active call
        coEvery { mockPeerConnectionManager.toggleMicrophone(any()) } returns Result.success(Unit)
        val offer = SignalingMessage.Offer("session-123", "v=0\r\n...", "caller-abc")
        coEvery { mockAnswerCallUseCase(any(), any()) } returns Result.success(Unit)
        viewModel.onEvent(CallUiEvent.AnswerCall(offer))

        // When: Toggling microphone off
        viewModel.onEvent(CallUiEvent.ToggleMicrophone(false))

        // Then: Verify microphone state updated
        assertThat(viewModel.controlsState.value.isMicrophoneEnabled).isFalse()
    }

    @Test
    fun `test characterize error handling`() = runTest {
        // Given: Offer creation fails
        coEvery { mockCreateOfferUseCase(any(), any()) } returns Result.failure(
            Exception("Network error")
        )

        // When: Starting call with error
        viewModel.onEvent(CallUiEvent.StartCall("user-123"))

        // Then: Verify error state
        assertThat(viewModel.callState.value).isInstanceOf(CallState.Error::class.java)
        val errorState = viewModel.callState.value as CallState.Error
        assertThat(errorState.message).contains("Network error")
    }

    @Test
    fun `test characterize dismiss error event`() = runTest {
        // Given: Error state
        coEvery { mockCreateOfferUseCase(any(), any()) } returns Result.failure(
            Exception("Test error")
        )
        viewModel.onEvent(CallUiEvent.StartCall("user-123"))

        // Verify error occurred
        assertThat(viewModel.callState.value).isInstanceOf(CallState.Error::class.java)

        // When: Dismissing error
        viewModel.onEvent(CallUiEvent.DismissError)

        // Then: Verify state reset to idle
        assertThat(viewModel.callState.value).isEqualTo(CallState.Idle)
    }

    @Test
    fun `test characterize ICE candidate handling`() = runTest {
        // Given: ICE candidate
        val candidate = SignalingMessage.IceCandidate(
            sessionId = "session-123",
            sdpMid = "audio",
            sdpMLineIndex = 0,
            sdpCandidate = "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host"
        )
        coEvery { mockAddIceCandidateUseCase(any()) } returns Result.success(Unit)

        // When: Handling ICE candidate
        viewModel.handleIceCandidate(candidate)

        // Then: Verify candidate was added
        assertThat(viewModel.controlsState.value.remoteIceCandidates).isEqualTo(1)
    }
}
