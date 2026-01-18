# WebRTC-Lite Architecture

## 목차

- [시스템 개요](#시스템-개요)
- [아키텍처 원칙](#아키텍처-원칙)
- [시스템 구성 요소](#시스템-구성-요소)
- [데이터 흐름](#데이터-흐름)
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
| iOS | Swift | Google WebRTC (1.0+) | 🔄 진행 중 |

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

**문서 버전**: 1.0.0
**마지막 업데이트**: 2026-01-18
**작성자**: WebRTC-Lite Team
