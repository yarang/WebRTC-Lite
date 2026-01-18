# TURN Credentials API Reference

## 개요

TURN Credentials API는 WebRTC 클라이언트를 위해 시간 제한이 있는 TURN 자격 증명을 생성하는 REST API입니다. HMAC-SHA1 인증을 사용하여 보안된 자격 증명을 제공합니다.

**기본 URL**: `http://<YOUR_SERVER>:8080`

**API 버전**: 1.0.0

---

## 인증

### API Key 인증

모든 엔드포인트는 선택적 API Key 인증을 지원합니다. API Key가 구성된 경우, 요청 헤더에 포함해야 합니다.

```http
X-API-Key: your-api-key-here
```

**환경변수 설정**:
```bash
export API_KEY=your-secure-api-key
export TURN_SECRET=your-turn-shared-secret
```

---

## 엔드포인트

### 1. 루트 엔드포인트

API 정보를 반환합니다.

**요청**:
```http
GET /
```

**응답**:
```json
{
  "service": "TURN Credentials API",
  "version": "1.0.0",
  "description": "Provides time-limited TURN credentials for WebRTC clients"
}
```

---

### 2. 헬스 체크

API 상태를 확인합니다.

**요청**:
```http
GET /health
```

**응답**:
```json
{
  "status": "healthy",
  "version": "1.0.0",
  "timestamp": "2026-01-18T10:30:00.000Z"
}
```

---

### 3. TURN 자격 증명 생성 (POST)

시간 제한 TURN 자격 증명을 생성합니다. 프로덕션 환경에서 권장되는 방식입니다.

**요청**:
```http
POST /turn-credentials
Content-Type: application/json
X-API-Key: your-api-key

{
  "username": "user123",
  "ttl": 86400
}
```

**요청 파라미터**:

| 필드 | 타입 | 필수 | 설명 | 제약사항 |
|------|------|------|------|----------|
| username | string | Yes | 사용자 이름 | 1-128자, 영숫자 및 `._-`만 허용 |
| ttl | integer | No | 자격 증명 유효 시간 (초) | 60-86400, 기본값 86400 (24시간) |

**응답**:
```json
{
  "username": "1737910400:user123",
  "password": "dGVzdHBhc3N3b3Jk",
  "ttl": 86400,
  "uris": [
    "turn:turn.example.com:5349?transport=udp",
    "turn:turn.example.com:5349?transport=tcp",
    "turns:turn.example.com:5349?transport=tcp"
  ]
}
```

**응답 필드**:

| 필드 | 타입 | 설명 |
|------|------|------|
| username | string | 시간 정보가 포함된 사용자 이름 (`timestamp:original_username`) |
| password | string | Base64로 인코딩된 HMAC-SHA1 비밀번호 |
| ttl | integer | 자격 증명 유효 시간 (초) |
| uris | array[string] | TURN 서버 URI 목록 (UDP, TCP, TLS) |

**에러 응답**:

```json
// 400 Bad Request
{
  "error": "Username contains invalid characters",
  "status_code": 400
}

// 401 Unauthorized
{
  "error": "Invalid API key",
  "status_code": 401
}

// 500 Internal Server Error
{
  "error": "TURN server configuration error",
  "status_code": 500
}
```

---

### 4. TURN 자격 증명 생성 (GET)

테스트를 위한 편의용 GET 엔드포인트입니다.

**요청**:
```http
GET /turn-credentials?username=user123&ttl=3600
X-API-Key: your-api-key
```

**쿼리 파라미터**:

| 파라미터 | 타입 | 필수 | 설명 | 제약사항 |
|----------|------|------|------|----------|
| username | string | Yes | 사용자 이름 | 1-128자 |
| ttl | integer | No | 자격 증명 유효 시간 (초) | 60-86400, 기본값 86400 |

**응답**: POST 엔드포인트와 동일

---

## 클라이언트 통합 가이드

### Android (Kotlin)

