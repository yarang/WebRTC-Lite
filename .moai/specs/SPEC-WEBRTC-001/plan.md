# Implementation Plan: SPEC-WEBRTC-001

**TAG BLOCK**
```
SPEC-ID: SPEC-WEBRTC-001
DOCUMENT: plan.md
VERSION: 1.0
LAST_UPDATED: 2025-01-18
```

---

## 1. Milestones (Priority-Based)

### Priority High (Primary Goal)

**Milestone 1: Infrastructure Foundation**
- Oracle Cloud Free Tier VM provisioning
- Coturn TURN/STUN server installation and configuration
- Firebase project setup with Firestore and Authentication
- Security rules deployment
- TURN credentials generation endpoint

**Milestone 2: Android SDK Core**
- WebRTC library integration
- Signaling client implementation (Firestore listeners)
- PeerConnection management
- ICE gathering and candidate exchange
- Basic 1:1 audio/video call

**Milestone 3: iOS SDK Core**
- WebRTC library integration (CocoaPodods/SPM)
- Signaling client implementation
- PeerConnection management
- ICE gathering and candidate exchange
- Basic 1:1 audio/video call

### Priority Medium (Secondary Goal)

**Milestone 4: Advanced Features**
- Network state monitoring and reconnection
- TURN credentials auto-refresh
- Adaptive bitrate (opus codec configuration)
- Connection quality metrics display
- Background state handling

**Milestone 5: Error Handling & Logging**
- Comprehensive error categorization
- Debug logging with severity levels
- Crash reporting integration
- Connection failure diagnostics
- User-friendly error messages

### Priority Low (Final Goal)

**Milestone 6: Optional Enhancements**
- Screen sharing (if platform supported)
- Multi-party connection preparation (SFU design)
- Recording capability (local storage)
- Bandwidth estimation display

### Optional Goal (Future)

**Milestone 7: Production Readiness**
- Load testing (10-50 concurrent connections)
- Performance optimization
- Documentation completion
- Sample applications
- Deployment automation

---

## 2. Technical Approach

### 2.1 WebRTC Peer Connection Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                    WebRTC Connection Lifecycle                      │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  CALLER                    FIRESTORE                  CALLEE         │
│    │                          │                          │           │
│    │  1. Create PeerConnection                           │           │
│    │  2. Get TURN Credentials    │                          │           │
│    ├───────────────────────────>│                          │           │
│    │<────────────────────────────┤                          │           │
│    │  3. Create Offer            │                          │           │
│    │  4. Store Offer             │                          │           │
│    ├───────────────────────────>│                          │           │
│    │                          │  5. Notify Callee          │           │
│    │                          ├──────────────────────────>│           │
│    │                          │                          │  6. Create PC│
│    │                          │                          │  7. Create Ans│
│    │                          │<──────────────────────────┤  8. Store Ans│
│    │  9. Listen for Answer     │<──────────────────────────┤           │
│    │<───────────────────────────┤                          │           │
│    │  10. Set Remote Desc       │                          │           │
│    │                          │                          │ 11. Listen  │
│    │  12. Gather ICE            │                          │ 12. Gather ICE│
│    │  13. Publish ICE           │                          │ 13. Publish ICE│
│    ├───────────────────────────>│                          │           │
│    │                          │<──────────────────────────┤           │
│    │  14. Listen for Remote ICE│                          │           │
│    │<───────────────────────────┤                          │           │
│    │  15. Add ICE Candidate     │                          │  16. Add ICE│
│    │                          │                          │<──────────┤
│    │  17. ICE Connection Complete                           │           │
│    ├──────────────────────────────────────────────────────>│           │
│    │  18. DTLS Handshake                                     │           │
│    │  19. Media Flow Established                             │           │
│    │<========================================================>│           │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 TURN Server Configuration

