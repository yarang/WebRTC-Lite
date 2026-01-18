# WebRTC-Lite Troubleshooting Guide

## 목차

- [빠른 진단 체크리스트](#빠른-진단-체크리스트)
- [TURN 서버 문제](#turn-서버-문제)
- [Firebase 시그널링 문제](#firebase-시그널링-문제)
- [클라이언트 연결 문제](#클라이언트-연결-문제)
- [네트워크 연결 문제](#네트워크-연결-문제)
- [성능 문제](#성능-문제)
- [보안 문제](#보안-문제)
- [로그 분석](#로그-분석)

---

## 빠른 진단 체크리스트

### 1단계: 서비스 상태 확인

```bash
# Coturn 서비스 상태
sudo systemctl status coturn

# TURN API 서비스 상태
sudo systemctl status turn-credentials-api

# 방화벽 규칙 확인
sudo iptables -L -n -v

# 포트 수신 대기 확인
sudo netstat -tulpn | grep -E ':(3478|5349|8080)'
```

### 2단계: 네트워크 연결 확인

```bash
# TURN 서버 연결 테스트
nc -zuv <TURN_SERVER_IP> 3478

# TLS 연결 테스트
openssl s_client -connect <TURN_SERVER_IP>:5349

# STUN 요청 테스트
turnutils_uclient -v -u testuser -w testpass <TURN_SERVER_IP> -p 3478
```

### 3단계: Firebase 연결 확인

```bash
# Firebase 배포 상태 확인
firebase deploy --only firestore:rules --dry-run

# Firestore 인덱스 상태 확인
firebase firestore:indexes list
```

---

## TURN 서버 문제

### 문제 1: Coturn 서비스가 시작되지 않음

**증상**:
```bash
sudo systemctl start coturn
# Job for coturn.service failed
```

**원인 분석**:
1. 설정 파일 문법 오류
2. TLS 인증서 누락
3. 포트 충돌

**해결 방법**:

1. 설정 파일 검증:
```bash
# 문법 검증
sudo coturn --check-config -c /etc/turnserver.conf

# 상세 로그 확인
sudo journalctl -u coturn -n 50 --no-pager
```

2. TLS 인증서 확인:
```bash
# 인증서 존재 확인
ls -la /etc/letsencrypt/live/<your-domain>/

# 인증서 없으면 STUN-only 모드로 시작
# /etc/turnserver.conf에서 tls-listening-port 주석 처리
sudo systemctl restart coturn
```

3. 포트 충돌 확인:
```bash
# 포트 사용 중인 프로세스 확인
sudo lsof -i :3478
sudo lsof -i :5349

# 충돌하는 프로세스 종료
sudo kill -9 <PID>
```

### 문제 2: TURN 인증 실패

**증상**:
```
401 Unauthorized
ERROR: Cannot turn on TURN functionality
```

**원인 분석**:
1. TURN_SECRET 환경변수 미설정
2. 사용자 이름 형식 오류 (timestamp:username)
3. HMAC-SHA1 불일치

**해결 방법**:

1. TURN_SECRET 설정 확인:
```bash
# API 서버에서 환경변수 확인
echo $TURN_SECRET

# 없으면 생성 및 설정
export TURN_SECRET=$(openssl rand -base64 32)
echo "TURN_SECRET=$TURN_SECRET" | sudo tee -a /etc/environment

# 서비스 재시작
sudo systemctl restart turn-credentials-api
```

2. Coturn 비밀번호 동기화:
```bash
# /etc/turnserver.conf에 동일한 비밀 설정
sudo nano /etc/turnserver.conf
# 추가: user=turnuser:0x<HEX_SECRET>

# 또는 REST API 사용
# /etc/turnserver.conf
rest-api-separator=:
use-auth-secret
static-auth-secret=<YOUR_TURN_SECRET>
```

### 문제 3: TURN 연결 시간 초과

**증상**:
```
ICE failed, TURN allocation timeout
```

**원인 분석**:
1. Oracle Cloud 방화벽 규칙 미설정
2. NAT 트래버설 실패
3. 대역폭 제한 초과

**해결 방법**:

1. Oracle Cloud Security List 확인:
```bash
# Oracle Cloud Console > Networking > Security Lists
# 다음 포트 인바운드 규칙 추가:
# - TCP 3478, 3479
# - UDP 3478, 3479
# - TCP 5349, 5350
# - UDP 49152-65535
```

2. iptables 규칙 확인:
```bash
# 규칙 확인
sudo iptables -L -n -v | grep -E '3478|5349'

# 규칙 추가
sudo iptables -I INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 49152:65535 -j ACCEPT

# 영구 저장
sudo netfilter-persistent save
```

3. 대역폭 제한 확인:
```bash
# 현재 세션 수 확인
sudo turnserver -n -v | grep "Total sessions"

# 제한 증설 (turnserver.conf)
max-bps-capacity=0  # 무제한
total-quota=1000
```

---

## Firebase 시그널링 문제

### 문제 1: Firestore 접근 거부 (Permission Denied)

**증상**:
```
FirebaseError: Missing or insufficient permissions
```

**원인 분석**:
1. 인증되지 않은 사용자 접근
2. Firestore 보안 규칙 오류
3. 참여자 검증 실패

**해결 방법**:

1. Firebase Auth 확인:
```kotlin
// Android
val user = FirebaseAuth.getInstance().currentUser
if (user == null) {
    FirebaseAuth.getInstance().signInAnonymously()
}
```

```swift
// iOS
let user = Auth.auth().currentUser
if user == nil {
    Auth.auth().signInAnonymously()
}
```

2. 보안 규칙 테스트:
```bash
# Firebase Console > Firestore > Rules
# Rules Playground에서 테스트

# 또는 CLI로 테스트
firebase firestore:test --rules firestore.rules
```

3. 보안 규칙 수정:
```javascript
// firestore.rules
match /webrtc_sessions/{sessionId} {
  allow read: if isParticipant(request.resource);
  allow write: if isCaller(request.resource) ||
                    isCallee(request.resource);
}
```

### 문제 2: 시그널링 지연 (Signaling Delay)

**증상**:
- Offer/Answer 교환에 5초 이상 소요
- ICE candidate 수신 지연

**원인 분석**:
1. Firestore 인덱스 미설정
2. 리스너 설정 오류
3. 네트워크 지연

**해결 방법**:

1. 인덱스 생성:
```bash
# firestore.indexes.json 배포
firebase deploy --only firestore:indexes

# 또는 Firebase Console에서 수동 생성
# Indexes > Composite Index > Add
# - Collection: webrtc_sessions
# - Fields: caller_id (Ascending), created_at (Descending)
```

2. 리스너 최적화:
```kotlin
// Android - Metadata Changes만 리스너
db.collection("webrtc_sessions")
    .document(sessionId)
    .addSnapshotListener(MetadataChanges.INCLUDE) { snapshot, e ->
        // 변경사항만 처리
    }
```

```swift
// iOS - includeMetadataChanges
db.collection("webrtc_sessions")
    .document(sessionId)
    .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
        // 변경사항만 처리
    }
```

### 문제 3: 세션 문서 자동 삭제 안 됨

**증상**:
- 종료된 통화 세션이 Firestore에 계속 남음
- Storage quota 초과

**원인 분석**:
1. TTL 설정 누락
2. Cloud Functions 미배포
3. 세션 상태 업데이트 실패

**해결 방법**:

1. Firestore TTL 설정:
```bash
# Firestore는 자동 TTL을 지원하지 않음
# Cloud Functions Scheduled Functions 사용

# functions/index.js
exports.deleteOldSessions = functions.pubsub
    .schedule('every 1 hours')
    .onRun(async (context) => {
        const cutoff = new Date(Date.now() - 3600000); // 1 hour ago
        const snapshot = await admin.firestore()
            .collection('webrtc_sessions')
            .where('updated_at', '<', cutoff)
            .get();

        const deletePromises = [];
        snapshot.forEach(doc => {
            deletePromises.push(doc.ref.delete());
        });

        await Promise.all(deletePromises);
        console.log(`Deleted ${deletePromises.length} old sessions`);
    });
```

2. 클라이언트에서 정리:
```kotlin
// Android - 통화 종료 시 세션 삭제
fun endCall(sessionId: String) {
    db.collection("webrtc_sessions")
        .document(sessionId)
        .delete()
}
```

---

## 클라이언트 연결 문제

### 문제 1: WebRTC PeerConnection 생성 실패

**증상**:
```
Failed to create PeerConnection
ICE state checking, then failed
```

**원인 분석**:
1. STUN/TURN 서버 URL 오류
2. TURN 자격 증명 만료
3. ICE candidate 수집 실패

**해결 방법**:

1. STUN/TURN URL 확인:
```kotlin
// Android
val iceServers = listOf(
    IceServer.builder("stun:$turnServerIp:3478").createIceServer(),
    IceServer.builder("turn:$turnServerIp:3478")
        .setUsername(turnCredentials.username)
        .setPassword(turnCredentials.password)
        .createIceServer()
)
```

```swift
// iOS
let iceServers: [RTCIceServer] = [
    RTCIceServer(url: "stun:\(turnServerIP):3478"),
    RTCIceServer(
        url: "turn:\(turnServerIP):3478",
        username: turnCredentials.username,
        credential: turnCredentials.password
    )
]
```

2. TURN 자격 증명 갱신:
```kotlin
// TTL이 60초 미만이면 갱신
if (turnCredentials.ttl < 60) {
    refreshTurnCredentials()
}
```

3. ICE candidate 타임아웃 증가:
```kotlin
// Android
val peerConnectionConstraints = MediaConstraints().apply {
    mandatory?.add(MediaConstraints.KeyValuePair(
        "iceRestart",
        "true"
    ))
}
```

### 문제 2: 카메라/마이크 권한 거부

**증상**:
```
Permission denied: CAMERA
Permission denied: RECORD_AUDIO
```

**원인 분석**:
1. 런타임 권한 미요청
2. AndroidManifest.xml/Info.plist 누락

**해결 방법**:

1. Android 권한 설정:
```xml
<!-- AndroidManifest.xml -->
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

```kotlin
// MainActivity.kt
if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA)
    != PackageManager.PERMISSION_GRANTED) {
    ActivityCompat.requestPermissions(
        this,
        arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO),
        PERMISSION_REQUEST_CODE
    )
}
```

2. iOS 권한 설정:
```xml
<!-- Info.plist -->
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for audio calls</string>
```

```swift
// Info.plist - Background Modes
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

---

## 네트워크 연결 문제

### 문제 1: NAT 트래버설 실패

**증상**:
- P2P 연결 실패
- TURN만으로 연결됨
- 대역폭 낭비

**원인 분석**:
1. Symmetric NAT 환경
2. STUN 서버 주소 오류
3. ICE candidate 수집 부족

**해결 방법**:

1. NAT 유형 확인:
```bash
# WebRTC에서 NAT 유형 확인
# https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/

# 결과가 "srflx"만 나오면 TURN 필요
```

2. 복수 STUN 서버 사용:
```kotlin
val iceServers = listOf(
    IceServer.builder("stun:stun.l.google.com:19302").createIceServer(),
    IceServer.builder("stun:$turnServerIp:3478").createIceServer()
)
```

3. ICE candidate 수집 최적화:
```kotlin
// 모든 candidate 수집 대기
peerConnection.createOffer(object : SdpObserver {
    override fun onCreateSuccess(sessionDescription: SessionDescription) {
        peerConnection.setLocalDescription(
            object : SdpObserver {
                override fun onSetSuccess() {
                    // ICE candidate 수집 대기
                    waitForIceGatheringComplete()
                }
                // ...
            },
            sessionDescription
        )
    }
    // ...
}, mediaConstraints)
```

### 문제 2: UDP 차단으로 인한 연결 실패

**증상**:
```
UDP port 3478 unreachable
```

**원인 분석**:
1. 방화벽에서 UDP 차단
2. 포트 포워딩 누락

**해결 방법**:

1. TCP over TLS 사용:
```kotlin
// TURNS (TCP 5349) 사용
val iceServers = listOf(
    IceServer.builder("turns:$turnServerIp:5349?transport=tcp")
        .setUsername(turnCredentials.username)
        .setPassword(turnCredentials.password)
        .createIceServer()
)
```

2. Oracle Cloud 포트 포워딩:
```bash
# Security List에 추가
# Ingress Rules:
# - Source: 0.0.0.0/0
# - IP Protocol: TCP
# - Destination Port: 5349
```

---

## 성능 문제

### 문제 1: 비디오 지연 (Latency)

**증상**:
- 2초 이상의 비디오 지연
- 오디오-비디오 동기화 불일치

**원인 분석**:
1. 네트워크 대역폭 부족
2. 비디오 코덱 비효율
3. TURN 서버 CPU 과부하

**해결 방법**:

1. 비디오 해상도 동적 조정:
```kotlin
// 네트워크 상태에 따라 해상도 조정
fun adjustVideoQuality(bandwidth: Long) {
    val constraints = when {
        bandwidth < 500_000 -> {
            // 500Kbps 미만: 240p
            createVideoConstraints(320, 240, 15)
        }
        bandwidth < 1_000_000 -> {
            // 1Mbps 미만: 480p
            createVideoConstraints(640, 480, 30)
        }
        else -> {
            // 1Mbps 이상: 720p
            createVideoConstraints(1280, 720, 30)
        }
    }
    peerConnection.setVideoConstraints(constraints)
}
```

2. 비트레이트 제한:
```kotlin
// Android
val videoEncoder = BitmapFactory()
videoEncoder.setBitrate(500_000) // 500Kbps
```

3. Coturn 최적화:
```bash
# /etc/turnserver.conf
max-bps=3000000  # 3Mbps per session
total-quota=300000  # Total bandwidth limit
```

### 문제 2: 오디오 에코 (Echo)

**증상**:
- 자신의 목소리가 들림
- 상대방 목소리 에코

**원인 분석**:
1. 스피커와 마이크 간섭
2. 에코 캔슬러 비활성화

**해결 방법**:

1. 에코 캔슬러 활성화:
```kotlin
// Android
val audioConstraints = MediaConstraints().apply {
    mandatory?.add(MediaConstraints.KeyValuePair(
        "echoCancellation",
        "true"
    ))
    mandatory?.add(MediaConstraints.KeyValuePair(
        "noiseSuppression",
        "true"
    ))
}
```

```swift
// iOS
let audioConstraints = RTCMediaConstraints(
    mandatoryConstraints: [
        "echoCancellation": "true",
        "noiseSuppression": "true"
    ],
    optionalConstraints: nil
)
```

---

## 보안 문제

### 문제 1: API 키 노출

**증상**:
- API 키가 클라이언트 코드에 하드코딩됨

**해결 방법**:

1. 환경변수 사용:
```kotlin
// BuildConfig에서 API 키 읽기
val apiKey = BuildConfig.TURN_API_KEY

// build.gradle
android {
    defaultConfig {
        buildConfigField "String", "TURN_API_KEY",
            "\"${System.getenv('TURN_API_KEY')}\""
    }
}
```

2. ProGuard/R8 난독화:
```gradle
// build.gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android.txt')
        }
    }
}
```

### 문제 2: TURN 비밀번호 노출

**증상**:
- 네트워크 패킷에 TURN 비밀번호 노출

**해결 방법**:

1. 짧은 TTL 사용:
```kotlin
// TTL 60초로 설정
val credentials = turnApiClient.getCredentials(
    username = userId,
    ttl = 60
)
```

2. HTTPS 전송만 허용:
```kotlin
// Android - Network Security Configuration
// res/xml/network_security_config.xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="true">your-turn-api.com</domain>
    </domain-config>
</network-security-config>
```

---

## 로그 분석

### Coturn 로그 분석

```bash
# 실시간 로그 모니터링
sudo tail -f /var/log/turnserver.log

# 에러만 필터링
sudo grep "ERROR" /var/log/turnserver.log | tail -20

# 특정 사용자 추적
sudo grep "username:user123" /var/log/turnserver.log

# 연결 실패 분석
sudo grep "allocation" /var/log/turnserver.log | grep "failed"
```

### TURN API 로그 분석

```bash
# API 로그 확인
sudo journalctl -u turn-credentials-api -f

# 401 에러 추적
sudo journalctl -u turn-credentials-api | grep "401"

# 자격 증명 발급 내역
sudo journalctl -u turn-credentials-api | grep "CREDENTIALS_ISSUED"
```

### WebRTC 클라이언트 로그

```bash
# Android Logcat
adb logcat -s WebRTC:D *:S

# iOS Console
# Xcode > Window > Devices and Simulators > Console
```

---

## 도구 및 리소스

### 진단 도구

1. **Trickle ICE**: https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
2. **WebRTC Internals**: chrome://webrtc-internals/
3. **turnutils_uclient**: Coturn 패키지 포함
4. **nc (netcat)**: 포트 연결 테스트
5. **openssl**: TLS 연결 테스트

### 유용한 명령어

```bash
# 네트워크 추적
sudo tcpdump -i any port 3478 -w turn.pcap

# 프로세스 모니터링
htop

# 포트 모니터링
sudo netstat -tulpn

# 방화벽 로그
sudo iptables -L -n -v
```

---

## 추가 지원

### 커뮤니티 리소스

- [WebRTC Google Group](https://groups.google.com/g/discuss-webrtc)
- [Coturn GitHub Issues](https://github.com/coturn/coturn/issues)
- [Firebase Community](https://firebase.community/)

### 버그 보고

버그를 발견하시면 [GitHub Issues](https://github.com/your-repo/webrtc-lite/issues)에 제출해 주세요. 다음 정보를 포함해 주시면 빠른 해결에 도움이 됩니다:

1. 환경 정보 (OS, 버전)
2. 재현 단계
3. 관련 로그
4. 스크린샷 (가능한 경우)

---

**문서 버전**: 1.0.0
**마지막 업데이트**: 2026-01-18
**작성자**: WebRTC-Lite Team