```kotlin
import retrofit2.Retrofit
import retrofit2.http.Body
import retrofit2.http.POST
import retrofit2.http.GET
import retrofit2.http.Query

// 데이터 모델
data class CredentialsRequest(
    val username: String,
    val ttl: Int = 86400
)

data class TURNCredentials(
    val username: String,
    val password: String,
    val ttl: Int,
    val uris: List<String>
)

// Retrofit API 인터페이스
interface TurnCredentialsApi {
    @POST("/turn-credentials")
    suspend fun getCredentials(
        @Body request: CredentialsRequest,
        @Header("X-API-Key") apiKey: String
    ): TURNCredentials

    @GET("/turn-credentials")
    suspend fun getCredentials(
        @Query("username") username: String,
        @Query("ttl") ttl: Int = 86400,
        @Header("X-API-Key") apiKey: String
    ): TURNCredentials
}

// 사용 예시
class TurnCredentialManager(
    private val api: TurnCredentialsApi,
    private val apiKey: String
) {
    suspend fun getTurnCredentials(userId: String): TURNCredentials {
        return api.getCredentials(
            CredentialsRequest(userId),
            apiKey
        )
    }
}

// PeerConnection 설정
fun createPeerConnection(credentials: TURNCredentials): PeerConnection {
    val iceServers = credentials.uris.map { uri ->
        IceServer.Builder(uri)
            .setUsername(credentials.username)
            .setPassword(credentials.password)
            .createIceServer()
    }

    val config = PeerConnection.IceServerBuilder()
        .createIceServer()
        .let {
            PeerConnection.IceServerBuilder(iceServers)
        }

    return peerConnectionFactory.createPeerConnection(config, observer)
}
```

### iOS (Swift)

```swift
import Foundation

// 데이터 모델
struct CredentialsRequest: Codable {
    let username: String
    let ttl: Int
}

struct TURNCredentials: Codable {
    let username: String
    let password: String
    let ttl: Int
    let uris: [String]
}

// API 클라이언트
class TurnCredentialsClient {
    private let baseURL: String
    private let apiKey: String

    init(baseURL: String, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func getCredentials(username: String, ttl: Int = 86400) async throws -> TURNCredentials {
        var urlComponents = URLComponents(string: "\(baseURL)/turn-credentials")!
        urlComponents.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "ttl", value: String(ttl))
        ]

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(TURNCredentials.self, from: data)
    }
}

// WebRTC 설정
class WebRTCManager {
    func createPeerConnection(credentials: TURNCredentials) -> RTCPeerConnection {
        let iceServers: [RTCIceServer] = credentials.uris.map { uri in
            RTCIceServer(
                url: uri,
                username: credentials.username,
                credential: credentials.password
            )
        }

        let config = RTCConfiguration()
        config.iceServers = iceServers

        return peerConnectionFactory.peerConnection(
            with: config,
            delegate: self
        )
    }
}
```

### JavaScript (TypeScript)

```typescript
// 타입 정의
interface CredentialsRequest {
  username: string;
  ttl?: number;
}

interface TURNCredentials {
  username: string;
  password: string;
  ttl: number;
  uris: string[];
}

// API 클라이언트
class TurnCredentialsClient {
  private baseURL: string;
  private apiKey: string;

  constructor(baseURL: string, apiKey: string) {
    this.baseURL = baseURL;
    this.apiKey = apiKey;
  }

  async getCredentials(username: string, ttl: number = 86400): Promise<TURNCredentials> {
    const response = await fetch(`${this.baseURL}/turn-credentials`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': this.apiKey,
      },
      body: JSON.stringify({ username, ttl }),
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    return response.json();
  }
}

// WebRTC 설정
async function createPeerConnection(credentials: TURNCredentials): Promise<RTCPeerConnection> {
  const config: RTCConfiguration = {
    iceServers: credentials.uris.map(uri => ({
      urls: uri,
      username: credentials.username,
      credential: credentials.password,
    })),
  };

  return new RTCPeerConnection(config);
}
```

---

## 인증 메커니즘

### HMAC-SHA1 자격 증명 생성

API는 TURN 서버와 공유된 비밀키(`TURN_SECRET`)를 사용하여 HMAC-SHA1 서명을 생성합니다.

**생성 과정**:

1. **타임스탬프 계산**: 현재 시간 + TTL
2. **사용자 이름 생성**: `timestamp:username`
3. **HMAC-SHA1 서명 생성**: `HMAC-SHA1(TURN_SECRET, turn_username)`
4. **Base64 인코딩**: 서명을 Base64로 인코딩