**Coturn Configuration (`/etc/turnserver.conf`)**
```conf
# Network
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=PUBLIC_IP
external-ip=PUBLIC_IP

# Authentication
lt-cred-mech
userdb=/var/lib/turn/turndb
realm=webrtc.example.com

# STUN/TURN
fingerprint
lt-cred-mech
stale-nonce
no-loopback-peers
no-multicast-peers

# TLS
cert=/etc/letsencrypt/live/turn.example.com/fullchain.pem
pkey=/etc/letsencrypt/live/turn.example.com/privkey.pem
cipher-list="ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384"

# Logging
log-file=/var/log/turnserver.log
verbose
```

**TURN Credentials API (Python FastAPI)**
```python
from fastapi import FastAPI
from datetime import datetime, timedelta
import hmac
import hashlib
import base64

app = FastAPI()

TURN_SECRET = "your-secret-key"
TURN_SERVER = "turn.example.com:3479"

def generate_turn_credentials(username: str, ttl: int = 86400) -> dict:
    timestamp = int(datetime.now().timestamp()) + ttl
    turn_username = f"{timestamp}:{username}"

    # HMAC-SHA1 signature
    hmac_obj = hmac.new(
        TURN_SECRET.encode(),
        turn_username.encode(),
        hashlib.sha1
    )
    password = base64.b64encode(hmac_obj.digest()).decode()

    return {
        "username": turn_username,
        "password": password,
        "ttl": ttl,
        "uris": [
            f"turn:{TURN_SERVER}?transport=udp",
            f"turn:{TURN_SERVER}?transport=tcp"
        ]
    }

@app.get("/turn-credentials")
async def get_turn_credentials(username: str):
    return generate_turn_credentials(username)
```

### 2.3 Firestore Security Rules

