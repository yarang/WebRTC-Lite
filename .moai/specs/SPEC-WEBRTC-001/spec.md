# SPEC-WEBRTC-001: WebRTC-Lite Hybrid Server

**TAG BLOCK**
```
SPEC-ID: SPEC-WEBRTC-001
TITLE: WebRTC-Lite Hybrid Server Infrastructure
STATUS: Planned
PRIORITY: High
ASSIGNED: Alfred
CREATED: 2025-01-18
LIFECYCLE: spec-anchored
```

---

## 1. Environment

### 1.1 Context

WebRTC-Lite는 비용 효율적인 하이브리드 WebRTC 인프라 솔루션으로, Firebase Firestore의 실시간 데이터베이스를 시그널링 서버로 활용하고 Oracle Cloud Free Tier의 Coturn 서버를 TURN/STUN 서버로 사용하여 월 $0 비용으로 P2P 연결을 지원합니다.

### 1.2 Target Platform

- **Mobile Platforms**: Android (API 24+), iOS (13.0+)
- **TURN/STUN Server**: Oracle Cloud Free Tier (Ubuntu 22.04)
- **Signaling Server**: Firebase Firestore (Free Tier: 50K reads/day, 20K writes/day)
- **Cost Target**: $0/month (Free Tier only)

### 1.3 Assumptions

- TURN/STUN 서버에 공용 IP 주소가 할당되어 있음
- Firebase 프로젝트가 생성되어 있고 Firestore가 활성화됨
- 클라이언트 앱이 인증된 Firebase 사용자 컨텍스트를 보유함
- 최대 동시 연결 수: Free Tier 제한 내에서 10-50개 연결 지원
- TURN 서버는 대부분의 NAT 환경에서 필수적임

---

## 2. System Requirements (EARS Format)

### 2.1 Ubiquitous Requirements (시스템은 항상 수행해야 하는 동작)

**REQ-U001** - 시스템은 **항상** 모든 WebRTC 연결 시도에 대해 STUN 서버 주소를 제공해야 한다.

**REQ-U002** - 시스템은 **항상** Firestore 시그널링 메시지의 수명 주기를 관리해야 한다 (생성, 읽기, 삭제).

**REQ-U003** - 시스템은 **항상** TURN 자격 증명을 안전하게 저장하고 전송해야 한다 (TTL 기반 임시 자격 증명).

**REQ-U004** - 시스템은 **항상** 연결 실패 시 로그를 기록하고 디버깅 정보를 제공해야 한다.

**REQ-U005** - 시스템은 **항상** P2P 연결 시도 후 일정 시간(30초) 내에 성공하지 않으면 TURN 서버로 폴백해야 한다.

### 2.2 Event-Driven Requirements (WHEN event THEN response)

**REQ-E001** - **WHEN** 새로운 WebRTC 세션이 시작되면, 시스템은 **SHALL** Firestore에 고유한 세션 문서를 생성하고 SDP Offer를 저장해야 한다.

**REQ-E002** - **WHEN** 원격 피어가 SDP Answer를 게시하면, 시스템은 **SHALL** 로컬 피어에게 알림을 전송하고 Answer를 적용해야 한다.

**REQ-E003** - **WHEN** ICE 후보가 수집되면, 시스템은 **SHALL** 즉시 Firestore에 후보 정보를 게시해야 한다.

**REQ-E004** - **WHEN** 네트워크 상태가 변경되면(WiFi ↔ Cellular), 시스템은 **SHALL** ICE 연결을 재시도해야 한다.

**REQ-E005** - **WHEN** WebRTC 연결이 성립되면, 시스템은 **SHALL** Firestore의 시그널링 문서를 삭제하여 불필요한 저장소 비용을 절약해야 한다.

**REQ-E006** - **WHEN** 연결이 끊어지면, 시스템은 **SHALL** 자동으로 재연결을 시도해야 한다 (최대 3회).

**REQ-E007** - **WHEN** TURN 자격 증명이 만료되면, 시스템은 **SHALL** 새로운 임시 자격 증명을 요청해야 한다.

### 2.3 State-Driven Requirements (IF condition THEN action)

**REQ-S001** - **IF** NAT 환경이 감지되면(Symmetric NAT 등), 시스템은 **SHALL** 즉시 TURN 서버를 사용해야 한다.

**REQ-S002** - **IF** Firestore 읽기/쓰기 할당량이 80%에 도달하면, 시스템은 **SHALL** 시그널링 폴링 간격을 늘려야 한다.

**REQ-S003** - **IF** TURN 서버가 응답하지 않으면, 시스템은 **SHALL** 사용자에게 연결 실패 알림을 표시해야 한다.

**REQ-S004** - **IF** P2P 연결이 성공하면, 시스템은 **SHALL** TURN 서버 사용을 중단하고 직접 P2P 통신을 우선해야 한다.

**REQ-S005** - **IF** 백그라운드 상태에서 5분 이상 경과하면, 시스템은 **SHALL** WebRTC 세션을 종료해야 한다.

### 2.4 Unwanted Behavior Requirements (시스템은 하지 않아야 하는 동작)

**REQ-N001** - 시스템은 TURN 자격 증명을 클라이언트 측에 하드코딩해서는 **안 된다**.

**REQ-N002** - 시스템은 미인증 사용자의 시그널링 메시지를 처리해서는 **안 된다**.

**REQ-N003** - 시스템은 WebRTC 세션 간에 미디어 스트림을 혼합해서는 **안 된다**.

