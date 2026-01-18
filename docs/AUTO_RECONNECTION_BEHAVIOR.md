# Auto-Reconnection Behavior Guide

## Overview

Milestone 4에서 구현된 자동 재연결 시스템은 WebRTC 연결 실패 시 자동으로 재연결을 시도하여 통화 품질과 안정성을 향상시킵니다.

## Architecture

### Components

1. **ReconnectionManager**: 재연결 상태 머신 관리
2. **FailureClassifier**: 연결 실패 유형 분류
3. **BackoffStrategy**: 지수 백오프 계산

### State Machine

```
STABLE → RECONNECTING → STABLE (성공)
                    ↘ FAILED (실패)
```

## Android Implementation

### ReconnectionManager.kt

```kotlin
class ReconnectionManager {
    private val _state = MutableStateFlow(ReconnectionState.STABLE)
    val state: StateFlow<ReconnectionState> = _state.asStateFlow()

    private val _retryCount = MutableStateFlow(0)
    val retryCount: StateFlow<Int> = _retryCount.asStateFlow()

    private val maxRetries = 3
    private val backoffDelays = listOf(1000L, 2000L, 4000L) // 1s, 2s, 4s

    fun handleMinorFailure() {
        when (state.value) {
            ReconnectionState.STABLE -> {
                _state.update { ReconnectionState.RECONNECTING }
                executeReconnection(ReconnectionStrategy.ICE_RESTART)
            }
            else -> {
                // 이미 재연결 중
            }
        }
    }

    fun handleMajorFailure() {
        when (state.value) {
            ReconnectionState.STABLE -> {
                _state.update { ReconnectionState.RECONNECTING }
                executeReconnection(ReconnectionStrategy.FULL_RECONNECTION)
            }
            else -> {
                // 이미 재연결 중
            }
        }
    }

    fun handleFatalFailure() {
        _state.update { ReconnectionState.FAILED }
        _retryCount.update { 0 }
    }

    fun onReconnectionSuccess() {
        _state.update { ReconnectionState.STABLE }
        _retryCount.update { 0 }
    }

    fun onReconnectionFailed() {
        val currentCount = _retryCount.value
        if (currentCount < maxRetries) {
            _retryCount.update { it + 1 }
            scheduleNextRetry()
        } else {
            _state.update { ReconnectionState.FAILED }
        }
    }

    private fun scheduleNextRetry() {
        val delay = backoffDelays[_retryCount.value]
        CoroutineScope(Dispatchers.IO).launch {
            delay(delay)
            executeReconnection(ReconnectionStrategy.FULL_RECONNECTION)
        }
    }

    fun canReconnect(): Boolean {
        return state.value == ReconnectionState.STABLE ||
               (state.value == ReconnectionState.RECONNECTING &&
                _retryCount.value < maxRetries)
    }

    fun reset() {
        _state.update { ReconnectionState.STABLE }
        _retryCount.update { 0 }
    }
}
```

### Integration in CallViewModel

```kotlin
@HiltViewModel
class CallViewModel @Inject constructor(
    private val webRTCRepository: WebRTCRepository,
    private val reconnectionManager: ReconnectionManager
) : ViewModel() {

    init {
        // 재연결 상태 관찰
        viewModelScope.launch {
            reconnectionManager.state.collect { state ->
                when (state) {
                    ReconnectionState.STABLE -> {
                        _callState.update { it.copy(isReconnecting = false) }
                    }
                    ReconnectionState.RECONNECTING -> {
                        _callState.update { it.copy(isReconnecting = true) }
                    }
                    ReconnectionState.FAILED -> {
                        _callState.update {
                            it.copy(
                                isReconnecting = false,
                                errorMessage = "Connection failed after multiple attempts"
                            )
                        }
                    }
                }
            }
        }
    }

    fun handleConnectionFailure(error: WebRTCException) {
        when {
            error.isMinor() -> {
                reconnectionManager.handleMinorFailure()
            }
            error.isMajor() -> {
                reconnectionManager.handleMajorFailure()
            }
            error.isFatal() -> {
                reconnectionManager.handleFatalFailure()
            }
        }
    }
}
```

## iOS Implementation

### ReconnectionManager.swift