**Python 예시**:
```python
import hmac
import hashlib
import base64
from datetime import datetime, timedelta

def generate_turn_credentials(username: str, ttl: int, secret: str):
    # 타임스탬프 계산
    timestamp = int((datetime.now() + timedelta(seconds=ttl)).timestamp())
    turn_username = f"{timestamp}:{username}"

    # HMAC-SHA1 생성
    hmac_obj = hmac.new(
        secret.encode(),
        turn_username.encode(),
        hashlib.sha1
    )
    password = base64.b64encode(hmac_obj.digest()).decode()

    return {
        "username": turn_username,
        "password": password,
        "ttl": ttl
    }
```

---

## 환경변수 설정

### 필수 환경변수

| 변수 | 설명 | 예시 |
|------|------|------|
| `TURN_SECRET` | TURN 서버와 공유된 비밀키 | `your-secret-key-here` |
| `TURN_SERVER` | TURN 서버 주소 | `turn.example.com` |
| `TURN_PORT` | TURN 서버 포트 | `5349` |

### 선택적 환경변수

| 변수 | 설명 | 기본값 |
|------|------|--------|
| `API_KEY` | API 인증 키 (없으면 인증 안 함) | 없음 |
| `DEFAULT_TTL` | 기본 TTL (초) | `86400` |
| `MAX_TTL` | 최대 TTL (초) | `86400` |
| `MIN_TTL` | 최소 TTL (초) | `60` |

### 서비스 시작

```bash
# 환경변수 설정
export TURN_SECRET=$(openssl rand -base64 32)
export TURN_SERVER=turn.example.com
export TURN_PORT=5349
export API_KEY=your-api-key-here

# 또는 .env 파일 사용
cat > .env << EOF
TURN_SECRET=$(openssl rand -base64 32)
TURN_SERVER=turn.example.com
TURN_PORT=5349
API_KEY=your-api-key-here
EOF

# 서비스 시작
python -m uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

---

## 보안 권장사항

### 1. API Key 사용

프로덕션 환경에서는 반드시 API Key를 설정하여 무단 접근을 방지하세요.

```bash
export API_KEY=$(openssl rand -hex 32)
```

### 2. HTTPS 사용

프로덕션에서는 HTTPS를 통해 API를 제공하세요.

```bash
# Nginx 역프록시 설정
server {
    listen 443 ssl;
    server_name turn-api.example.com;

    ssl_certificate /etc/letsencrypt/live/turn-api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/turn-api.example.com/privkey.pem;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 3. TTL 제한

TTL을 최소화하여 자격 증명 노출 위험을 줄이세요.

```bash
export DEFAULT_TTL=3600  # 1시간
export MAX_TTL=86400     # 24시간
```

### 4. Rate Limiting

Rate limiting을 구현하여 DoS 공격을 방지하세요.

```python
# slowapi를 사용한 rate limiting 예시
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@app.post("/turn-credentials")
@limiter.limit("10/minute")
async def get_turn_credentials(request: CredentialsRequest):
    # ...
```

---

## 테스트

### 단위 테스트

```bash
# 테스트 실행
cd infrastructure/oracle-cloud/coturn/turn-credentials-api
pytest test_main.py -v

# 커버리지 확인
pytest test_main.py --cov=main --cov-report=html
```

### 통합 테스트

```bash
# curl로 테스트
curl -X POST http://localhost:8080/turn-credentials \
  -H "Content-Type: application/json" \
  -H "X-API-Key: test-api-key" \
  -d '{"username": "testuser", "ttl": 3600}'
```

---

## 문제 해결

### 일반적인 문제

1. **401 Unauthorized**: API Key가 틀리거나 설정되지 않음
2. **400 Bad Request**: 사용자 이름 형식 오류 또는 TTL 범위 초과
3. **500 Internal Server Error**: TURN_SECRET이 설정되지 않음

### 로그 확인

```bash
# 서비스 로그
sudo journalctl -u turn-credentials-api -f

# 에러만 필터링
sudo journalctl -u turn-credentials-api | grep -i error
```

---

## 추가 리소스

- [FastAPI 공식 문서](https://fastapi.tiangolo.com/)
- [WebRTC Security Guide](https://webrtc.org/)
- [Coturn 문서](https://github.com/coturn/coturn)

---

**API 버전**: 1.0.0
**마지막 업데이트**: 2026-01-18
**작성자**: WebRTC-Lite Team
