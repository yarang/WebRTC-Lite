package com.webrtclite.core.presentation.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import com.webrtclite.core.presentation.model.CallState
import com.webrtclite.core.presentation.viewmodel.CallViewModel

/**
 * Main call screen composable
 */
@Composable
fun CallScreen(
    viewModel: CallViewModel = hiltViewModel(),
    onCallEnded: () -> Unit = {}
) {
    val callState by viewModel.callState.collectAsState()
    val controlsState by viewModel.controlsState.collectAsState()

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        when (val state = callState) {
            is CallState.Idle -> IdleScreen()
            is CallState.Connecting -> ConnectingScreen()
            is CallState.WaitingForAnswer -> WaitingScreen(state.sessionId)
            is CallState.Connected -> ConnectedCallScreen(
                state = state,
                controlsState = controlsState,
                viewModel = viewModel
            )
            is CallState.Ending -> EndingScreen()
            is CallState.Ended -> EndedScreen(state.reason, onCallEnded)
            is CallState.Error -> ErrorScreen(state.message, viewModel::onEvent)
        }
    }
}

/**
 * Connected call screen with video and controls
 */
@Composable
fun ConnectedCallScreen(
    state: CallState.Connected,
    controlsState: com.webrtclite.core.presentation.model.CallControlsState,
    viewModel: CallViewModel
) {
    Box(modifier = Modifier.fillMaxSize()) {
        // Remote video (full screen)
        RemoteVideoView(
            modifier = Modifier.fillMaxSize(),
            isVisible = state.isRemoteVideoEnabled
        )

        // Local video (picture-in-picture)
        LocalVideoView(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(16.dp)
                .size(120.dp, 160.dp)
                .clip(RoundedCornerShape(12.dp)),
            isVisible = controlsState.isLocalVideoVisible
        )

        // Call info
        CallInfo(
            sessionId = state.sessionId,
            duration = controlsState.connectionDuration,
            modifier = Modifier
                .align(Alignment.TopStart)
                .padding(16.dp)
        )

        // Call controls
        CallControls(
            isCameraEnabled = controlsState.isCameraEnabled,
            isMicrophoneEnabled = controlsState.isMicrophoneEnabled,
            isSpeakerEnabled = controlsState.isSpeakerEnabled,
            onToggleCamera = { viewModel.onEvent(com.webrtclite.core.presentation.model.CallUiEvent.ToggleCamera(!controlsState.isCameraEnabled)) },
            onToggleMicrophone = { viewModel.onEvent(com.webrtclite.core.presentation.model.CallUiEvent.ToggleMicrophone(!controlsState.isMicrophoneEnabled)) },
            onToggleSpeaker = { viewModel.onEvent(com.webrtclite.core.presentation.model.CallUiEvent.ToggleSpeaker(!controlsState.isSpeakerEnabled)) },
            onSwitchCamera = { viewModel.onEvent(com.webrtclite.core.presentation.model.CallUiEvent.SwitchCamera) },
            onEndCall = { viewModel.onEvent(com.webrtclite.core.presentation.model.CallUiEvent.EndCall) },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(24.dp)
        )
    }
}

/**
 * Remote video view placeholder
 */
@Composable
fun RemoteVideoView(
    modifier: Modifier = Modifier,
    isVisible: Boolean = true
) {
    if (isVisible) {
        Box(
            modifier = modifier
                .background(Color.DarkGray),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "Remote Video",
                color = Color.White,
                fontSize = 16.sp
            )
        }
    }
}

/**
 * Local video view placeholder
 */
@Composable
fun LocalVideoView(
    modifier: Modifier = Modifier,
    isVisible: Boolean = true
) {
    if (isVisible) {
        Box(
            modifier = modifier
                .background(Color.Gray),
            contentAlignment = Alignment.Center
        ) {
            Text(
                text = "You",
                color = Color.White,
                fontSize = 12.sp
            )
        }
    }
}

/**
 * Call info display
 */
@Composable
fun CallInfo(
    sessionId: String,
    duration: Long,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .background(Color.Black.copy(alpha = 0.5f))
            .padding(12.dp)
    ) {
        Text(
            text = formatDuration(duration),
            color = Color.White,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = "Session: ${sessionId.take(8)}",
            color = Color.White.copy(alpha = 0.7f),
            fontSize = 12.sp
        )
    }
}

/**
 * Call controls buttons
 */