**Rules (`firestore.rules`)**
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Helper functions
    function isSignedIn() {
      return request.auth != null;
    }

    function isCaller() {
      return isSignedIn() &&
             request.auth.uid == resource.data.caller_id;
    }

    function isCallee() {
      return isSignedIn() &&
             request.auth.uid == resource.data.callee_id;
    }

    function isParticipant() {
      return isCaller() || isCallee();
    }

    // Sessions collection
    match /webrtc_sessions/{sessionId} {
      // Allow create if caller
      allow create: if isSignedIn() &&
                        request.resource.data.caller_id == request.auth.uid;

      // Allow read/update for participants only
      allow read, update: if isParticipant();

      // Allow delete for caller or after 1 hour
      allow delete: if isCaller() ||
                       (request.time > resource.data.created_at + duration(1, 'h'));

      // ICE candidates subcollection
      match /ice_candidates/{candidateId} {
        allow read, write: if isParticipant();
      }
    }

    // TURN credentials (server-only, no client access)
    match /turn_credentials/{docId} {
      allow read: if false;  // Server API only
      allow write: if false;
    }
  }
}
```

---

## 3. Architecture Design

### 3.1 Component Interaction Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Component Interaction                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    WebRTCManager                              │  │
│  │  - PeerConnection lifecycle                                  │  │
│  │  - Media stream management                                   │  │
│  │  - ICE candidate handling                                    │  │
│  └───────────────────────────┬──────────────────────────────────┘  │
│                              │                                       │
│          ┌───────────────────┼───────────────────┐                 │
│          │                   │                   │                 │
│  ┌───────▼────────┐  ┌───────▼────────┐  ┌──────▼─────────┐       │
│  │ SignalingClient│  │NetworkMonitor │  │AuthManager     │       │
│  │ - Firestore    │  │ - Network state│  │ - Firebase Auth│       │
│  │ - SDP exchange │  │ - Reconnect   │  │ - Token refresh│       │
│  └────────────────┘  └───────────────┘  └────────────────┘       │
│                                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                      TurnCredentialService                    │  │
│  │  - Fetch temporary credentials                               │  │
│  │  - Cache with TTL                                             │  │
│  │  - Auto-refresh on expiry                                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 State Machine

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Session State Machine                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                       │
│   [IDLE] ────CreateOffer───> [OFFER_SENT] ────ReceiveAnswer───>     │
│      │                          │                    │              │
│      │                          │                    v              │
│      │<───────────Error─────────┴───────────> [CONNECTING]          │
│      │                              │         (ICE Exchange)        │
│      │                              v                │              │
│      └──────────────────────> [CONNECTED] <────────┘               │
│                                        │                            │
│                                        │ Disconnect/Error           │
│                                        v                            │
│                                    [ENDED]                          │
│                                        │                            │
│                                        v                            │
│                                    [IDLE]                           │
│                                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 4. Risk Management

### 4.1 Identified Risks

| Risk | Impact | Probability | Mitigation Strategy |
|------|--------|-------------|---------------------|
| Free Tier quota exceeded | High | Medium | Implement graceful degradation, alerting |
| TURN server downtime | High | Low | Health checks, auto-restart on OCI |
| NAT traversal failure | High | Medium | Always provide TURN credentials |
| Firestore latency | Medium | Low | Local caching, optimistic UI |
| WebRTC compatibility | Medium | Low | Test on target Android/iOS versions |
| Security vulnerabilities | High | Low | Regular updates, DTLS mandatory |

### 4.2 Contingency Plans

**Free Tier Exhaustion**
- Implement adaptive polling: Increase interval as quota approaches
- Session cleanup: Delete Firestore documents immediately after connection
- Fallback to WebSocket signaling (future enhancement)

**TURN Server Failure**
- Health check endpoint every 30 seconds
- Automatic service restart via systemd
- Alert administrator via email/SMS

**NAT Traversal Issues**
- Always provide TURN credentials (not optional)
- Support both UDP and TCP transports
- Document known incompatible network configurations

---

## 5. Dependencies

### 5.1 External Dependencies

| Dependency | Version | License | Purpose |
|------------|---------|---------|---------|
| Coturn | 4.6+ | BSD | TURN/STUN server |
| Firebase SDK | Latest | Firebase | Authentication, Firestore |
| WebRTC (Android) | 1.6+ | BSD | P2P media |
| WebRTC (iOS) | 5.0+ | BSD | P2P media |
| Python FastAPI | 0.115+ | MIT | TURN credential API |
| Oracle Cloud | Always Free | Oracle | Infrastructure |

### 5.2 Development Dependencies

| Dependency | Version | License | Purpose |
|------------|---------|---------|---------|
| pytest | Latest | MIT | Testing |
| pytest-asyncio | Latest | MIT | Async tests |
| black | Latest | MIT | Code formatting |
| mypy | Latest | MIT | Type checking |
| ruff | Latest | MIT | Linting |

---

## 6. Verification Strategy

### 6.1 Testing Approach

**Unit Testing** (pytest for Python, JUnit for Android, XCTest for iOS)
- Individual component logic
- State transitions
- Error handling paths

**Integration Testing**
- Firestore signaling flow
- TURN credential generation
- Authentication integration

**End-to-End Testing**
- Full call establishment
- Network reconnection
- Multi-client scenarios

**Manual Testing**
- Real device testing on Android and iOS
- Different network conditions (WiFi, Cellular, NAT)
- Connection quality assessment

### 6.2 Quality Metrics

- **Test Coverage Target**: 100% for critical paths, 85% overall
- **Linting**: Zero ruff warnings
- **Type Checking**: Zero mypy errors
- **Security**: OWASP compliance, zero high-severity vulnerabilities
- **Performance**: P2P connection < 3 seconds, TURN connection < 5 seconds

---

## 7. Next Steps

After SPEC approval:

1. Execute `/moai:2-run SPEC-WEBRTC-001` to begin TDD implementation
2. Start with Milestone 1 (Infrastructure Foundation)
3. Create GitHub issues for each milestone
4. Set up CI/CD pipeline for automated testing
5. Deploy staging environment for manual verification
