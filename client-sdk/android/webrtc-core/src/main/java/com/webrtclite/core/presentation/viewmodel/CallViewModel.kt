package com.webrtclite.core.presentation.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.domain.usecase.AddIceCandidateUseCase
import com.webrtclite.core.domain.usecase.AnswerCallUseCase
import com.webrtclite.core.domain.usecase.CreateOfferUseCase
import com.webrtclite.core.domain.usecase.EndCallUseCase
import com.webrtclite.core.presentation.model.CallControlsState
import com.webrtclite.core.presentation.model.CallState
import com.webrtclite.core.presentation.model.CallUiEvent
import com.webrtclite.core.webrtc.PeerConnectionManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.webrtc.IceCandidate
import java.util.UUID
import javax.inject.Inject

/**
 * ViewModel for managing WebRTC call state and UI interactions
 */
@HiltViewModel
class CallViewModel @Inject constructor(
    private val createOfferUseCase: CreateOfferUseCase,
    private val answerCallUseCase: AnswerCallUseCase,
    private val addIceCandidateUseCase: AddIceCandidateUseCase,
    private val endCallUseCase: EndCallUseCase,
    private val peerConnectionManager: PeerConnectionManager
) : ViewModel() {

    private val _callState = MutableStateFlow<CallState>(CallState.Idle)
    val callState: StateFlow<CallState> = _callState.asStateFlow()

    private val _controlsState = MutableStateFlow(CallControlsState())
    val controlsState: StateFlow<CallControlsState> = _controlsState.asStateFlow()

    private var currentSessionId: String? = null
    private var callStartTime: Long = 0L

    /**
     * Handle UI events
     */
    fun onEvent(event: CallUiEvent) {
        when (event) {
            is CallUiEvent.StartCall -> startCall(event.targetUserId)
            is CallUiEvent.AnswerCall -> answerCall(event.offer)
            is CallUiEvent.EndCall -> endCall()
            is CallUiEvent.ToggleCamera -> toggleCamera(event.enabled)
            is CallUiEvent.ToggleMicrophone -> toggleMicrophone(event.enabled)
            is CallUiEvent.SwitchCamera -> switchCamera()
            is CallUiEvent.ToggleSpeaker -> toggleSpeaker(event.enabled)
            is CallUiEvent.DismissError -> dismissError()
        }
    }

    /**
     * Start outgoing call
     */
    private fun startCall(targetUserId: String) {
        viewModelScope.launch {
            _callState.value = CallState.Connecting

            val sessionId = UUID.randomUUID().toString()
            currentSessionId = sessionId
            callStartTime = System.currentTimeMillis()

            createOfferUseCase(sessionId, targetUserId)
                .onSuccess {
                    _callState.value = CallState.WaitingForAnswer(sessionId)
                    startIceCandidateObservation(sessionId)
                    startConnectionDurationTracking()
                }
                .onFailure { error ->
                    _callState.value = CallState.Error(
                        message = "Failed to start call: ${error.message}",
                        throwable = error
                    )
                }
        }
    }

    /**
     * Answer incoming call
     */
    private fun answerCall(offer: SignalingMessage.Offer) {
        viewModelScope.launch {
            _callState.value = CallState.Connecting

            currentSessionId = offer.sessionId
            callStartTime = System.currentTimeMillis()

            answerCallUseCase(offer, "current-user-id")
                .onSuccess {
                    _callState.value = CallState.Connected(offer.sessionId)
                    startIceCandidateObservation(offer.sessionId)
                    startConnectionDurationTracking()
                }
                .onFailure { error ->
                    _callState.value = CallState.Error(
                        message = "Failed to answer call: ${error.message}",
                        throwable = error
                    )
                }
        }
    }

    /**
     * End active call
     */
    private fun endCall() {
        viewModelScope.launch {
            _callState.value = CallState.Ending

            currentSessionId?.let { sessionId ->
                endCallUseCase(sessionId)
                    .onSuccess {
                        _callState.value = CallState.Ended()
                        resetCallState()
                    }
                    .onFailure { error ->
                        _callState.value = CallState.Error(
                            message = "Failed to end call: ${error.message}",
                            throwable = error
                        )
                    }
            }
        }
    }

    /**
     * Toggle camera
     */
    private fun toggleCamera(enabled: Boolean) {
        viewModelScope.launch {
            peerConnectionManager.toggleCamera(enabled)
                .onSuccess {
                    _controlsState.value = _controlsState.value.copy(
                        isCameraEnabled = enabled,
                        isLocalVideoVisible = enabled
                    )
                }
        }
    }

    /**
     * Toggle microphone
     */
    private fun toggleMicrophone(enabled: Boolean) {
        viewModelScope.launch {
            peerConnectionManager.toggleMicrophone(enabled)
                .onSuccess {
                    _controlsState.value = _controlsState.value.copy(
                        isMicrophoneEnabled = enabled
                    )
                }
        }
    }

    /**
     * Switch camera
     */
    private fun switchCamera() {
        viewModelScope.launch {
            peerConnectionManager.switchCamera()
        }
    }

    /**
     * Toggle speaker
     */
    private fun toggleSpeaker(enabled: Boolean) {
        _controlsState.value = _controlsState.value.copy(
            isSpeakerEnabled = enabled
        )
    }

    /**
     * Dismiss error state
     */
    private fun dismissError() {
        if (_callState.value is CallState.Error) {
            _callState.value = CallState.Idle
        }
    }

    /**
     * Start observing ICE candidates
     */
    private fun startIceCandidateObservation(sessionId: String) {
        viewModelScope.launch {
            peerConnectionManager.observeIceCandidates().collect { candidate ->
                addIceCandidateUseCase.signalLocalCandidate(sessionId, UUID.randomUUID().toString(), candidate)
                    .onSuccess {
                        _controlsState.value = _controlsState.value.copy(
                            localIceCandidates = _controlsState.value.localIceCandidates + 1
                        )
                    }
            }
        }
    }

    /**
     * Start tracking connection duration
     */
    private fun startConnectionDurationTracking() {
        viewModelScope.launch {
            while (_callState.value is CallState.Connected) {
                kotlinx.coroutines.delay(1000)
                val duration = System.currentTimeMillis() - callStartTime
                _controlsState.value = _controlsState.value.copy(
                    connectionDuration = duration / 1000
                )
            }
        }
    }

    /**
     * Reset call state
     */
    private fun resetCallState() {
        currentSessionId = null
        callStartTime = 0L
        _controlsState.value = CallControlsState()
    }

    /**
     * Handle incoming ICE candidate
     */
    fun handleIceCandidate(candidate: SignalingMessage.IceCandidate) {
        viewModelScope.launch {
            addIceCandidateUseCase(candidate)
                .onSuccess {
                    _controlsState.value = _controlsState.value.copy(
                        remoteIceCandidates = _controlsState.value.remoteIceCandidates + 1
                    )
                }
                .onFailure { error ->
                    // Log error but don't disrupt call
                    _callState.value = CallState.Error(
                        message = "ICE candidate error: ${error.message}",
                        throwable = error
                    )
                }
        }
    }
}
