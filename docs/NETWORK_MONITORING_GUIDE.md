# Network Monitoring Guide

## Overview

Milestone 4에서 구현된 네트워크 모니터링 시스템은 WebRTC 연결의 품질을 실시간으로 추적하고 사용자에게 시각적 피드백을 제공합니다.

## Architecture

### Components

1. **RTCStatsCollector**: WebRTC RTCStats API를 사용하여 통계 수집
2. **QualityMetricsCollector**: 품질 점수 계산 (0-100)
3. **QualityMetricsOverlay**: 색상 코딩된 UI 표시

### Data Flow

```
WebRTC API → RTCStatsCollector → Quality Score → UI Display
```

## Android Implementation

### RTCStatsCollector.kt

```kotlin
class RTCStatsCollector(
    private val peerConnection: PeerConnection
) {
    private val _metrics = MutableStateFlow<QualityMetrics>(QualityMetrics())
    val metrics: StateFlow<QualityMetrics> = _metrics.asStateFlow()

    private var collectionJob: Job? = null

    fun start() {
        collectionJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive) {
                collectStats()
                delay(1000) // 1초 간격
            }
        }
    }

    fun stop() {
        collectionJob?.cancel()
    }

    private suspend fun collectStats() {
        peerConnection.getStats { report ->
            val rtt = extractRTT(report)
            val packetLoss = calculatePacketLoss(report)
            val bitrate = calculateBitrate(report)
            val qualityScore = calculateQualityScore(rtt, packetLoss, bitrate)
            val qualityState = determineQualityState(qualityScore)

            _metrics.update { current ->
                current.copy(
                    rtt = rtt,
                    packetLoss = packetLoss,
                    bitrate = bitrate,
                    qualityScore = qualityScore,
                    qualityState = qualityState
                )
            }
        }
    }
}
```

### Integration in CallViewModel

```kotlin
@HiltViewModel
class CallViewModel @Inject constructor(
    private val peerConnectionManager: PeerConnectionManager
) : ViewModel() {

    private val statsCollector = RTCStatsCollector(
        peerConnectionManager.peerConnection
    )

    val qualityMetrics: StateFlow<QualityMetrics> = statsCollector.metrics

    fun startCall(roomId: String) {
        // WebRTC 연결 설정
        peerConnectionManager.initialize()
        statsCollector.start()
    }

    fun endCall() {
        statsCollector.stop()
        peerConnectionManager.close()
    }
}
```

### QualityMetricsOverlay UI

```kotlin
@Composable
fun QualityMetricsOverlay(
    metrics: QualityMetrics,
    onDismiss: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
    ) {
        Card(
            modifier = Modifier.align(Alignment.TopEnd),
            colors = CardDefaults.cardColors(
                containerColor = Color.Black.copy(alpha = 0.7f)
            )
        ) {
            Column(
                modifier = Modifier.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                QualityMetricRow("RTT", "${metrics.rtt}ms", metrics.rttColor)
                QualityMetricRow("Packet Loss", "${metrics.packetLoss}%", metrics.packetLossColor)
                QualityMetricRow("Bitrate", "${metrics.bitrate}Kbps", metrics.bitrateColor)
                Divider()
                QualityScoreDisplay(metrics.qualityScore, metrics.qualityState)
            }
        }
    }
}
```

## iOS Implementation

### RTCStatsCollector.swift

```swift
class RTCStatsCollector {
    private let peerConnection: RTCPeerConnection
    private var timer: Timer?
    @Published private(set) var metrics: QualityMetrics = QualityMetrics()

    init(peerConnection: RTCPeerConnection) {
        self.peerConnection = peerConnection
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectStats()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func collectStats() {
        peerConnection.statistics { [weak self] report in
            guard let self = self else { return }

            let rtt = self.extractRTT(from: report)
            let packetLoss = self.calculatePacketLoss(from: report)
            let bitrate = self.calculateBitrate(from: report)
            let qualityScore = self.calculateQualityScore(
                rtt: rtt,
                packetLoss: packetLoss,
                bitrate: bitrate
            )
            let qualityState = self.determineQualityState(score: qualityScore)

            DispatchQueue.main.async {
                self.metrics = QualityMetrics(
                    rtt: rtt,
                    packetLoss: packetLoss,
                    bitrate: bitrate,
                    qualityScore: qualityScore,
                    qualityState: qualityState
                )
            }
        }
    }
}
```

### Integration in CallViewModel

```swift
class CallViewModel: ObservableObject {
    @Published var qualityMetrics: QualityMetrics = QualityMetrics()
    private let statsCollector: RTCStatsCollector

    init(peerConnectionManager: PeerConnectionManager) {
        self.statsCollector = RTCStatsCollector(
            peerConnection: peerConnectionManager.peerConnection
        )

        // Combine을 사용한 메트릭 업데이트
        statsCollector.$metrics
            .assign(to: &$qualityMetrics)
    }

    func startCall(roomId: String) {
        peerConnectionManager.initialize()
        statsCollector.start()
    }

    func endCall() {
        statsCollector.stop()
        peerConnectionManager.close()
    }
}
```

### QualityMetricsOverlay UI

