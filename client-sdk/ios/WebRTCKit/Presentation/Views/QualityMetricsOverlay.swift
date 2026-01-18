// MARK: - Quality Metrics Overlay
// TRUST 5 Compliance: Testable, Unified, Trackable

import SwiftUI
import Combine

// MARK: - Quality Metrics Overlay View

/// Overlay component for displaying WebRTC quality metrics
/// Shows RTT, packet loss, bitrate, and quality state with color coding
@available(iOS 13.0, *)
struct QualityMetricsOverlay: View {

    // MARK: - Properties

    let statsReport: RTCStatsReport?
    let isVisible: Bool

    // MARK: - Body

    var body: some View {
        if isVisible, let report = statsReport {
            VStack(alignment: .leading, spacing: 8) {
                // Quality State Header
                Text("Connection Quality: \(report.getQualityState().displayName)")
                    .font(.headline)
                    .foregroundColor(.white)

                Divider()
                    .background(Color.white.opacity(0.3))

                // RTT Metric
                MetricRow(
                    label: "RTT",
                    value: "\(Int(report.rtt)) ms",
                    color: getMetricColor(
                        value: report.rtt,
                        threshold: 100.0,
                        lowerIsBetter: true
                    )
                )

                // Packet Loss Metric
                MetricRow(
                    label: "Packet Loss",
                    value: String(format: "%.2f%%", report.packetLoss),
                    color: getMetricColor(
                        value: report.packetLoss,
                        threshold: 3.0,
                        lowerIsBetter: true
                    )
                )

                // Bitrate Metric
                MetricRow(
                    label: "Bitrate",
                    value: formatBitrate(bps: report.bitrate),
                    color: getMetricColor(
                        value: report.bitrate,
                        threshold: 500_000.0,
                        lowerIsBetter: false
                    )
                )

                // Resolution Metric
                if report.resolutionWidth > 0 && report.resolutionHeight > 0 {
                    MetricRow(
                        label: "Resolution",
                        value: "\(report.resolutionWidth)x\(report.resolutionHeight)",
                        color: .white
                    )
                }

                Divider()
                    .background(Color.white.opacity(0.3))

                // Quality Score
                Text("Quality Score: \(report.calculateQualityScore())/100")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: report.getQualityState().color).opacity(0.9))
            )
            .padding()
        }
    }

    // MARK: - Private Methods

    private func getMetricColor(value: Double, threshold: Double, lowerIsBetter: Bool) -> Color {
        if lowerIsBetter {
            switch value {
            case 0..<threshold * 0.5:
                return .green
            case threshold * 0.5..<threshold:
                return .orange
            default:
                return .red
            }
        } else {
            switch value {
            case threshold * 2...:
                return .green
            case threshold..<threshold * 2:
                return .orange
            default:
                return .red
            }
        }
    }

    private func formatBitrate(bps: Double) -> String {
        switch bps {
        case 1_000_000...:
            return String(format: "%.2f Mbps", bps / 1_000_000)
        case 1_000...:
            return String(format: "%.2f Kbps", bps / 1_000)
        default:
            return String(format: "%.2f bps", bps)
        }
    }
}

// MARK: - Metric Row View

@available(iOS 13.0, *)
struct MetricRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .foregroundColor(color)
                .bold()
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

@available(iOS 13.0, *)
struct QualityMetricsOverlay_Previews: PreviewProvider {
    static var previews: some View {
        QualityMetricsOverlay(
            statsReport: RTCStatsReport(
                timestamp: Date().timeIntervalSince1970 * 1000,
                rtt: 45.0,
                packetLoss: 0.5,
                bitrate: 1_500_000.0,
                resolutionWidth: 1280,
                resolutionHeight: 720,
                bytesReceived: 10_000_000,
                bytesSent: 5_000_000,
                framesDecoded: 3000,
                framesEncoded: 3000
            ),
            isVisible: true
        )
    }
}