@Composable
fun CallControls(
    isCameraEnabled: Boolean,
    isMicrophoneEnabled: Boolean,
    isSpeakerEnabled: Boolean,
    onToggleCamera: () -> Unit,
    onToggleMicrophone: () -> Unit,
    onToggleSpeaker: () -> Unit,
    onSwitchCamera: () -> Unit,
    onEndCall: () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Toggle camera
        ControlButton(
            icon = if (isCameraEnabled) "\u2744" else "\uD83D\uDCAB", // Snowflake/Closed
            label = if (isCameraEnabled) "Camera" else "Muted",
            backgroundColor = if (isCameraEnabled) Color.White else Color.Red,
            onClick = onToggleCamera
        )

        // Toggle microphone
        ControlButton(
            icon = if (isMicrophoneEnabled) "\uD83D\uDD0A" else "\uD83D\uDD07", // Microphone/Muted
            label = if (isMicrophoneEnabled) "Mic" else "Muted",
            backgroundColor = if (isMicrophoneEnabled) Color.White else Color.Red,
            onClick = onToggleMicrophone
        )

        // End call
        ControlButton(
            icon = "\uD83D\uDD0E", // Telephone
            label = "End",
            backgroundColor = Color.Red,
            onClick = onEndCall
        )

        // Toggle speaker
        ControlButton(
            icon = if (isSpeakerEnabled) "\uD83D\uDD0A" else "\uD83D\uDD07",
            label = if (isSpeakerEnabled) "Speaker" else "Earpiece",
            backgroundColor = if (isSpeakerEnabled) Color.White else Color.Gray,
            onClick = onToggleSpeaker
        )

        // Switch camera
        ControlButton(
            icon = "\uD83D\uDCF7", // Camera
            label = "Flip",
            backgroundColor = Color.White,
            onClick = onSwitchCamera
        )
    }
}

/**
 * Individual control button
 */
@Composable
fun ControlButton(
    icon: String,
    label: String,
    backgroundColor: Color,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
    ) {
        Button(
            onClick = onClick,
            modifier = Modifier
                .size(56.dp)
                .clip(CircleShape),
            colors = ButtonDefaults.buttonColors(
                containerColor = backgroundColor
            ),
            contentPadding = PaddingValues(0.dp)
        ) {
            Text(
                text = icon,
                fontSize = 24.sp,
                color = Color.Black
            )
        }
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = label,
            color = Color.White,
            fontSize = 10.sp
        )
    }
}

/**
 * Idle screen
 */
@Composable
fun IdleScreen() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = "Ready to call",
            color = Color.White,
            fontSize = 18.sp
        )
    }
}

/**
 * Connecting screen
 */
@Composable
fun ConnectingScreen() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CircularProgressIndicator(color = Color.White)
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Connecting...",
                color = Color.White,
                fontSize = 18.sp
            )
        }
    }
}

/**
 * Waiting for answer screen
 */
@Composable
fun WaitingScreen(sessionId: String) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CircularProgressIndicator(color = Color.White)
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Waiting for answer...",
                color = Color.White,
                fontSize = 18.sp
            )
            Text(
                text = "Session: ${sessionId.take(8)}",
                color = Color.White.copy(alpha = 0.7f),
                fontSize = 14.sp
            )
        }
    }
}

/**
 * Ending screen
 */
@Composable
fun EndingScreen() {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CircularProgressIndicator(color = Color.White)
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = "Ending call...",
                color = Color.White,
                fontSize = 18.sp
            )
        }
    }
}

/**
 * Ended screen
 */
@Composable
fun EndedScreen(reason: String?, onNavigateBack: () -> Unit) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "Call ended",
                color = Color.White,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )
            reason?.let {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = it,
                    color = Color.White.copy(alpha = 0.7f),
                    fontSize = 14.sp
                )
            }
            Spacer(modifier = Modifier.height(24.dp))
            Button(onClick = onNavigateBack) {
                Text("Back")
            }
        }
    }
}

/**
 * Error screen
 */
@Composable
fun ErrorScreen(
    message: String,
    onEvent: (com.webrtclite.core.presentation.model.CallUiEvent) -> Unit
) {
    Box(
        modifier = Modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(32.dp)
        ) {
            Text(
                text = "Error",
                color = Color.Red,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold
            )
            Spacer(modifier = Modifier.height(16.dp))
            Text(
                text = message,
                color = Color.White,
                fontSize = 16.sp
            )
            Spacer(modifier = Modifier.height(24.dp))
            Button(onClick = { onEvent(com.webrtclite.core.presentation.model.CallUiEvent.DismissError) }) {
                Text("Dismiss")
            }
        }
    }
}

/**
 * Format duration in seconds to MM:SS
 */
private fun formatDuration(seconds: Long): String {
    val minutes = seconds / 60
    val secs = seconds % 60
    return String.format("%02d:%02d", minutes, secs)
}