```swift
class ReconnectionManager: ObservableObject {
    @Published private(set) var state: ReconnectionState = .stable
    @Published private(set) var retryCount: Int = 0

    private let maxRetries = 3
    private let backoffDelays: [TimeInterval] = [1.0, 2.0, 4.0] // 1s, 2s, 4s
    private var retryWorkItem: DispatchWorkItem?

    func handleMinorFailure() {
        switch state {
        case .stable:
            state = .reconnecting
            executeReconnection(strategy: .iceRestart)
        default:
            break
        }
    }

    func handleMajorFailure() {
        switch state {
        case .stable:
            state = .reconnecting
            executeReconnection(strategy: .fullReconnection)
        default:
            break
        }
    }

    func handleFatalFailure() {
        state = .failed
        retryCount = 0
    }

    func onReconnectionSuccess() {
        state = .stable
        retryCount = 0
    }

    func onReconnectionFailed() {
        if retryCount < maxRetries {
            retryCount += 1
            scheduleNextRetry()
        } else {
            state = .failed
        }
    }

    private func scheduleNextRetry() {
        let delay = backoffDelays[retryCount]
        let workItem = DispatchWorkItem { [weak self] in
            self?.executeReconnection(strategy: .fullReconnection)
        }
        retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func canReconnect() -> Bool {
        return state == .stable ||
               (state == .reconnecting && retryCount < maxRetries)
    }

    func reset() {
        state = .stable
        retryCount = 0
        retryWorkItem?.cancel()
        retryWorkItem = nil
    }
}
```

### Integration in CallViewModel

```swift
class CallViewModel: ObservableObject {
    @Published var isReconnecting = false
    @Published var errorMessage: String?

    private let reconnectionManager: ReconnectionManager

    init(peerConnectionManager: PeerConnectionManager) {
        self.reconnectionManager = ReconnectionManager()

        // 재연결 상태 관찰
        reconnectionManager.$state
            .sink { [weak self] state in
                switch state {
                case .stable:
                    self?.isReconnecting = false
                case .reconnecting:
                    self?.isReconnecting = true
                case .failed:
                    self?.isReconnecting = false
                    self?.errorMessage = "Connection failed after multiple attempts"
                }
            }
            .store(in: &cancellables)
    }

    func handleConnectionFailure(error: Error) {
        switch error.severity {
        case .minor:
            reconnectionManager.handleMinorFailure()
        case .major:
            reconnectionManager.handleMajorFailure()
        case .fatal:
            reconnectionManager.handleFatalFailure()
        }
    }
}
```

## Failure Classification

### Minor Failures

ICE 연결 문제가 발생했지만 PeerConnection은 유효한 경우

**Examples**:
- 일시적인 네트워크 혼잡
- ICE 후보 실패
- STUN 요청 타임아웃

**Strategy**: ICE Restart
- 기존 PeerConnection 유지
- 새로운 ICE offer 생성
- ICE 후보 재수집

### Major Failures

PeerConnection이 복구 불가능한 상태인 경우

**Examples**:
- PeerConnection closed
- ICE 연결 실패
- SDP 교환 실패

**Strategy**: Full Reconnection
- 기존 PeerConnection 폐기
- 새로운 PeerConnection 생성
- 전체 WebRTC 협상 재실행

### Fatal Failures

복구 불가능한 치명적인 오류

**Examples**:
- 사용자 인증 실패
- 서버 오류 (5xx)
- 앱 권한 거부

**Strategy**: No Recovery
- 재연결 시도 중단
- 사용자에게 오류 표시
- 수동 재연결 요구

## Exponential Backoff

### Backoff Delays

| Retry Attempt | Delay | Total Time |
|--------------|-------|------------|
| 1st attempt | 1s | 1s |
| 2nd attempt | 2s | 3s |
| 3rd attempt | 4s | 7s |
| After 3 attempts | Failed | - |

### Rationale

- **1st delay (1s)**: 빠른 복구 시도
- **2nd delay (2s)**: 네트워크 안정화 대기
- **3rd delay (4s)**: 충분한 복구 시간 제공
- **Max 3 attempts**: 사용자 경험과 안정성 균형

## Reconnection Strategies

### ICE Restart

```kotlin
fun executeIceRestart() {
    // 기존 PeerConnection 유지
    peerConnection.createOffer({ offer ->
        // ICE restart 옵션 설정
        val restartOffer = SessionDescription(
            SessionDescription.Type.OFFER,
            offer.description.replace("a=group:BUNDLE", "a=group:BUNDLE\r\na=ice-options:trickle")
        )
        peerConnection.setLocalDescription(restartOffer)
        signalingClient.sendOffer(restartOffer)
    }, MediaConstraints())
}
```

