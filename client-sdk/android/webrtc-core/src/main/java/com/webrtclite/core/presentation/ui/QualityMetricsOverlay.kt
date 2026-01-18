package com.webrtclite.core.presentation.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.webrtclite.core.webrtc.QualityState
import com.webrtclite.core.webrtc.RTCStatsReport

/**
 * Overlay component for displaying WebRTC quality metrics
 * Shows RTT, packet loss, bitrate, and quality state with color coding
 */
@Composable
fun QualityMetricsOverlay(
    statsReport: RTCStatsReport?,
    isVisible: Boolean,
    modifier: Modifier = Modifier
) {
    if (!isVisible || statsReport == null) {
        return
    }

    val qualityState = statsReport.getQualityState()
    val backgroundColor = getQualityColor(qualityState).copy(alpha = 0.9f)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(16.dp)
            .background(
                color = backgroundColor,
                shape = RoundedCornerShape(12.dp)
            )
            .padding(16.dp)
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            horizontalAlignment = Alignment.Start
        ) {
            // Quality State Header
            Text(
                text = "Connection Quality: ${qualityState.name}",
                style = MaterialTheme.typography.titleMedium,
                color = Color.White,
                fontSize = 18.sp
            )

            Spacer(modifier = Modifier.height(4.dp))

            // RTT Metric
            MetricRow(
                label = "RTT",
                value = "${statsReport.rtt.toInt()} ms",
                color = getMetricColor(statsReport.rtt, 100.0)
            )

            // Packet Loss Metric
            MetricRow(
                label = "Packet Loss",
                value = "${"%.2f".format(statsReport.packetLoss)}%",
                color = getMetricColor(statsReport.packetLoss, 3.0)
            )

            // Bitrate Metric
            MetricRow(
                label = "Bitrate",
                value = formatBitrate(statsReport.bitrate),
                color = getMetricColorInverse(statsReport.bitrate, 500_000.0)
            )

            // Resolution Metric
            if (statsReport.resolutionWidth > 0 && statsReport.resolutionHeight > 0) {
                MetricRow(
                    label = "Resolution",
                    value = "${statsReport.resolutionWidth}x${statsReport.resolutionHeight}",
                    color = Color.White
                )
            }

            // Quality Score
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Quality Score: ${statsReport.calculateQualityScore()}/100",
                style = MaterialTheme.typography.bodySmall,
                color = Color.White.copy(alpha = 0.8f)
            )
        }
    }
}

@Composable
private fun MetricRow(
    label: String,
    value: String,
    color: Color
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = Color.White
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = color
        )
    }
}

/**
 * Get color based on quality state
 */
private fun getQualityColor(state: QualityState): Color {
    return when (state) {
        QualityState.EXCELLENT -> Color(0xFF4CAF50)  // Green
        QualityState.GOOD -> Color(0xFF8BC34A)       // Light Green
        QualityState.FAIR -> Color(0xFFFF9800)       // Orange
        QualityState.POOR -> Color(0xFFF44336)       // Red
    }
}

/**
 * Get metric color (lower is better for RTT and packet loss)
 */
private fun getMetricColor(value: Double, threshold: Double): Color {
    return when {
        value < threshold * 0.5 -> Color(0xFF4CAF50)  // Green
        value < threshold -> Color(0xFFFF9800)        // Orange
        else -> Color(0xFFF44336)                     // Red
    }
}

/**
 * Get metric color (higher is better for bitrate)
 */
private fun getMetricColorInverse(value: Double, threshold: Double): Color {
    return when {
        value > threshold * 2 -> Color(0xFF4CAF50)    // Green
        value > threshold -> Color(0xFFFF9800)        // Orange
        else -> Color(0xFFF44336)                     // Red
    }
}

/**
 * Format bitrate for display
 */
private fun formatBitrate(bps: Double): String {
    return when {
        bps >= 1_000_000 -> String.format("%.2f Mbps", bps / 1_000_000)
        bps >= 1_000 -> String.format("%.2f Kbps", bps / 1_000)
        else -> String.format("%.2f bps", bps)
    }
}
