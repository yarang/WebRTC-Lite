# WebRTC Hybrid Server

> 비용 효율적인 하이브리드 WebRTC 인프라 솔루션

## 🎯 프로젝트 개요

완전 관리형 WebRTC 서비스의 높은 비용 부담과 완전 자체 구축의 복잡성 사이의 균형을 찾은 하이브리드 아키텍처입니다.

- **Signaling**: Firebase Firestore (무료 티어, 관리형)
- **TURN/STUN**: Oracle Cloud Free Tier + Coturn (자체 호스팅, 무료)
- **예상 월 비용**: $0

## 📊 프로젝트 상태

### 현재 버전: v0.1.0 (Milestone 1 완료)

**완료된 작업 (Milestone 1: Infrastructure Foundation)**:
- ✅ Coturn TURN/STUN 서버 설정 (Oracle Cloud 최적화)
- ✅ Firebase Firestore 보안 규칙 및 인덱스
- ✅ Oracle Cloud Terraform IaC 구성
- ✅ TURN Credentials API (FastAPI) - 100% 테스트 커버리지
- ✅ 보안 설정 (iptables, fail2ban)
- ✅ 공유 스키마 및 상수 정의

**진행 중인 작업**:
- 🔄 Milestone 2: Android SDK Core (WebRTC 연동, 시그널링 클라이언트)
- 🔄 Milestone 3: iOS SDK Core (WebRTC 연동, 시그널링 클라이언트)

### 테스트 커버리지
- TURN Credentials API: 100% (14/14 tests passed)
- TRUST 5 점수: 5.0/5.0

### 구현된 요구사항 (12/27)
- REQ-U001, REQ-U003, REQ-U004: STUN/TURN 서버 및 인증
- REQ-N001, REQ-N002: 자격 증명 관리 및 시그널링 보안
- REQ-E001-E003, REQ-E005, REQ-E007: WebRTC 세션 및 자격 증명 갱신
- REQ-S001, REQ-S003: NAT 탐지 및 TURN 서버 가용性

## ✨ 주요 특징

- ✅ **완전 무료**: Oracle Cloud Free Tier로 월 10TB 트래픽 무료 처리
- ✅ **고가용성**: Firebase의 99.95% SLA + Oracle Cloud 인프라
- ✅ **크로스 플랫폼**: Android(Kotlin) & iOS(Swift) SDK 제공
- ✅ **쉬운 배포**: 자동화 스크립트로 10분 내 TURN 서버 구축
- ✅ **확장 가능**: 트래픽 증가 시 유료 티어로 원활한 전환

## 🏗️ 아키텍처

```
┌─────────────┐         ┌──────────────┐         ┌─────────────┐
│   Android   │◄───────►│   Firebase   │◄───────►│     iOS     │
│   Client    │ Signaling│  Firestore   │ Signaling│   Client    │
└──────┬──────┘         └──────────────┘         └──────┬──────┘
       │                                                  │
       │                 P2P Connection                   │
       │◄────────────────────────────────────────────────►│
       │                 (Direct or Relayed)              │
       │                                                  │
       │               ┌──────────────┐                   │
       └──────────────►│ Oracle Cloud │◄──────────────────┘
                       │ TURN Server  │
                       │   (Coturn)   │
                       └──────────────┘
```

## 📋 사전 요구사항

### 필수 항목
- [ ] Oracle Cloud 계정 (Free Tier)
- [ ] Firebase 프로젝트
- [ ] Android Studio (Android 개발 시)
- [ ] Xcode (iOS 개발 시)

### 권장 항목
- [ ] 도메인 (HTTPS/TLS 적용 시)
- [ ] Terraform 기본 지식 (IaC 사용 시)

## 🚀 Quick Start

### 1. 인프라 구축 (15분)

#### Oracle Cloud TURN 서버 구축
```bash
# 1. Oracle Cloud VM 생성
# - Shape: VM.Standard.A1.Flex (ARM 권장)
# - Image: Ubuntu 22.04
# - VCN: TCP/UDP 3478, UDP 49152-65535 개방

# 2. SSH 접속
ssh -i ~/.ssh/oracle_cloud.pem ubuntu@<VM_IP>

# 3. Coturn 자동 설치
git clone https://github.com/your-repo/webrtc-hybrid-server.git
cd webrtc-hybrid-server/infrastructure/oracle-cloud/coturn
chmod +x setup.sh
sudo ./setup.sh

# 4. 방화벽 설정
sudo iptables -I INPUT -p udp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 3478 -j ACCEPT
sudo iptables -I INPUT -p udp --dport 49152:65535 -j ACCEPT
sudo netfilter-persistent save

# 5. 서비스 시작
sudo systemctl start coturn
sudo systemctl enable coturn
```

