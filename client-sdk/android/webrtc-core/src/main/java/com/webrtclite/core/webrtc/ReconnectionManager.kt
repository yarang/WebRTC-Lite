package com.webrtclite.core.webrtc

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.webrtc.PeerConnection
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manager for automatic reconnection with state machine
 * Handles reconnection states: Stable, Reconnecting, Failed
 * Implements exponential backoff and ICE restart logic
 */
@Singleton
class ReconnectionManager @Inject constructor() {

    // State management
    private val _reconnectionState = MutableStateFlow(ReconnectionState.STABLE)
    val reconnectionState: StateFlow<ReconnectionState> = _reconnectionState.asStateFlow()

    private val _retryCount = MutableStateFlow(0)
    val retryCount: StateFlow<Int> = _retryCount.asStateFlow()

    private val mutex = Mutex()

    companion object {
        private const val MAX_RETRY_ATTEMPTS = 3
        private val BACKOFF_DELAYS = listOf(1000L, 2000L, 4000L) // 1s, 2s, 4s
    }

    /**
     * Reconnection states
     */
    enum class ReconnectionState {
        STABLE,      // Connection is stable
        RECONNECTING, // Attempting to reconnect
        FAILED        // All reconnection attempts failed
    }

    /**
     * Reconnection failure types
     */
    enum class FailureType {
        MINOR,   // ICE restart can fix (e.g., candidate pair failure)
        MAJOR,   // Full reconnection needed (e.g., peer connection closed)
        FATAL    // Cannot recover (e.g., authentication failure)
    }

    private data class ReconnectionAttempt(
        val attemptNumber: Int,
        val failureType: FailureType,
        val timestamp: Long = System.currentTimeMillis()
    )

    private var currentAttempt: ReconnectionAttempt? = null

    /**
     * Handle connection failure and attempt reconnection
     * @param failureType Type of failure that occurred
     * @param peerConnection Current peer connection (for ICE restart)
     * @param onReconnect Callback to perform reconnection
     */
    suspend fun handleFailure(
        failureType: FailureType,
        peerConnection: PeerConnection? = null,
        onReconnect: suspend (ReconnectionStrategy) -> Result<Unit>
    ) {
        mutex.withLock {
            if (_reconnectionState.value == ReconnectionState.RECONNECTING) {
                // Already reconnecting, skip
                return
            }

            if (_retryCount.value >= MAX_RETRY_ATTEMPTS) {
                _reconnectionState.value = ReconnectionState.FAILED
                return
            }

            _reconnectionState.value = ReconnectionState.RECONNECTING
            val attemptNumber = _retryCount.value + 1
            currentAttempt = ReconnectionAttempt(attemptNumber, failureType)
            _retryCount.value = attemptNumber
        }

        // Get backoff delay
        val backoffDelay = if (attemptNumber <= BACKOFF_DELAYS.size) {
            BACKOFF_DELAYS[attemptNumber - 1]
        } else {
            BACKOFF_DELAYS.last() * (1L shl (attemptNumber - BACKOFF_DELAYS.size))
        }

        // Wait before attempting reconnection
        delay(backoffDelay)

        // Determine reconnection strategy
        val strategy = when (failureType) {
            FailureType.MINOR -> ReconnectionStrategy.ICE_RESTART
            FailureType.MAJOR -> ReconnectionStrategy.FULL_RECONNECTION
            FailureType.FATAL -> {
                _reconnectionState.value = ReconnectionState.FAILED
                return
            }
        }

        // Attempt reconnection
        val result = onReconnect(strategy)

        if (result.isSuccess) {
            // Reconnection successful
            _reconnectionState.value = ReconnectionState.STABLE
            _retryCount.value = 0
            currentAttempt = null
        } else {
            // Reconnection failed, check if we should retry
            if (attemptNumber >= MAX_RETRY_ATTEMPTS) {
                _reconnectionState.value = ReconnectionState.FAILED
            } else {
                // Stay in reconnecting state for next attempt
                _reconnectionState.value = ReconnectionState.RECONNECTING
            }
        }
    }

    /**
     * Reset reconnection state (call when connection is stable)
     */
    suspend fun reset() {
        mutex.withLock {
            _reconnectionState.value = ReconnectionState.STABLE
            _retryCount.value = 0
            currentAttempt = null
        }
    }

    /**
     * Get current backoff delay for logging
     */
    fun getCurrentBackoffDelay(): Long {
        val attempt = _retryCount.value
        return if (attempt <= BACKOFF_DELAYS.size) {
            BACKOFF_DELAYS.getOrElse(attempt - 1) { BACKOFF_DELAYS.last() }
        } else {
            BACKOFF_DELAYS.last() * (1L shl (attempt - BACKOFF_DELAYS.size))
        }
    }

    /**
     * Check if reconnection is possible
     */
    fun canReconnect(): Boolean {
        return _retryCount.value < MAX_RETRY_ATTEMPTS &&
               _reconnectionState.value != ReconnectionState.FAILED
    }
}

/**
 * Reconnection strategies
 */
enum class ReconnectionStrategy {
    ICE_RESTART,        // Restart ICE only (keep peer connection)
    FULL_RECONNECTION   // Full reconnection (create new peer connection)
}
