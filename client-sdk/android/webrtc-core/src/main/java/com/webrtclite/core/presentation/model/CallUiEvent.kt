package com.webrtclite.core.presentation.model

/**
 * UI events for call interaction
 */
sealed class CallUiEvent {
    /**
     * Start outgoing call
     */
    data class StartCall(val targetUserId: String) : CallUiEvent()

    /**
     * Answer incoming call
     */
    data class AnswerCall(val offer: com.webrtclite.core.data.model.SignalingMessage.Offer) : CallUiEvent()

    /**
     * End active call
     */
    object EndCall : CallUiEvent()

    /**
     * Toggle camera on/off
     */
    data class ToggleCamera(val enabled: Boolean) : CallUiEvent()

    /**
     * Toggle microphone on/off
     */
    data class ToggleMicrophone(val enabled: Boolean) : CallUiEvent()

    /**
     * Switch camera (front/back)
     */
    object SwitchCamera : CallUiEvent()

    /**
     * Toggle speaker
     */
    data class ToggleSpeaker(val enabled: Boolean) : CallUiEvent()

    /**
     * Dismiss error
     */
    object DismissError : CallUiEvent()
}