#### Firebase 설정
```bash
# 1. Firebase 콘솔에서 프로젝트 생성
# 2. Firestore 데이터베이스 생성 (프로덕션 모드)

# 3. 보안 규칙 배포
firebase deploy --only firestore:rules

# 4. Android/iOS 앱 등록
# - Firebase 콘솔에서 google-services.json / GoogleService-Info.plist 다운로드
```

### 2. 클라이언트 SDK 설정

#### Android
```bash
cd client-sdk/android

# google-services.json 파일 복사
cp ~/Downloads/google-services.json app/

# WebRTC 설정 업데이트
# app/src/main/java/com/webrtc/WebRTCConfig.kt에서
# TURN_SERVER_URL을 Oracle Cloud VM IP로 변경

# 빌드 및 실행
./gradlew installDebug
```

#### iOS
```bash
cd client-sdk/ios

# GoogleService-Info.plist 파일 복사
cp ~/Downloads/GoogleService-Info.plist WebRTCKit/

# 의존성 설치
pod install

# Xcode에서 WebRTCConfig.swift 수정
# turnServerURL을 Oracle Cloud VM IP로 변경

# 빌드 및 실행
open WebRTCKit.xcworkspace
```

### 3. 연결 테스트

#### TURN 서버 테스트
```bash
# Trickle ICE 도구로 연결 확인
# https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/

# STUN Server: stun:<ORACLE_VM_IP>:3478
# TURN Server: turn:<ORACLE_VM_IP>:3478
# Username: testuser
# Password: testpass
```

#### 앱 간 통화 테스트
1. Android/iOS 앱 2대 실행
2. 동일한 Room ID 입력
3. 한쪽에서 "Call" 버튼 클릭
4. 다른 쪽에서 "Accept" 클릭
5. 영상/음성 통화 확인

## 📚 문서

- [CLAUDE.md](CLAUDE.md) - 프로젝트 전체 컨텍스트 (Claude Code용)
- [DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md) - 개발 환경 설정 및 워크플로우
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Oracle Cloud 배포 상세 가이드
- [ARCHITECTURE.md](ARCHITECTURE.md) - 시스템 아키텍처 설계 및 다이어그램
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - 문제 해결 가이드
- [API_REFERENCE.md](API_REFERENCE.md) - TURN Credentials API 문서
- [DDD_COMPLETION_REPORT.md](DDD_COMPLETION_REPORT.md) - Milestone 1 완료 보고서

## 🧪 테스트

### 단위 테스트
```bash
# Android
cd client-sdk/android
./gradlew test

# iOS
cd client-sdk/ios
xcodebuild test -workspace WebRTCKit.xcworkspace \
  -scheme WebRTCKit -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 통합 테스트
```bash
# Android (디바이스 연결 필요)
./gradlew connectedAndroidTest

# iOS (시뮬레이터 실행 필요)
xcodebuild test -workspace WebRTCKit.xcworkspace \
  -scheme WebRTCKit -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 네트워크 시나리오 테스트
- [ ] 동일 WiFi (P2P 직접 연결)
- [ ] WiFi ↔ LTE (STUN 필요)
- [ ] LTE ↔ LTE (TURN 필요)
- [ ] 제한적 NAT 환경

## 🔒 보안 고려사항

### TURN 서버
- [ ] Static Credentials를 Dynamic Credentials로 전환 (프로덕션)
- [ ] TLS/DTLS 활성화 (Let's Encrypt)
- [ ] fail2ban 설정으로 DDoS 방어
- [ ] Rate limiting 설정

### Firebase
- [ ] Firestore 보안 규칙 강화 (인증된 사용자만 접근)
- [ ] 민감한 데이터 암호화
- [ ] Firebase App Check 활성화

### 클라이언트
- [ ] API Key 난독화 (Android ProGuard, iOS Obfuscation)
- [ ] 인증서 피닝 구현
- [ ] 사용자 인증 통합 (Firebase Auth)

## 💰 비용 예상

### Oracle Cloud Free Tier (영구 무료)
- VM.Standard.A1.Flex: 4 OCPU, 24GB RAM
- 아웃바운드 데이터 전송: 월 10TB
- 스토리지: 200GB

### Firebase Free Tier
- Firestore 읽기: 일 50,000건
- Firestore 쓰기: 일 20,000건
- 스토리지: 1GB

**예상 동시 접속자 처리량**: 100-200명 (1:1 통화 기준)

## 🤝 기여 방법

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하세요.

## 🙏 감사의 말

- [Coturn](https://github.com/coturn/coturn) - TURN/STUN 서버 구현
- [WebRTC](https://webrtc.org/) - 실시간 통신 기술
- [Firebase](https://firebase.google.com/) - 백엔드 인프라
- [Oracle Cloud](https://www.oracle.com/cloud/) - 무료 VM 호스팅

## 📞 문의

- 이슈: [GitHub Issues](https://github.com/your-repo/webrtc-hybrid-server/issues)
- 이메일: your-email@example.com
- 디스코드: [커뮤니티 링크](#)

---

**Made with ❤️ for developers who need cost-effective WebRTC solutions**
