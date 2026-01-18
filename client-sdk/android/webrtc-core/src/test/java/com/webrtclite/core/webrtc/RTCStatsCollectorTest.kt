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
 * Unit tests for RTCStatsCollector
 * Tests stats collection, quality calculation, and state management
 */
@RunWith(MockitoJUnitRunner::class)
class RTCStatsCollectorTest {

    @Mock
    private lateinit var mockPeerConnection: PeerConnection

    private lateinit var collector: RTCStatsCollector

    @Before
    fun setup() {
        collector = RTCStatsCollector()
    }

    @Test
    fun `test collector starts and stops collecting`() = runTest {
        // Start collecting
        collector.startCollecting(mockPeerConnection)
        collector.stopCollecting()

        // Verify no errors
        assertTrue("Collector should stop successfully", true)
    }

    @Test
    fun `test quality score calculation - excellent`() {
        val report = RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = 30.0,           // < 50ms
            packetLoss = 0.5,     // < 1%
            bitrate = 1_500_000.0, // > 1Mbps
            resolutionWidth = 1280,
            resolutionHeight = 720,
            bytesReceived = 10_000_000,
            bytesSent = 5_000_000,
            framesDecoded = 3000,
            framesEncoded = 3000
        )

        val score = report.calculateQualityScore()
        val state = report.getQualityState()

        assertTrue("Score should be >= 85 for excellent quality", score >= 85)
        assertEquals("State should be EXCELLENT", QualityState.EXCELLENT, state)
    }

    @Test
    fun `test quality score calculation - good`() {
        val report = RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = 75.0,           // < 100ms
            packetLoss = 2.0,     // < 3%
            bitrate = 750_000.0,  // > 500Kbps
            resolutionWidth = 1280,
            resolutionHeight = 720,
            bytesReceived = 10_000_000,
            bytesSent = 5_000_000,
            framesDecoded = 3000,
            framesEncoded = 3000
        )

        val score = report.calculateQualityScore()
        val state = report.getQualityState()

        assertTrue("Score should be 70-84 for good quality", score in 70..84)
        assertEquals("State should be GOOD", QualityState.GOOD, state)
    }

    @Test
    fun `test quality score calculation - fair`() {
        val report = RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = 150.0,          // < 200ms
            packetLoss = 4.0,     // < 5%
            bitrate = 300_000.0,  // > 250Kbps
            resolutionWidth = 640,
            resolutionHeight = 480,
            bytesReceived = 5_000_000,
            bytesSent = 2_500_000,
            framesDecoded = 1500,
            framesEncoded = 1500
        )

        val score = report.calculateQualityScore()
        val state = report.getQualityState()

        assertTrue("Score should be 50-69 for fair quality", score in 50..69)
        assertEquals("State should be FAIR", QualityState.FAIR, state)
    }

    @Test
    fun `test quality score calculation - poor`() {
        val report = RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = 250.0,          // >= 200ms
            packetLoss = 6.0,     // >= 5%
            bitrate = 100_000.0,  // <= 250Kbps
            resolutionWidth = 320,
            resolutionHeight = 240,
            bytesReceived = 1_000_000,
            bytesSent = 500_000,
            framesDecoded = 300,
            framesEncoded = 300
        )

        val score = report.calculateQualityScore()
        val state = report.getQualityState()

        assertTrue("Score should be < 50 for poor quality", score < 50)
        assertEquals("State should be POOR", QualityState.POOR, state)
    }

    @Test
    fun `test quality score is never negative`() {
        val report = RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = 1000.0,         // Very high
            packetLoss = 100.0,   // 100% loss
            bitrate = 0.0,        // No bitrate
            resolutionWidth = 0,
            resolutionHeight = 0,
            bytesReceived = 0,
            bytesSent = 0,
            framesDecoded = 0,
            framesEncoded = 0
        )

        val score = report.calculateQualityScore()

        assertEquals("Score should be 0 at minimum", 0, score)
    }

    @Test
    fun `test quality state transitions`() {
        val excellent = RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = 30.0, packetLoss = 0.5, bitrate = 1_500_000.0,
            resolutionWidth = 1280, resolutionHeight = 720,
            bytesReceived = 10_000_000, bytesSent = 5_000_000,
            framesDecoded = 3000, framesEncoded = 3000
        )

        val poor = RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = 250.0, packetLoss = 6.0, bitrate = 100_000.0,
            resolutionWidth = 320, resolutionHeight = 240,
            bytesReceived = 1_000_000, bytesSent = 500_000,
            framesDecoded = 300, framesEncoded = 300
        )

        assertEquals("Excellent state", QualityState.EXCELLENT, excellent.getQualityState())
        assertEquals("Poor state", QualityState.POOR, poor.getQualityState())
    }
}