```swift
struct QualityMetricsOverlay: View {
    let metrics: QualityMetrics
    var onDismiss: () -> Void

    var body: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    QualityMetricRow(label: "RTT", value: "\(metrics.rtt)ms", color: metrics.rttColor)
                    QualityMetricRow(label: "Packet Loss", value: "\(metrics.packetLoss)%", color: metrics.packetLossColor)
                    QualityMetricRow(label: "Bitrate", value: "\(metrics.bitrate)Kbps", color: metrics.bitrateColor)
                    Divider()
                    QualityScoreDisplay(score: metrics.qualityScore, state: metrics.qualityState)
                }
                .padding(12)
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)
                .padding()
            }
            Spacer()
        }
    }
}
```

## Quality Score Calculation

### Algorithm

품질 점수는 세 가지 메트릭의 가중 평균으로 계산됩니다:

```kotlin
fun calculateQualityScore(rtt: Int, packetLoss: Double, bitrate: Int): Int {
    val rttScore = when {
        rtt < 50 -> 25
        rtt < 100 -> 18
        rtt < 200 -> 10
        else -> 5
    }

    val packetLossScore = when {
        packetLoss < 1.0 -> 40
        packetLoss < 3.0 -> 30
        packetLoss < 5.0 -> 20
        else -> 10
    }

    val bitrateScore = when {
        bitrate > 1000 -> 35
        bitrate > 500 -> 25
        bitrate > 250 -> 15
        else -> 5
    }

    return (rttScore + packetLossScore + bitrateScore).coerceIn(0, 100)
}
```

### Quality States

| Score | State | Color | Description |
|-------|-------|-------|-------------|
| 85-100 | EXCELLENT | Green | 최적 연결 상태 |
| 70-84 | GOOD | Light Green | 양호한 연결 상태 |
| 50-69 | FAIR | Orange | 보통 연결 상태 |
| 0-49 | POOR | Red | 나쁜 연결 상태 |

## Metric Extraction

### RTT (Round Trip Time)

```kotlin
private fun extractRTT(report: RTCStatsReport): Int {
    val stats = report.statsMap.values.firstOrNull {
        it.type == "candidate-pair" && it.members.containsKey("roundTripTime")
    }
    return stats?.members?.get("roundTripTime")?.toString()?.toDouble()?.toInt() ?: 0
}
```

### Packet Loss

```kotlin
private fun calculatePacketLoss(report: RTCStatsReport): Double {
    val inbound = report.statsMap.values.firstOrNull {
        it.type == "inbound-rtp"
    }

    val packetsReceived = inbound?.members?.get("packetsReceived")?.toString()?.toDouble() ?: 0.0
    val packetsLost = inbound?.members?.get("packetsLost")?.toString()?.toDouble() ?: 0.0
    val packetsTotal = packetsReceived + packetsLost

    return if (packetsTotal > 0) {
        (packetsLost / packetsTotal) * 100
    } else {
        0.0
    }
}
```

### Bitrate

```kotlin
private fun calculateBitrate(report: RTCStatsReport): Int {
    val inbound = report.statsMap.values.firstOrNull {
        it.type == "inbound-rtp"
    }

    val bytesReceived = inbound?.members?.get("bytesReceived")?.toString()?.toDouble() ?: 0.0
    val prevBytes = previousBytes.get() ?: 0.0

    if (prevBytes > 0) {
        val bytesPerSecond = (bytesReceived - prevBytes) / 1.0 // 1초 간격
        previousBytes.set(bytesReceived)
        return ((bytesPerSecond * 8) / 1000).toInt() // Kbps
    }

    previousBytes.set(bytesReceived)
    return 0
}
```

## Performance Considerations

### Collection Interval

- **Recommended**: 1 second
- **Minimum**: 500ms
- **Maximum**: 5 seconds

너무 자주 수집하면 배터리와 CPU 사용량이 증가할 수 있습니다.

### Memory Usage

- In-memory buffer: 최대 100개 샘플
- 약 10KB의 메모리 사용
- 자동으로 오래된 샘플 정리

### Battery Impact

- 1초 간격: 약 1-2% 배터리 사용/시간
- 5초 간격: 약 0.5% 배터리 사용/시간

## Troubleshooting

### Stats Not Updating

**문제**: 메트릭이 업데이트되지 않음

**해결**:
1. RTCStatsCollector가 시작되었는지 확인
2. PeerConnection이 연결되었는지 확인
3. 적절한 권한이 있는지 확인

### Incorrect Quality Scores

**문제**: 품질 점수가 실제 연결 품질과 다름

**해결**:
1. WebRTC 버전 확인 (최신 버전 권장)
2. stats 수집 간격 확인
3. 메트릭 추출 로그 확인

## Best Practices

1. **통화 시작 시 수집 시작**: `start()`를 연결 설정 후 호출
2. **통화 종료 시 수집 중지**: `stop()`을 세션 정리 전 호출
3. **UI 업데이트 최적화**: StateFlow/@Published 사용으로 자동 업데이트
4. **배터리 최적화**: 필요할 때만 수집 활성화
5. **사용자 피드백**: 품질 저하 시 사용자에게 알림

## API Reference

### RTCStatsCollector (Android)

| Method | Description |
|--------|-------------|
| `start()` | stats 수집 시작 |
| `stop()` | stats 수집 중지 |
| `metrics: StateFlow<QualityMetrics>` | 메트릭 스트림 |

### RTCStatsCollector (iOS)

| Method | Description |
|--------|-------------|
| `start()` | stats 수집 시작 |
| `stop()` | stats 수집 중지 |
| `@Published metrics: QualityMetrics` | 메트릭 프로퍼티 |

---

**버전**: 1.0.0
**마지막 업데이트**: 2026-01-19
