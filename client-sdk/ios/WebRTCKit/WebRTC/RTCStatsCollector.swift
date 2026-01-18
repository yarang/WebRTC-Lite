// MARK: - RTC Stats Collector
// TRUST 5 Compliance: Testable, Unified, Trackable

import Foundation
import WebRTC
import Combine

// MARK: - RTC Stats Collector

/// Collector for WebRTC RTC statistics
/// Collects network metrics at regular intervals for monitoring and quality assessment
@available(iOS 13.0, *)
final class RTCStatsCollector {

    // MARK: - Properties

    private let statsReportSubject = PassthroughSubject<RTCStatsReport, Never>()
    var statsReportPublisher: AnyPublisher<RTCStatsReport, Never> {
        statsReportSubject.eraseToAnyPublisher()
    }

    private var peerConnection: RTCPeerConnection?
    private var collectionTask: Task<Void, Never>?
    private var isCollecting = false

    private enum Constants {
        static let collectionInterval: TimeInterval = 1.0 // 1 second
    }

    // MARK: - Public Methods

    /// Start collecting stats from the peer connection
    /// - Parameter pc: The peer connection to monitor
    func startCollecting(pc: RTCPeerConnection) {
        guard !isCollecting else { return }

        peerConnection = pc
        isCollecting = true

        collectionTask = Task { [weak self] in
            while !Task.isCancelled && self?.isCollecting == true {
                self?.collectStats()
                try? await Task.sleep(nanoseconds: UInt64(Constants.collectionInterval * 1_000_000_000))
            }
        }
    }

    /// Stop collecting stats
    func stopCollecting() {
        isCollecting = false
        collectionTask?.cancel()
        collectionTask = nil
        peerConnection = nil
    }

    // MARK: - Private Methods

    private func collectStats() {
        guard let pc = peerConnection else { return }

        pc.statistics { [weak self] reports in
            guard let self = self else { return }
            let statsReport = self.parseStatsReport(reports: reports)
            self.statsReportSubject.send(statsReport)
        }
    }

    private func parseStatsReport(reports: [RTCLegacyStatsReport]) -> RTCStatsReport {
        var rtt = 0.0
        var packetLoss = 0.0
        var bytesReceived: Int64 = 0
        var bytesSent: Int64 = 0
        var framesDecoded: Int64 = 0
        var framesEncoded: Int64 = 0
        var currentBitrate = 0.0
        var resolutionWidth = 0
        var resolutionHeight = 0

        for report in reports {
            switch report.type {
            case "googCandidatePair":
                // Extract RTT from active candidate pair
                if let rttValue = report.values["googRtt"] as? Double {
                    rtt = rttValue
                }
            case "googLibjingleSession":
                // Extract RTT alternative
                if let rttValue = report.values["googRtt"] as? Double {
                    rtt = rttValue
                }
            case "ssrc":
                // Extract receiver metrics
                if let packetsLost = report.values["packetsLost"] as? Int64,
                   let packetsReceived = report.values["packetsReceived"] as? Int64 {
                    let total = Double(packetsLost + packetsReceived)
                    if total > 0 {
                        packetLoss = (Double(packetsLost) / total) * 100
                    }
                }

                if let bytesRecv = report.values["bytesReceived"] as? Int64 {
                    bytesReceived = bytesRecv
                }
                if let bytesSentValue = report.values["bytesSent"] as? Int64 {
                    bytesSent = bytesSentValue
                }

                if let framesDec = report.values["framesDecoded"] as? Int64 {
                    framesDecoded = framesDec
                }
                if let framesEnc = report.values["framesEncoded"] as? Int64 {
                    framesEncoded = framesEnc
                }

                // Extract video resolution
                if let width = report.values["googFrameWidthReceived"] as? Int {
                    resolutionWidth = width
                }
                if let height = report.values["googFrameHeightReceived"] as? Int {
                    resolutionHeight = height
                }
            default:
                break
            }
        }

        return RTCStatsReport(
            timestamp: Date().timeIntervalSince1970 * 1000,
            rtt: rtt,
            packetLoss: packetLoss,
            bitrate: currentBitrate,
            resolutionWidth: resolutionWidth,
            resolutionHeight: resolutionHeight,
            bytesReceived: bytesReceived,
            bytesSent: bytesSent,
            framesDecoded: framesDecoded,
            framesEncoded: framesEncoded
        )
    }
}

// MARK: - RTC Stats Report

/// Data class representing RTC statistics report
struct RTCStatsReport {
    let timestamp: Double        // Timestamp in milliseconds
    let rtt: Double               // Round-trip time in milliseconds
    let packetLoss: Double        // Packet loss percentage
    let bitrate: Double           // Current bitrate in bps
    let resolutionWidth: Int      // Video width
    let resolutionHeight: Int     // Video height
    let bytesReceived: Int64      // Total bytes received
    let bytesSent: Int64          // Total bytes sent
    let framesDecoded: Int64      // Total frames decoded
    let framesEncoded: Int64      // Total frames encoded

    /// Calculate quality score (0-100) based on metrics
    func calculateQualityScore() -> Int {
        var score = 100

        // RTT penalty (excellent < 50ms, good < 100ms, fair < 200ms, poor >= 200ms)
        switch rtt {
        case 0..<50:
            score -= 0
        case 50..<100:
            score -= 10
        case 100..<200:
            score -= 30
        default:
            score -= 50
        }

        // Packet loss penalty (excellent < 1%, good < 3%, fair < 5%, poor >= 5%)
        switch packetLoss {
        case 0..<1.0:
            score -= 0
        case 1.0..<3.0:
            score -= 10
        case 3.0..<5.0:
            score -= 20
        default:
            score -= 40
        }

        // Bitrate quality (excellent > 1Mbps, good > 500kbps, fair > 250kbps, poor <= 250kbps)
        switch bitrate {
        case 1_000_000...:
            score -= 0
        case 500_000..<1_000_000:
            score -= 5
        case 250_000..<500_000:
            score -= 15
        default:
            score -= 25
        }

        return max(score, 0)
    }

    /// Get quality state based on score
    func getQualityState() -> QualityState {
        let score = calculateQualityScore()
        switch score {
        case 85...:
            return .excellent
        case 70..<85:
            return .good
        case 50..<70:
            return .fair
        default:
            return .poor
        }
    }
}

// MARK: - Quality State

/// Quality state enum
enum QualityState {
    case excellent
    case good
    case fair
    case poor

    var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }

    var color: String {
        switch self {
        case .excellent: return "#4CAF50"  // Green
        case .good: return "#8BC34A"       // Light Green
        case .fair: return "#FF9800"       // Orange
        case .poor: return "#F44336"       // Red
        }
    }
}
