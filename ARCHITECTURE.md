# WebRTC-Lite Architecture

## 목차

- [시스템 개요](#시스템-개요)
- [아키텍처 원칙](#아키텍처-원칙)
- [시스템 구성 요소](#시스템-구성-요소)
- [데이터 흐름](#데이터-흐름)
- [고급 기능 아키텍처](#고급-기능-아키텍처)
- [보안 아키텍처](#보안-아키텍처)
- [확장성 전략](#확장성-전략)
- [기술 스택](#기술-스택)

---

## 시스템 개요

WebRTC-Lite는 비용 효율적인 하이브리드 WebRTC 인프라 솔루션으로, Firebase Firestore의 시그널링과 Oracle Cloud Free Tier의 TURN/STUN 서버를 결합하여 월 $0 비용으로 실시간 통신을 제공합니다.

### 핵심 목표

1. **비용 효율성**: Oracle Cloud Free Tier와 Firebase Free Tier 활용
2. **간단한 배포**: 자동화 스크립트로 10분 내 구축 가능
3. **크로스 플랫폼**: Android와 iOS 지원
4. **보안**: HMAC-SHA1 기반 동적 자격 증명 및 Firestore 보안 규칙

---

## 아키텍처 원칙

### 1. 비용 최적화 (Cost Optimization)

- Oracle Cloud Free Tier 활용 (월 10TB 트래픽)
- Firebase Free Tier 활용 (일일 50K 읽기, 20K 쓰기)
- 트래픽 패턴에 따른 자동 리소스 조정

### 2. 단순성 (Simplicity)

- 관리형 서비스 최대 활용 (Firebase)
- 최소한의 자체 인프라 (Coturn만 자체 호스팅)
- 선언적 구성 (Terraform)

### 3. 보안 (Security)

- 시간 기반 자격 증명 (TTL: 60-86400초)
- Firestore 보안 규칙으로 참여자만 접근
- TLS 1.3 암호화

### 4. 확장성 (Scalability)

- 무료 티어에서 유료 티어로 원활한 전환
- 상태 비저장 API 설계
- 수평적 확장 가능

---

## 시스템 구성 요소

### C4 Context Diagram

```mermaid
C4Context
    title WebRTC-Lite System Context

    Person(caller, "Caller", "WebRTC 사용자")
    Person(callee, "Callee", "WebRTC 사용자")

    System(webrtc_lite, "WebRTC-Lite", "비용 효율적인 WebRTC 인프라")

    System_Ext(firebase, "Firebase Firestore", "시그널링 서비스")
    System_Ext(oracle, "Oracle Cloud", "TURN/STUN 서버")

    Rel(caller, webrtc_lite, "1:1 통화", "HTTPS/WebSocket")
    Rel(callee, webrtc_lite, "1:1 통화", "HTTPS/WebSocket")
    Rel(webrtc_lite, firebase, "SDP 교환", "Firestore SDK")
    Rel(webrtc_lite, oracle, "미디어 릴레이", "TURN/STUN")
```

### C4 Container Diagram

```mermaid
C4Container
    title WebRTC-Lite Container Diagram

    Person(user, "모바일 사용자")

    Container(client_android, "Android Client", "Kotlin", "WebRTC 클라이언트 앱")
    Container(client_ios, "iOS Client", "Swift", "WebRTC 클라이언트 앱")

    ContainerDb(firestore, "Firebase Firestore", "NoSQL Document DB", "시그널링 데이터 저장")
    Container(turn_api, "TURN Credentials API", "FastAPI", "TURN 자격 증명 발급")
    Container(turn_server, "Coturn TURN Server", "C/Ubuntu", "미디어 릴레이")

    Container_Monitoring(prometheus, "Prometheus", "Metrics Collection")

    Rel(user, client_android, "사용")
    Rel(user, client_ios, "사용")

    Rel(client_android, firestore, "시그널링 (Offer/Answer/ICE)")
    Rel(client_ios, firestore, "시그널링 (Offer/Answer/ICE)")

    Rel(client_android, turn_api, "자격 증명 요청", "REST")
    Rel(client_ios, turn_api, "자격 증명 요청", "REST")

    Rel(turn_api, turn_server, "자격 증명 생성", "HMAC-SHA1")

    Rel(client_android, turn_server, "미디어 릴레이", "TURN/STUN")
    Rel(client_ios, turn_server, "미디어 릴레이", "TURN/STUN")

    Rel(turn_server, prometheus, "메트릭 전송")
```

### Coturn TURN Server 상세

```mermaid
graph TB
    subgraph "Oracle Cloud Infrastructure"
        subgraph "Coturn TURN Server"
            A[STUN Service<br/>Port 3478/3479]
            B[TURN Service<br/>Port 3478/3479]
            C[TURNS Service<br/>Port 5349/5350]
            D[Authentication<br/>HMAC-SHA1]
            E[Relay Engine<br/>UDP/TCP]
        end

        subgraph "Security Layer"
            F[iptables<br/>Firewall]
            G[fail2ban<br/>DDoS Protection]
        end

        subgraph "Monitoring"
            H[monitor.sh<br/>Health Check]
            I[Prometheus<br/>Metrics]
        end
    end

    A --> D
    B --> D
    C --> D
    D --> E

    F --> A
    F --> B
    F --> C
    G --> F

    E --> I
    H --> A
    H --> B
    H --> C
```

### Firebase Firestore 구조

```mermaid
erDiagram
    webrtc_sessions ||--o{ ice_candidates : contains
    webrtc_sessions {
        string session_id PK
        string caller_id FK
        string callee_id FK
        string status "pending|offered|answered|connected|ended"
        timestamp created_at
        timestamp updated_at
        object offer "SDP Offer"
        object answer "SDP Answer"
        object turn_credentials "TURN credentials"
        object error "Error info"
    }

    ice_candidates {
        string candidate_id PK
        string session_id FK
        string sender "caller|callee"
        string candidate "ICE candidate string"
        string sdpMid
        number sdpMLineIndex
        timestamp created_at
    }
```

---

## 데이터 흐름

### WebRTC 통화 연결 시퀀스

```mermaid
sequenceDiagram
    participant C as Caller
    participant F as Firebase Firestore
    participant A as TURN API
    participant T as TURN Server
    participant R as Callee

    Note over C,R: 1. 통화 설정
    C->>F: createSession(callee_id)
    C->>A: requestTURNcredentials(username)
    A->>T: generate HMAC-SHA1
    T-->>A: return password
    A-->>C: return credentials
    C->>F: storeOffer(SDP)
    F-->>R: notifyNewSession()

    Note over C,R: 2. 응답
    R->>F: readOffer(SDP)
    R->>A: requestTURNcredentials(username)
    A-->>R: return credentials
    R->>F: storeAnswer(SDP)
    F-->>C: notifyAnswer()

    Note over C,R: 3. ICE 연결
    loop ICE Exchange
        C->>F: sendICECandidate()
        F-->>R: notifyICECandidate()
        R->>F: sendICECandidate()
        F-->>C: notifyICECandidate()
    end

    Note over C,R: 4. P2P 또는 TURN 연결
    C->>T: TURN allocate (if needed)
    R->>T: TURN allocate (if needed)
    C-->>R: Direct or Relayed Media
```

### TURN 자격 증명 발급 흐름

```mermaid
flowchart TD
    A[Client Request] --> B{API Key Valid?}
    B -->|No| C[401 Unauthorized]
    B -->|Yes| D{Username Valid?}
    D -->|No| E[400 Bad Request]
    D -->|Yes| F{TTL Valid?}
    F -->|No| G[400 Bad Request]
    F -->|Yes| H[Generate Timestamp]
    H --> I[Create username:timestamp]
    I --> J[Generate HMAC-SHA1]
    J --> K[Build URIs]
    K --> L[Return Credentials]

    style A fill:#e1f5e1
    style L fill:#e1f5e1
    style C fill:#f5e1e1
    style E fill:#f5e1e1
    style G fill:#f5e1e1
```

### 시그널링 데이터 흐름

```mermaid
flowchart LR
    subgraph "Caller Side"
        A1[WebRTC Client] --> A2[Firestore SDK]
    end

    subgraph "Firebase Cloud"
        B1[Firestore Database]
        B2[Security Rules]
        B3[Realtime Listeners]
    end

    subgraph "Callee Side"
        C1[Firestore SDK] --> C2[WebRTC Client]
    end

    A2 -->|Offer| B1
    B1 -->|Security Check| B2
    B2 -->|Allowed| B3
    B3 -->|Notify| C1
    C1 -->|Read Offer| C2

    C2 -->|Answer| B1
    B1 -->|Security Check| B2
    B2 -->|Allowed| B3
    B3 -->|Notify| A2
    A2 -->|Read Answer| A1

    style B2 fill:#fff3cd
    style B3 fill:#d1ecf1
```

---

## 고급 기능 아키텍처 (Milestone 4)

### 네트워크 모니터링 및 품질 메트릭

Milestone 4에서 구현된 RTCStats 기반 모니터링 시스템입니다.

#### RTCStats Collection Flow

```mermaid
sequenceDiagram
    participant UI as QualityMetricsOverlay
    participant VM as CallViewModel
    participant PC as PeerConnectionManager
    participant SC as RTCStatsCollector
    participant RTC as WebRTC API

    Note over UI,RTC: 매 1초마다 stats 수집

    loop Every 1 second
        SC->>RTC: getStats()
        RTC-->>SC: RTCStatsReport
        SC->>SC: Extract metrics (RTT, packet loss, bitrate)
        SC->>SC: Calculate quality score (0-100)
        SC->>SC: Determine quality state
        SC->>VM: Update quality metrics
        VM->>UI: StateFlow/@Published update
        UI->>UI: Color-coded display
    end
```

#### Quality Score Calculation Algorithm

```mermaid
flowchart TD
    A[RTCStatsCollector receives stats] --> B[Extract RTT]
    A --> C[Extract Packet Loss]
    A --> D[Extract Bitrate]

    B --> E{RTT Score}
    E -->|< 50ms| F[25 points]
    E -->|< 100ms| G[18 points]
    E -->|< 200ms| H[10 points]
    E -->|>= 200ms| I[5 points]

    C --> J{Packet Loss Score}
    J -->|< 1%| K[40 points]
    J -->|< 3%| L[30 points]
    J -->|< 5%| M[20 points]
    J -->|>= 5%| N[10 points]

    D --> O{Bitrate Score}
    O -->|> 1Mbps| P[35 points]
    O -->|> 500Kbps| Q[25 points]
    O -->|> 250Kbps| R[15 points]
    O -->|<= 250Kbps| S[5 points]

    F --> T[Sum: RTT + Loss + Bitrate]
    G --> T
    H --> T
    I --> T
    K --> T
    L --> T
    M --> T
    N --> T
    P --> T
    Q --> T
    R --> T
    S --> T

    T --> U{Quality State}
    U -->|85-100| V[EXCELLENT - Green]
    U -->|70-84| W[GOOD - Light Green]
    U -->|50-69| X[FAIR - Orange]
    U -->|0-49| Y[POOR - Red]
```

### 자동 재연결 상태 머신

#### Reconnection State Machine

```mermaid
stateDiagram-v2
    [*] --> STABLE: 초기화
    STABLE --> RECONNECTING: ICE connection failure

    state RECONNECTING {
        [*] --> Attempt1
        Attempt1 --> Attempt2: 1초 후 실패
        Attempt2 --> Attempt3: 2초 후 실패
        Attempt3 --> FAILED: 4초 후 실패
        Attempt1 --> STABLE: 성공
        Attempt2 --> STABLE: 성공
        Attempt3 --> STABLE: 성공
    }

    RECONNECTING --> STABLE: 재연결 성공
    RECONNECTING --> FAILED: 최대 재시도 도달
    FAILED --> [*]

    note right of STABLE
        정상 연결 상태
        재시도 카운트 = 0
    end note

    note right of RECONNECTING
        Minor: ICE restart
        Major: Full reconnection
        Exponential backoff
    end note

    note right of FAILED
        3회 재시도 실패
        사용자에게 알림 필요
    end note
```

#### Reconnection Strategy Decision

```mermaid
flowchart TD
    A[Connection Failure Detected] --> B{Failure Type}

    B -->|MINOR| C[ICE Restart Strategy]
    B -->|MAJOR| D[Full Reconnection Strategy]
    B -->|FATAL| E[No Recovery]

    C --> F[Keep existing PeerConnection]
    C --> G[Create new offer]
    C --> H[Restart ICE gathering]

    D --> I[Close old PeerConnection]
    D --> J[Create new PeerConnection]
    D --> K[Full renegotiation]

    E --> L[Set state to FAILED]
    E --> M[Notify user]

    H --> N{Retry Limit Reached?}
    K --> N
    N -->|No| O[Increment retry count]
    N -->|Yes| L
    O --> P{Attempt Successful?}
    P -->|Yes| Q[Return to STABLE]
    P -->|No| R[Wait backoff time]
    R --> N

    style C fill:#e1f5e1
    style D fill:#fff3cd
    style E fill:#f5e1e1
    style Q fill:#e1f5e1
    style L fill:#f5e1e1
```

### TURN 자격 증명 캐싱 및 자동 갱신

#### Caching and Auto-Refresh Flow

```mermaid
sequenceDiagram
    participant App as Application
    participant TCS as TurnCredentialService
    participant API as TURN API
    participant Cache as In-Memory Cache

    Note over App,Cache: 앱 시작 시
    App->>TCS: startAutoRefresh()
    TCS->>TCS: Start 60s timer

    loop Every 60 seconds
        TCS->>Cache: Check cached credentials
        Cache-->>TCS: Return cached or null

        alt Cache exists
            TCS->>TCS: Calculate time to expiry
            alt Time to expiry < 5 minutes
                TCS->>API: Request fresh credentials
                API-->>TCS: New credentials
                TCS->>Cache: Update cache
            end
        else Cache empty
            TCS->>API: Request credentials
            API-->>TCS: New credentials
            TCS->>Cache: Store in cache
        end
    end

    Note over App,Cache: 자격 증명 요청 시
    App->>TCS: getCredentials(username)
    TCS->>Cache: Check cache
    Cache-->>TCS: Return cached credentials
    TCS-->>App: Return credentials (fast path)
```

#### Cache State Management

```mermaid
stateDiagram-v2
    [*] --> EMPTY: 초기 상태
    EMPTY --> FETCHING: getCredentials() 호출
    FETCHING --> CACHED: 자격 증명 수신 완료
    CACHED --> REFRESHING: 5분 전 자동 갱신
    REFRESHING --> CACHED: 갱신 성공
    CACHED --> EXPIRED: TTL 만료
    EXPIRED --> FETCHING: 재요청
    CACHED --> [*]: 앱 종료

    note right of CACHED
        자격 증명 사용 가능
        Thread-safe access
        Mutex/NSLock 보호
    end note

    note right of REFRESHING
        백그라운드 갱신 중
        기존 자격 증명 계속 사용
    end note
```

### 백그라운드 상태 처리

#### Android Background Service Lifecycle

```mermaid
stateDiagram-v2
    [*] --> IDLE: 초기 상태
    IDLE --> FOREGROUND: 통화 시작
    FOREGROUND --> FOREGROUND_SERVICE: 백그라운드 전환
    FOREGROUND_SERVICE --> BACKGROUND_TIMEOUT: 5분 타이머 시작

    state BACKGROUND_TIMEOUT {
        [*] --> Warning1: 1분 경과
        Warning1 --> Warning2: 2분 경과
        Warning2 --> Warning3: 3분 경과
        Warning3 --> Warning4: 4분 경과
        Warning4 --> TIMEOUT: 5분 경과
    }

    BACKGROUND_TIMEOUT --> CLEANUP: 타임아웃 도달
    BACKGROUND_TIMEOUT --> FOREGROUND: 포그라운드 복귀

    CLEANUP --> [*]: 세션 종료
    FOREGROUND --> IDLE: 통화 종료

    note right of FOREGROUND_SERVICE
        Foreground Service 실행
        알림 표시 중
        WebRTC 세션 유지
    end note

    note right of CLEANUP
        PeerConnection 정리
        Foreground Service 중지
        알림 제거
    end note
```

#### iOS Background State Handling

```mermaid
stateDiagram-v2
    [*] --> ACTIVE: 앱 활성화
    ACTIVE --> BACKGROUND: didEnterBackground

    state BACKGROUND {
        [*] --> Monitoring: 5분 타이머 시작
        Monitoring --> FOREGROUND_RETURN: willEnterForeground
        Monitoring --> TIMEOUT: 5분 경과
    }

    BACKGROUND --> ACTIVE: 포그라운드 복귀 (타이머 내)
    BACKGROUND --> CLEANUP: 타임아웃 발생

    CLEANUP --> [*]: 세션 정리
    ACTIVE --> [*]: 앱 종료

    note right of Monitoring
        Audio session 활성화
        WebRTC 세션 유지
        VoIP 백그라운드 모드
    end note

    note right of CLEANUP
        PeerConnection close
        Audio session 정리
        상태 초기화
    end note
```

### Advanced Features Integration

```mermaid
graph TB
    subgraph "Advanced Features Layer"
        A[RTCStatsCollector]
        B[ReconnectionManager]
        C[QualityMetricsOverlay]
        D[TurnCredentialService]
        E[WebRTCBackgroundService]
        F[BackgroundStateHandler]
    end

    subgraph "Core WebRTC Layer"
        G[PeerConnectionManager]
        H[CallViewModel]
        I[SignalingRepository]
    end

    subgraph "UI Layer"
        J[CallScreen/CallView]
    end

    A --> G
    B --> H
    C --> J
    D --> I
    E --> H
    F --> H

    A --> C
    B --> G
    D --> D

    style A fill:#d1ecf1
    style B fill:#fff3cd
    style C fill:#e1f5e1
    style D fill:#d4edda
    style E fill:#f8d7da
    style F fill:#f8d7da
```

---

## 보안 아키텍처

### 보안 레이어

```mermaid
graph TB
    subgraph "Client Security"
        A1[Certificate Pinning]
        A2[API Key Obfuscation]
        A3[Firebase Auth]
    end

    subgraph "Transport Security"
        B1[TLS 1.3]
        B2[DTLS]
        B3[HMAC-SHA1]
    end

    subgraph "Server Security"
        C1[Firestore Security Rules]
        C2[iptables Firewall]
        C3[fail2ban]
    end

    subgraph "Data Security"
        D1[Time-based Credentials]
        D2[Session TTL]
        D3[Participant Validation]
    end

    A3 --> B1
    B1 --> B3
    B3 --> C1
    C1 --> D1
    C2 --> B1
    C3 --> C2
```

### Firestore 보안 규칙 구조

```mermaid
flowchart TD
    A[Firestore Request] --> B{Authenticated?}
    B -->|No| C[403 Forbidden]
    B -->|Yes| D{Caller or Callee?}
    D -->|No| E[403 Forbidden]
    D -->|Yes| F{Session Expired?}
    F -->|Yes| G[Allow Delete]
    F -->|No| H{Valid SDP/ICE?}
    H -->|No| I[400 Invalid]
    H -->|Yes| J[Allow Read/Write]

    style C fill:#f5e1e1
    style E fill:#f5e1e1
    style I fill:#f5e1e1
    style G fill:#e1f5e1
    style J fill:#e1f5e1
```

---

## 확장성 전략

### 수평적 확장 (Horizontal Scaling)

```mermaid
graph LR
    subgraph "Current (Free Tier)"
        A1[Single TURN Server]
        A2[Firebase Free Tier]
    end

    subgraph "Scale Up (Paid)"
        B1[Load Balancer]
        B2[TURN Server 1]
        B3[TURN Server 2]
        B4[TURN Server N]
    end

    subgraph "Cloud Services"
        C1[Firebase Paid Tier]
        C2[Redis Cluster<br/>for distributed TURN]
    end

    A1 -.->|Upgrade| B1
    B1 --> B2
    B1 --> B3
    B1 --> B4
    B2 --> C2
    B3 --> C2
    B4 --> C2
    A2 -.->|Upgrade| C1
```

### 비용 최적화 경로

1. **Free Tier (0-100 concurrent users)**
   - Oracle Cloud Free Tier: 1 VM, 10TB bandwidth
   - Firebase Free Tier: 50K reads/day

2. **Growth Tier (100-500 concurrent users)**
   - Oracle Cloud Paid: 2-3 VMs with Load Balancer
   - Firebase Paid Tier: Blaze plan
   - 예상 비용: ~$50-100/월

3. **Production Tier (500+ concurrent users)**
   - Oracle Cloud: 5+ VMs, Auto Scaling
   - Cloudflare for CDN/DDoS protection
   - 예상 비용: ~$200-500/월

---

## 기술 스택

### 인프라 계층

| 컴포넌트 | 기술 | 버전 | 용도 |
|---------|------|------|------|
| Cloud Provider | Oracle Cloud | - | TURN/STUN 서버 호스팅 |
| VM Shape | VM.Standard.E2.1.Micro | - | Free Tier (1 OCPU, 1GB RAM) |
| IaC Tool | Terraform | ~> 5.0 | 인프라 자동화 |
| OS | Ubuntu | 22.04 LTS | 운영 체제 |

### TURN/STUN 계층

| 컴포넌트 | 기술 | 버전 | 용도 |
|---------|------|------|------|
| TURN Server | Coturn | 4.6+ | STUN/TURN 서비스 |
| Authentication | HMAC-SHA1 | - | 시간 기반 자격 증명 |
| TLS Certificate | Let's Encrypt | - | TLS 1.3 암호화 |

### API 계층

| 컴포넌트 | 기술 | 버전 | 용도 |
|---------|------|------|------|
| Web Framework | FastAPI | 0.104+ | REST API |
| Python | Python | 3.12+ | 런타임 |
| ASGI Server | Uvicorn | 0.24+ | API 서버 |

### 시그널링 계층

| 컴포넌트 | 기술 | 버전 | 용도 |
|---------|------|------|------|
| Database | Firebase Firestore | - | 시그널링 데이터 저장 |
| Security | Firestore Security Rules | v2 | 데이터 접근 제어 |
| Indexes | Firestore Indexes | - | 쿼리 최적화 |

### 클라이언트 계층

| 플랫폼 | 언어 | WebRTC 라이브러리 | 상태 |
|--------|------|------------------|------|
| Android | Kotlin | Google WebRTC (1.0+) | ✅ 완료 |
| iOS | Swift | Google WebRTC (1.0+) | ✅ 완료 |

---

## Android Client Architecture (Milestone 2)

### Clean Architecture 계층 구조

```mermaid
graph TB
    subgraph "Presentation Layer"
        A[CallScreen<br/>Jetpack Compose]
        B[CallViewModel<br/>State Management]
        C[CallState & CallUiEvent<br/>UI Models]
    end

    subgraph "Domain Layer"
        D[Use Cases<br/>Business Logic]
        E[WebRTCRepository<br/>Interface]
        F[SignalingRepository<br/>Interface]
    end

    subgraph "Data Layer"
        G[SignalingRepositoryImpl<br/>Firestore Integration]
        H[FirestoreDataSource<br/>Data Source]
        I[TurnCredentialService<br/>TURN Credentials]
        J[NetworkModule<br/>DI Configuration]
    end

    subgraph "WebRTC Core"
        K[PeerConnectionManager<br/>WebRTC Lifecycle]
        L[Google WebRTC Library<br/>Native Implementation]
    end

    A --> B
    B --> C
    B --> D
    D --> E
    D --> F
    G --> E
    G --> H
    I --> H
    G --> K
    K --> L
    J --> G
    J --> I
```

### Android 컴포넌트 상세

#### Presentation Layer
```mermaid
classDiagram
    class CallScreen {
        +Composable() Content
        +onCallClicked()
        +onHangupClicked()
        +onPermissionResult()
    }

    class CallViewModel {
        -callState: StateFlow~CallState~
        -createOfferUseCase: CreateOfferUseCase
        -answerCallUseCase: AnswerCallUseCase
        +onEvent(CallUiEvent)
        +callState: StateFlow~CallState~
    }

    class CallState {
        +isConnected: Boolean
        +isCalling: Boolean
        +localSessionDescription: String?
        +remoteSessionDescription: String?
        +errorMessage: String?
    }

    class CallUiEvent {
        <<sealed class>>
        StartCall(roomId: String)
        AnswerCall()
        EndCall()
    }

    CallViewModel --> CallState
    CallViewModel --> CallUiEvent
    CallScreen --> CallViewModel
```

#### Domain Layer
```mermaid
classDiagram
    class CreateOfferUseCase {
        -repository: WebRTCRepository
        +invoke(roomId: String): Result~SessionDescription~
    }

    class AnswerCallUseCase {
        -repository: WebRTCRepository
        -signalingRepository: SignalingRepository
        +invoke(offer: SessionDescription): Result~Unit~
    }

    class AddIceCandidateUseCase {
        -signalingRepository: SignalingRepository
        +invoke(candidate: IceCandidate): Result~Unit~
    }

    class EndCallUseCase {
        -repository: WebRTCRepository
        +invoke(): Result~Unit~
    }

    class WebRTCRepository {
        <<interface>>
        +createPeerConnection(): PeerConnection
        +createOffer(): Result~SessionDescription~
        +createAnswer(offer): Result~SessionDescription~
        +addIceCandidate(candidate): Result~Unit~
        +close(): Result~Unit~
    }
```

#### Data Layer
```mermaid
classDiagram
    class SignalingRepositoryImpl {
        -firestoreDataSource: FirestoreDataSource
        -turnCredentialService: TurnCredentialService
        +sendOffer(roomId, offer): Result~Unit~
        +sendAnswer(roomId, answer): Result~Unit~
        +sendIceCandidate(roomId, candidate): Result~Unit~
        +observeOffer(roomId): Flow~SessionDescription~
        +observeAnswer(roomId): Flow~SessionDescription~
        +observeIceCandidates(roomId): Flow~IceCandidate~
    }

    class FirestoreDataSource {
        -firestore: FirebaseFirestore
        -collectionReference: CollectionReference
        +getDocument(roomId): Flow~DocumentSnapshot~
        +setOffer(roomId, sdp): Result~Unit~
        +setAnswer(roomId, sdp): Result~Unit~
        +addIceCandidate(roomId, candidate): Result~Unit~
    }

    class TurnCredentialService {
        -apiUrl: String
        -cache: LruCache
        +getCredentials(username): Result~TurnCredentials~
        +refreshCredentials(): Result~Unit~
    }
```

### WebRTC PeerConnection 관리

```mermaid
stateDiagram-v2
    [*] --> Idle: 초기화
    Idle --> CreatingOffer: createOffer()
    CreatingOffer --> OfferCreated: SDP 생성 완료
    OfferCreated --> WaitingForAnswer: Offer 전송 완료
    WaitingForAnswer --> CreatingAnswer: Answer 수신
    CreatingAnswer --> AnswerCreated: SDP 생성 완료
    AnswerCreated --> GatheringCandidates: ICE Gathering 시작
    GatheringCandidates --> Connecting: ICE 후보 교환 중
    Connecting --> Connected: P2P/TURN 연결 성공
    Connected --> Disconnected: 연결 종료
    Disconnected --> [*]: 정리 완료

    OfferCreated --> Disconnected: 타임아웃/거절
    WaitingForAnswer --> Disconnected: 취소
```

### 의존성 주입 (Hilt)

```mermaid
graph LR
    subgraph "Hilt Modules"
        A[AppModule]
        B[NetworkModule]
    end

    subgraph "Singleton Components"
        C[FirebaseFirestore]
        D[TurnCredentialService]
        E[SignalingRepository]
    end

    subgraph "Scoped Components"
        F[PeerConnectionManager]
        G[CallViewModel]
    end

    A --> C
    B --> D
    C --> E
    D --> E
    E --> F
    F --> G
```

### 비동기 처리 (Coroutines + Flow)

```mermaid
sequenceDiagram
    participant UI as CallScreen
    participant VM as CallViewModel
    participant UC as UseCase
    participant Repo as Repository
    participant DS as DataSource
    participant FS as Firestore

    UI->>VM: onEvent(StartCall)
    VM->>UC: invoke(roomId)
    UC->>Repo: createPeerConnection()
    Repo-->>UC: PeerConnection
    UC->>Repo: createOffer()
    Repo->>Repo: WebRTC.createOffer()
    Repo-->>UC: SessionDescription
    UC->>Repo: sendOffer(roomId, sdp)
    Repo->>DS: setOffer(roomId, sdp)
    DS->>FS: firestore.collection(roomId).set()
    FS-->>DS: Success
    DS-->>Repo: Result.Success
    Repo-->>UC: Result.Success
    UC-->>VM: Result.Success
    VM->>VM: updateState(CallState)
    VM-->>UI: callState.collect()
    UI->>UI: Update UI (Calling 상태)
```

### 보안 계층

| 컴포넌트 | 기술 | 용도 |
|---------|------|------|
| Firewall | iptables | 패킷 필터링 |
| DDoS Protection | fail2ban | 무차별 대입 방어 |
| Authentication | Firebase Auth | 사용자 인증 |

---

## iOS Client Architecture (Milestone 3)

### Clean Architecture 계층 구조

```mermaid
graph TB
    subgraph "Presentation Layer"
        A[CallView<br/>SwiftUI]
        B[CallViewModel<br/>Combine State Management]
        C[CallState<br/>UI Models]
    end

    subgraph "Domain Layer"
        D[Use Cases<br/>Business Logic]
        E[WebRTCRepository<br/>Interface]
        F[SignalingRepository<br/>Interface]
    end

    subgraph "Data Layer"
        G[SignalingRepositoryImpl<br/>Firestore Integration]
        H[TurnCredentialService<br/>TURN Credentials]
        I[SignalingMessage<br/>Data Models]
    end

    subgraph "WebRTC Core"
        J[PeerConnectionManager<br/>WebRTC Lifecycle]
        K[Google WebRTC.xcframework<br/>Native Implementation]
    end

    subgraph "Dependency Injection"
        L[AppContainer<br/>Manual DI]
    end

    A --> B
    B --> C
    B --> D
    D --> E
    D --> F
    G --> E
    H --> G
    G --> J
    J --> K
    L --> B
    L --> G
    L --> H
```

### iOS 컴포넌트 상세

#### Presentation Layer
```mermaid
classDiagram
    class CallView {
        <<SwiftUI View>>
        +Body() some View
        +onCallClicked()
        +onHangupClicked()
    }

    class CallViewModel {
        <<ObservableObject>>
        @Published callState: CallState
        -createOfferUseCase: CreateOfferUseCase
        -answerCallUseCase: AnswerCallUseCase
        -endCallUseCase: EndCallUseCase
        +startCall(roomId: String)
        +answerCall()
        +endCall()
    }

    class CallState {
        isConnected: Bool
        isCalling: Bool
        localSessionDescription: String?
        remoteSessionDescription: String?
        errorMessage: String?
    }

    CallView --> CallViewModel
    CallViewModel --> CallState
```

#### Domain Layer
```mermaid
classDiagram
    class CreateOfferUseCase {
        -repository: WebRTCRepository
        -signalingRepository: SignalingRepository
        +execute(roomId: String) async throws
    }

    class AnswerCallUseCase {
        -repository: WebRTCRepository
        -signalingRepository: SignalingRepository
        +execute(offer: String) async throws
    }

    class AddIceCandidateUseCase {
        -signalingRepository: SignalingRepository
        +execute(candidate: IceCandidate) async throws
    }

    class EndCallUseCase {
        -repository: WebRTCRepository
        -signalingRepository: SignalingRepository
        +execute() async throws
    }

    class WebRTCRepository {
        <<protocol>>
        +createPeerConnection() async throws
        +createOffer() async throws -> String
        +createAnswer(offer: String) async throws -> String
        +addIceCandidate(candidate: IceCandidate) async throws
        +close() async throws
    }

    class SignalingRepository {
        <<protocol>>
        +sendOffer(roomId: String, sdp: String) async throws
        +sendAnswer(roomId: String, sdp: String) async throws
        +sendIceCandidate(roomId: String, candidate: IceCandidate) async throws
        +observeOffer(roomId: String) AsyncStream~String~
        +observeAnswer(roomId: String) AsyncStream~String~
        +observeIceCandidates(roomId: String) AsyncStream~IceCandidate~
    }
```

#### Data Layer
```mermaid
classDiagram
    class SignalingRepositoryImpl {
        -firestore: Firestore
        -turnService: TurnCredentialService
        +sendOffer(roomId, sdp) async throws
        +sendAnswer(roomId, sdp) async throws
        +sendIceCandidate(roomId, candidate) async throws
        +observeOffer(roomId) AsyncStream~String~
        +observeAnswer(roomId) AsyncStream~String~
        +observeIceCandidates(roomId) AsyncStream~IceCandidate~
    }

    class TurnCredentialService {
        -apiURL: String
        -cache: NSCache
        -apiToken: String
        +getCredentials(username: String) async throws -> TurnCredentials
    }

    class SignalingMessage {
        <<Codable>>
        type: String
        sdp: String?
        candidate: String?
        sdpMid: String?
        sdpMLineIndex: Int32?
    }
```

### WebRTC PeerConnection 관리 (iOS)

```mermaid
stateDiagram-v2
    [*] --> Idle: 초기화
    Idle --> CreatingOffer: startCall()
    CreatingOffer --> OfferCreated: createOffer() 완료
    OfferCreated --> WaitingForAnswer: Offer 전송 완료
    WaitingForAnswer --> CreatingAnswer: Answer 수신
    CreatingAnswer --> AnswerCreated: createAnswer() 완료
    AnswerCreated --> GatheringCandidates: ICE Gathering 시작
    GatheringCandidates --> Connecting: ICE 후보 교환 중
    Connecting --> Connected: P2P/TURN 연결 성공
    Connected --> Disconnected: 연결 종료
    Disconnected --> [*]: 정리 완료

    OfferCreated --> Disconnected: 타임아웃/거절
    WaitingForAnswer --> Disconnected: 취소
```

### 비동기 처리 (async/await + Combine)

```mermaid
sequenceDiagram
    participant UI as CallView
    participant VM as CallViewModel
    participant UC as CreateOfferUseCase
    participant Repo as WebRTCRepository
    participant PC as PeerConnectionManager
    participant FS as Firestore

    UI->>VM: startCall(roomId)
    VM->>UC: execute(roomId)
    UC->>Repo: createPeerConnection()
    Repo->>PC: initialize()
    PC-->>Repo: RTCPeerConnection
    UC->>Repo: createOffer()
    Repo->>PC: createOffer()
    PC-->>Repo: RTCSessionDescription
    UC->>Repo: setLocalDescription()
    Repo->>PC: setLocalDescription()
    UC->>VM: signalingRepository.sendOffer()
    VM->>FS: firestore.collection(roomId).setData()
    FS-->>VM: Success
    VM->>VM: updateState(CallState.calling)
    VM-->>UI: @Published callState
    UI->>UI: Update UI (Calling 상태)
```

### 의존성 주입 (AppContainer)

```mermaid
graph LR
    subgraph "AppContainer"
        A[Firestore Instance]
        B[TurnCredentialService]
        C[SignalingRepository]
        D[WebRTCRepository]
        E[CreateOfferUseCase]
        F[CallViewModel]
    end

    A --> B
    A --> C
    B --> C
    C --> E
    D --> E
    E --> F
```

### Swift Concurrency 패턴

**async/await 사용:**
```swift
func execute(roomId: String) async throws {
    let peerConnection = try await repository.createPeerConnection()
    let offer = try await repository.createOffer()
    try await repository.setLocalDescription(offer)
    try await signalingRepository.sendOffer(roomId: roomId, sdp: offer.sdp)
}
```

**AsyncStream 사용 (Firestore 리스너):**
```swift
func observeOffer(roomId: String) -> AsyncStream<String> {
    return AsyncStream { continuation in
        let listener = firestore.collection("sessions")
            .document(roomId)
            .addSnapshotListener { snapshot, error in
                guard let sdp = snapshot?.data?["offer"] as? String else {
                    return
                }
                continuation.yield(sdp)
            }
        continuation.onTermination = { _ in
            listener.remove()
        }
    }
}
```

### 보안 계층

---

## 네트워크 토폴로지

### Oracle Cloud 네트워크 구성

```mermaid
graph TB
    subgraph "Oracle Cloud"
        subgraph "VCN (10.0.0.0/16)"
            subgraph "Public Subnet"
                A[TURN Server<br/>10.0.0.2]
                B[Internet Gateway]
            end

            subgraph "Security List"
                C[Allow TCP 3478]
                D[Allow UDP 3478]
                E[Allow TCP 5349]
                F[Allow UDP 49152-65535]
            end
        end
    end

    subgraph "Internet"
        G[Android Clients]
        H[iOS Clients]
    end

    G --> B
    H --> B
    B --> A
    C --> A
    D --> A
    E --> A
    F --> A
```

### 포트 매핑

| 포트 | 프로토콜 | 용도 | 설명 |
|------|---------|------|------|
| 3478 | TCP/UDP | STUN/TURN | 기본 STUN/TURN 포트 |
| 3479 | TCP/UDP | STUN/TURN | 대체 포트 |
| 5349 | TCP | TURNS | TLS over TURN |
| 5350 | TCP | TURNS | TLS 대체 포트 |
| 49152-65535 | UDP | Media Relay | TURN 릴레이 포트 범위 |

---

## 모니터링 및 로깅

### 모니터링 아키텍처

```mermaid
graph LR
    A[Coturn Server] -->|Metrics| B[monitor.sh]
    B -->|Health Check| C[Prometheus]
    C -->|Alerts| D[PagerDuty/Email]

    E[TURN API] -->|Logs| F[Uvicorn Logs]
    F -->|Forward| G[Cloud Logging]

    H[Firebase] -->|Metrics| I[Firebase Console]
    I -->|Dashboard| J[Grafana]
```

### 로그 수집

1. **Coturn 로그**: `/var/log/turnserver.log`
2. **API 로그**: Uvicorn stdout → Cloud Logging
3. **Firebase 로그**: Firestore 쿼리 로그
4. **시스템 로그**: `/var/log/syslog`

---

## 데이터 모델

### WebRTC 세션 상태 머신

```mermaid
stateDiagram-v2
    [*] --> pending: createSession()
    pending --> offered: createOffer()
    offered --> answered: createAnswer()
    answered --> connected: ICE connected
    connected --> ended: hangUp()
    offered --> ended: timeout/reject
    pending --> ended: cancel()

    note right of pending
        Caller initiates call
        Session document created
    end note

    note right of offered
        SDP Offer stored
        Waiting for callee
    end note

    note right of answered
        SDP Answer stored
        ICE exchange started
    end note

    note right of connected
        P2P or TURN established
        Media flowing
    end note

    note right of ended
        Session cleaned up
        After 1 hour TTL
    end note
```

---

## 성능 최적화

### Oracle Cloud Free Tier 제약 사항

| 리소스 | 제한 | 최적화 전략 |
|--------|------|------------|
| CPU | 1 OCPU | io-thread-count=2, relay-thread-count=2 |
| RAM | 1GB | 최소한의 프로세스 실행 |
| Bandwidth | 10TB/월 | max-bps=3000000 (3Mbps per session) |
| Storage | 200GB | 로그 로테이션, 30일 보관 |

### Firebase Free Tier 제약 사항

| 리소스 | 제한 | 최적화 전략 |
|--------|------|------------|
| Reads | 50K/day | 세션 문서 캐싱 |
| Writes | 20K/day | 배치 업데이트 |
| Storage | 1GB | 1시간 TTL로 자동 삭제 |

---

## 참고 문헌

- [WebRTC Protocols](https://webrtc.org/)
- [Coturn Documentation](https://github.com/coturn/coturn)
- [Firebase Firestore Security Rules](https://firebase.google.com/docs/firestore/security)
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)

---

**문서 버전**: 2.0.0
**마지막 업데이트**: 2026-01-19
**작성자**: WebRTC-Lite Team

## 변경 이력

### v2.0.0 (2026-01-19)
- Milestone 4 고급 기능 아키텍처 추가
- 네트워크 모니터링 및 품질 메트릭 섹션 추가
- 자동 재연결 상태 머신 다이어그램 추가
- TURN 자격 증명 캐싱 및 자동 갱신 흐름 추가
- 백그라운드 상태 처리 라이프사이클 다이어그램 추가

### v1.0.0 (2026-01-18)
- 초기 시스템 아키텍처 문서
- Android/iOS 클라이언트 아키텍처
- C4 컨테이너 다이어그램
- WebRTC 연결 시퀀스 다이어그램
