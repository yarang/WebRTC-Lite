package com.webrtclite.core.webrtc

import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mock
import org.mockito.junit.MockitoJUnitRunner
import org.mockito.kotlin.*
import org.webrtc.PeerConnection

/**
 * Unit tests for ReconnectionManager
 * Tests state machine, exponential backoff, and reconnection strategies
 */
@RunWith(MockitoJUnitRunner::class)
class ReconnectionManagerTest {

    @Mock
    private lateinit var mockPeerConnection: PeerConnection

    private lateinit var reconnectionManager: ReconnectionManager

    @Before
    fun setup() {
        reconnectionManager = ReconnectionManager()
    }

    @Test
    fun `test initial state is STABLE`() {
        assertEquals("Initial state should be STABLE", ReconnectionManager.ReconnectionState.STABLE, reconnectionManager.reconnectionState.value)
    }

    @Test
    fun `test retry count starts at 0`() {
        assertEquals("Initial retry count should be 0", 0, reconnectionManager.retryCount.value)
    }

    @Test
    fun `test minor failure triggers ICE restart`() = runTest {
        var strategyUsed: ReconnectionStrategy? = null

        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.MINOR,
            peerConnection = mockPeerConnection,
            onReconnect = { strategy ->
                strategyUsed = strategy
                Result.success(Unit)
            }
        )

        assertEquals("Should use ICE restart for minor failure", ReconnectionStrategy.ICE_RESTART, strategyUsed)
    }

    @Test
    fun `test major failure triggers full reconnection`() = runTest {
        var strategyUsed: ReconnectionStrategy? = null

        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.MAJOR,
            peerConnection = mockPeerConnection,
            onReconnect = { strategy ->
                strategyUsed = strategy
                Result.success(Unit)
            }
        )

        assertEquals("Should use full reconnection for major failure", ReconnectionStrategy.FULL_RECONNECTION, strategyUsed)
    }

    @Test
    fun `test fatal failure sets state to FAILED`() = runTest {
        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.FATAL,
            peerConnection = mockPeerConnection,
            onReconnect = { _ -> Result.success(Unit) }
        )

        assertEquals("State should be FAILED after fatal error", ReconnectionManager.ReconnectionState.FAILED, reconnectionManager.reconnectionState.value)
    }

    @Test
    fun `test successful reconnection resets state`() = runTest {
        // First, trigger a failure
        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.MINOR,
            peerConnection = mockPeerConnection,
            onReconnect = { Result.success(Unit) }
        )

        // State should return to STABLE after successful reconnection
        assertEquals("State should be STABLE after successful reconnection", ReconnectionManager.ReconnectionState.STABLE, reconnectionManager.reconnectionState.value)
        assertEquals("Retry count should reset to 0", 0, reconnectionManager.retryCount.value)
    }

    @Test
    fun `test failed reconnection increments retry count`() = runTest {
        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.MINOR,
            peerConnection = mockPeerConnection,
            onReconnect = { Result.failure(Exception("Reconnection failed")) }
        )

        assertEquals("Retry count should increment", 1, reconnectionManager.retryCount.value)
        assertEquals("State should remain RECONNECTING", ReconnectionManager.ReconnectionState.RECONNECTING, reconnectionManager.reconnectionState.value)
    }

    @Test
    fun `test max retry attempts sets state to FAILED`() = runTest {
        // Simulate 3 failed attempts
        repeat(ReconnectionManager.MAX_RETRY_ATTEMPTS) {
            reconnectionManager.handleFailure(
                failureType = ReconnectionManager.FailureType.MINOR,
                peerConnection = mockPeerConnection,
                onReconnect = { Result.failure(Exception("Failed")) }
            )
        }

        assertEquals("State should be FAILED after max retries", ReconnectionManager.ReconnectionState.FAILED, reconnectionManager.reconnectionState.value)
    }

    @Test
    fun `test exponential backoff delays`() {
        // Check backoff delays for first 3 attempts
        reconnectionManager.reset()

        // Attempt 1: 1 second
        val delay1 = reconnectionManager.getCurrentBackoffDelay()
        assertEquals("First attempt should have 1s delay", 1000L, delay1)

        // Simulate first retry
        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.MINOR,
            peerConnection = mockPeerConnection,
            onReconnect = { Result.failure(Exception("Failed")) }
        )

        // Attempt 2: 2 seconds
        val delay2 = reconnectionManager.getCurrentBackoffDelay()
        assertEquals("Second attempt should have 2s delay", 2000L, delay2)
    }

    @Test
    fun `test canReconnect returns true when retries available`() {
        assertTrue("Should be able to reconnect initially", reconnectionManager.canReconnect())

        // After one failed attempt
        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.MINOR,
            peerConnection = mockPeerConnection,
            onReconnect = { Result.failure(Exception("Failed")) }
        )

        assertTrue("Should still be able to reconnect with retries left", reconnectionManager.canReconnect())
    }

    @Test
    fun `test canReconnect returns false when max retries reached`() = runTest {
        // Exhaust all retries
        repeat(ReconnectionManager.MAX_RETRY_ATTEMPTS) {
            reconnectionManager.handleFailure(
                failureType = ReconnectionManager.FailureType.MINOR,
                peerConnection = mockPeerConnection,
                onReconnect = { Result.failure(Exception("Failed")) }
            )
        }

        assertFalse("Should not be able to reconnect after max retries", reconnectionManager.canReconnect())
    }

    @Test
    fun `test reset clears reconnection state`() = runTest {
        // Trigger a failure
        reconnectionManager.handleFailure(
            failureType = ReconnectionManager.FailureType.MINOR,
            peerConnection = mockPeerConnection,
            onReconnect = { Result.failure(Exception("Failed")) }
        )

        // Reset
        reconnectionManager.reset()

        assertEquals("State should reset to STABLE", ReconnectionManager.ReconnectionState.STABLE, reconnectionManager.reconnectionState.value)
        assertEquals("Retry count should reset to 0", 0, reconnectionManager.retryCount.value)
        assertTrue("Should be able to reconnect after reset", reconnectionManager.canReconnect())
    }
}