**REQ-N004** - 시스템은 사용자의 비밀번호나 민감한 정보를 로그에 기록해서는 **안 된다**.

**REQ-N005** - 시스템은 만료된 SDP Offer를 사용해서는 **안 된다** (5분 TTL).

### 2.5 Optional Requirements (가능하면 제공해야 하는 기능)

**REQ-O001** - 가능하면 화면 공유(Screen Share) 기능을 제공해야 한다.

**REQ-O002** - 가능하면 화상 회의를 위한 다자간(Multi-party) 연결을 지원해야 한다 (SFU 아키텍처).

**REQ-O003** - 가능하면 네트워크 대역폭에 따라 적응적 비트레이트 조정(Adaptive Bitrate)을 제공해야 한다.

**REQ-O004** - 가능하면 연결 품질 메트릭(RTT, 패킷 손실, 대역폭)을 실시간으로 표시해야 한다.

**REQ-O005** - 가능하면 녹화 기능을 제공해야 한다 (로컬 또는 클라우드 저장).

---

## 3. Architecture Overview

### 3.1 System Components

```
┌─────────────────────────────────────────────────────────────────────┐
│                         WebRTC-Lite Architecture                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────┐         ┌──────────────┐         ┌──────────────┐ │
│  │   Android    │         │     iOS      │         │   Web App    │ │
│  │    Client    │         │    Client    │         │   (Future)   │ │
│  └──────┬───────┘         └──────┬───────┘         └──────┬───────┘ │
│         │                        │                        │         │
│         └────────────────────────┼────────────────────────┘         │
│                                  │                                  │
│                    ┌─────────────▼─────────────┐                    │
│                    │   Firebase Firestore      │                    │
│                    │   (Signaling Channel)     │                    │
│                    │   - SDP Offers/Answers    │                    │
│                    │   - ICE Candidates        │                    │
│                    │   - Session Metadata      │                    │
│                    └─────────────┬─────────────┘                    │
│                                  │                                  │
│                    ┌─────────────▼─────────────┐                    │
│                    │      Coturn Server        │                    │
│                    │   (Oracle Cloud Free)     │                    │
│                    │   - STUN: Port 3478       │                    │
│                    │   - TURN: Port 3479       │                    │
│                    │   - DTLS: encrypted       │                    │
│                    └───────────────────────────┘                    │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 Firestore Collections Structure

**Collection: `webrtc_sessions`**
```
{
  "session_id": "uuid-v4",
  "caller_id": "user_uid",
  "callee_id": "user_uid",
  "status": "pending" | "offered" | "answered" | "connected" | "ended",
  "created_at": Timestamp,
  "updated_at": Timestamp,
  "offer": {
    "sdp": "base64_encoded_sdp",
    "type": "offer",
    "created_at": Timestamp
  },
  "answer": {
    "sdp": "base64_encoded_sdp",
    "type": "answer",
    "created_at": Timestamp
  },
  "ice_candidates": {
    "caller": [
      {"candidate": "...", "sdpMid": "...", "sdpMLineIndex": 0}
    ],
    "callee": [
      {"candidate": "...", "sdpMid": "...", "sdpMLineIndex": 0}
    ]
  },
  "turn_credentials": {
    "username": "timestamp:username",
    "password": "base64_encoded",
    "ttl": 86400,
    "uris": ["turn:server:3479?transport=udp"]
  }
}
```

### 3.3 Technology Stack

| Component | Technology | Version | Rationale |
|-----------|-----------|---------|-----------|
| Signaling | Firebase Firestore | Latest | Free Tier, Real-time listeners |
| TURN/STUN | Coturn | 4.6+ | Industry standard, OCI Free Tier |
| Android SDK | Kotlin + WebRTC | 1.6+ | Native WebRTC support |
| iOS SDK | Swift + WebRTC | 5.0+ | Native WebRTC support |
| Authentication | Firebase Auth | Latest | Free Tier integration |
| Deployment | Oracle Cloud Free Tier | Ubuntu 22.04 | 2 AMD VMs, 10TB Bandwidth |

### 3.4 Security Considerations

- **Transport**: TLS 1.3 for all signaling communication
- **Media**: DTLS-SRTP for media encryption (mandatory)
- **Authentication**: Firebase Auth UID verification for all signaling
- **TURN**: Temporary credentials with 24-hour TTL
- **Authorization**: Firestore Security Rules for collection access
- **NAT Traversal**: STUN for direct connection, TURN for fallback

---

## 4. Traceability Matrix

| REQ ID | Category | Test Scenario | Priority |
|--------|----------|---------------|----------|
| REQ-U001 | Ubiquitous | All connections include STUN config | High |
| REQ-E001 | Event | Session creation stores Offer | High |
| REQ-E002 | Event | Answer notification received | High |
| REQ-E003 | Event | ICE candidates published | High |
| REQ-E004 | Event | Network change triggers reconnect | Medium |
| REQ-S001 | State | NAT detection uses TURN | High |
| REQ-S002 | State | Quota management reduces polling | Low |
| REQ-N001 | Unwanted | No hardcoded credentials | High |
| REQ-N002 | Unwanted | Auth required for signaling | High |
| REQ-O001 | Optional | Screen sharing support | Low |

---

## 5. References

- [WebRTC Protocols](https://webrtc.org/)
- [Coturn Documentation](https://github.com/coturn/coturn)
- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security)
- [Oracle Cloud Free Tier](https://www.oracle.com/cloud/free/)