### Full Reconnection

```kotlin
fun executeFullReconnection() {
    // 기존 연결 정리
    peerConnection.close()

    // 새로운 PeerConnection 생성
    peerConnection = createPeerConnection()

    // 전체 협상 재실행
    createOffer()
}
```

## UI Feedback

### Android

```kotlin
@Composable
fun CallScreen(viewModel: CallViewModel) {
    val isReconnecting by viewModel.isReconnecting.collectAsState()
    val retryCount by viewModel.retryCount.collectAsState()

    Box {
        VideoCallContent()

        if (isReconnecting) {
            ReconnectionIndicator(
                retryCount = retryCount,
                maxRetries = 3
            )
        }
    }
}

@Composable
fun ReconnectionIndicator(retryCount: Int, maxRetries: Int) {
    Card(
        modifier = Modifier.align(Alignment.Center),
        colors = CardDefaults.cardColors(
            containerColor = Color.Black.copy(alpha = 0.8f)
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            CircularProgressIndicator(color = Color.White)
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Reconnecting... ($retryCount/$maxRetries)",
                color = Color.White
            )
        }
    }
}
```

### iOS

```swift
struct CallView: View {
    @ObservedObject var viewModel: CallViewModel

    var body: some View {
        ZStack {
            VideoCallContent()

            if viewModel.isReconnecting {
                ReconnectionIndicator(
                    retryCount: viewModel.retryCount,
                    maxRetries: 3
                )
            }
        }
    }
}

struct ReconnectionIndicator: View {
    let retryCount: Int
    let maxRetries: Int

    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
            Text("Reconnecting... (\(retryCount)/\(maxRetries))")
                .foregroundColor(.white)
                .padding(.top, 8)
        }
        .padding(16)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }
}
```

## Best Practices

1. **실패 분류**: 정확한 실패 유형 분류로 적절한 전략 선택
2. **사용자 피드백**: 재연결 시도 중 사용자에게 알림
3. **타임아웃 관리**: 적절한 타임아웃 설정으로 무한 대기 방지
4. **상태 동기화**: UI와 백엔드 상태 동기화 유지
5. **로그 기록**: 재연결 시도 로그로 디버깅 용이

## Troubleshooting

### 연결이 계속 실패함

**문제**: 3회 재시도 후 연결 실패

**해결**:
1. 네트워크 연결 확인
2. TURN 서버 상태 확인
3. Firebase Firestore 접속 확인
4. 방화벽/포트 설정 확인

### 재연결이 너무 느림

**문제**: 재연결 시간이 너무 김

**해결**:
1. 백오프 딜레이 조정
2. ICE timeout 줄이기
3. 네트워크 모니터링으로 품질 확인

### 무한 재연결 루프

**문제**: 재연결이 멈추지 않음

**해결**:
1. maxRetries 설정 확인
2. Fatal failure 조건 확인
3. 타임아웃 설정 추가

## API Reference

### ReconnectionManager (Android)

| Method | Description |
|--------|-------------|
| `handleMinorFailure()` | Minor failure 처리 (ICE restart) |
| `handleMajorFailure()` | Major failure 처리 (Full reconnection) |
| `handleFatalFailure()` | Fatal failure 처리 (No recovery) |
| `onReconnectionSuccess()` | 재연결 성공 시 호출 |
| `onReconnectionFailed()` | 재연결 실패 시 호출 |
| `canReconnect(): Boolean` | 재연결 가능 여부 확인 |
| `reset()` | 재연결 상태 초기화 |

### ReconnectionManager (iOS)

| Method | Description |
|--------|-------------|
| `handleMinorFailure()` | Minor failure 처리 (ICE restart) |
| `handleMajorFailure()` | Major failure 처리 (Full reconnection) |
| `handleFatalFailure()` | Fatal failure 처리 (No recovery) |
| `onReconnectionSuccess()` | 재연결 성공 시 호출 |
| `onReconnectionFailed()` | 재연결 실패 시 호출 |
| `canReconnect() -> Bool` | 재연결 가능 여부 확인 |
| `reset()` | 재연결 상태 초기화 |

---

**버전**: 1.0.0
**마지막 업데이트**: 2026-01-19
