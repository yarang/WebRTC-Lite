package com.webrtclite.core.webrtc

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.delay
import kotlinx.coroutines.channels.awaitClose
import org.webrtc.PeerConnection
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Collector for WebRTC RTC statistics
 * Collects network metrics at regular intervals for monitoring and quality assessment
 */
@Singleton
class RTCStatsCollector @Inject constructor() {

    private val _statsReport = MutableStateFlow<RTCStatsReport?>(null)
    val statsReport: Flow<RTCStatsReport?> = _statsReport

    private var peerConnection: PeerConnection? = null
    private var isCollecting = false
    private var collectionJob: kotlinx.coroutines.Job? = null

    companion object {
        private const val COLLECTION_INTERVAL_MS = 1000L // 1 second
    }

    /**
     * Start collecting stats from the peer connection
     * @param pc The peer connection to monitor
     */
    suspend fun startCollecting(pc: PeerConnection) {
        if (isCollecting) {
            return
        }

        peerConnection = pc
        isCollecting = true

        collectionJob = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            while (isCollecting) {
                collectStats()
                delay(COLLECTION_INTERVAL_MS)
            }
        }
    }

    /**
     * Stop collecting stats
     */
    suspend fun stopCollecting() {
        isCollecting = false
        collectionJob?.cancel()
        collectionJob = null
        _statsReport.value = null
    }

    /**
     * Collect current stats from peer connection
     */
    private suspend fun collectStats() {
        val pc = peerConnection ?: return

        pc.getStats(null) { reports ->
            val statsReport = parseStatsReport(reports)
            _statsReport.value = statsReport
        }
    }

    /**
     * Parse WebRTC stats report into structured format
     */
    private fun parseStatsReport(reports: Array<org.webrtc.StatsReport>): RTCStatsReport {
        var rtt = 0.0
        var packetLoss = 0.0
        var bytesReceived = 0L
        var bytesSent = 0L
        var framesDecoded = 0L
        var framesEncoded = 0L
        var currentBitrate = 0.0
        var resolutionWidth = 0
        var resolutionHeight = 0

        for (report in reports) {
            when (report.type) {
                "candidate-pair" -> {
                    // Extract RTT from active candidate pair
                    report.values["currentRoundTripTime"]?.let { rtt = it.toDouble() }
                }
                "inbound-rtp" -> {
                    // Extract receiver metrics
                    report.values["packetsLost"]?.let { lost ->
                        report.values["packetsReceived"]?.let { received ->
                            val total = lost.toDouble() + received.toDouble()
                            if (total > 0) {
                                packetLoss = (lost.toDouble() / total) * 100
                            }
                        }
                    }
                    report.values["bytesReceived"]?.let { bytesReceived = it.toLong() }
                    report.values["framesDecoded"]?.let { framesDecoded = it.toLong() }
                }
                "outbound-rtp" -> {
                    // Extract sender metrics
                    report.values["bytesSent"]?.let { bytesSent = it.toLong() }
                    report.values["framesEncoded"]?.let { framesEncoded = it.toLong() }
                }
                "track" -> {
                    // Extract video resolution
                    report.values["frameWidth"]?.let { resolutionWidth = it.toInt() }
                    report.values["frameHeight"]?.let { resolutionHeight = it.toInt() }
                }
            }
        }

        // Calculate bitrate (bytes per second)
        val previousReport = _statsReport.value
        if (previousReport != null) {
            val timeDiff = System.currentTimeMillis() - previousReport.timestamp
            if (timeDiff > 0) {
                val bytesDiff = (bytesReceived + bytesSent) - (previousReport.bytesReceived + previousReport.bytesSent)
                currentBitrate = (bytesDiff.toDouble() * 8) / (timeDiff / 1000.0)
            }
        }

        return RTCStatsReport(
            timestamp = System.currentTimeMillis(),
            rtt = rtt * 1000, // Convert to milliseconds
            packetLoss = packetLoss,
            bitrate = currentBitrate,
            resolutionWidth = resolutionWidth,
            resolutionHeight = resolutionHeight,
            bytesReceived = bytesReceived,
            bytesSent = bytesSent,
            framesDecoded = framesDecoded,
            framesEncoded = framesEncoded
        )
    }
}

/**
 * Data class representing RTC statistics report
 */
data class RTCStatsReport(
    val timestamp: Long,
    val rtt: Double,           // Round-trip time in milliseconds
    val packetLoss: Double,    // Packet loss percentage
    val bitrate: Double,       // Current bitrate in bps
    val resolutionWidth: Int,  // Video width
    val resolutionHeight: Int, // Video height
    val bytesReceived: Long,   // Total bytes received
    val bytesSent: Long,       // Total bytes sent
    val framesDecoded: Long,   // Total frames decoded
    val framesEncoded: Long    // Total frames encoded
) {
    /**
     * Calculate quality score (0-100) based on metrics
     */
    fun calculateQualityScore(): Int {
        var score = 100

        // RTT penalty (excellent < 50ms, good < 100ms, fair < 200ms, poor >= 200ms)
        when {
            rtt < 50 -> score -= 0
            rtt < 100 -> score -= 10
            rtt < 200 -> score -= 30
            else -> score -= 50
        }

        // Packet loss penalty (excellent < 1%, good < 3%, fair < 5%, poor >= 5%)
        when {
            packetLoss < 1.0 -> score -= 0
            packetLoss < 3.0 -> score -= 10
            packetLoss < 5.0 -> score -= 20
            else -> score -= 40
        }

        // Bitrate quality (excellent > 1Mbps, good > 500kbps, fair > 250kbps, poor <= 250kbps)
        when {
            bitrate > 1_000_000 -> score -= 0
            bitrate > 500_000 -> score -= 5
            bitrate > 250_000 -> score -= 15
            else -> score -= 25
        }

        return score.coerceAtLeast(0)
    }

    /**
     * Get quality state based on score
     */
    fun getQualityState(): QualityState {
        val score = calculateQualityScore()
        return when {
            score >= 85 -> QualityState.EXCELLENT
            score >= 70 -> QualityState.GOOD
            score >= 50 -> QualityState.FAIR
            else -> QualityState.POOR
        }
    }
}

/**
 * Quality state enum
 */
enum class QualityState {
    EXCELLENT,
    GOOD,
    FAIR,
    POOR
}
