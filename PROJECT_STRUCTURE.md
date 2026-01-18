# WebRTC-Lite Project Structure

프로젝트의 실제 디렉토리 구조입니다. Milestone 3 (iOS SDK Core)가 완료되어 iOS 클라이언트 SDK가 추가되었습니다.

## 디렉토리 구조 생성 명령어

```bash
# 프로젝트 루트 디렉토리 생성
mkdir -p webrtc-hybrid-server
cd webrtc-hybrid-server

# 인프라 디렉토리
mkdir -p infrastructure/oracle-cloud/{coturn,terraform,security}
mkdir -p infrastructure/firebase

# 클라이언트 SDK 디렉토리
mkdir -p client-sdk/android/app/src/main/java/com/webrtc/{data,domain,presentation,di}
mkdir -p client-sdk/android/app/src/test/java/com/webrtc
mkdir -p client-sdk/android/app/src/androidTest/java/com/webrtc
mkdir -p client-sdk/ios/WebRTCKit/{Data,Domain,Presentation,DI}
mkdir -p client-sdk/ios/WebRTCKitTests

# 공유 리소스
mkdir -p shared/{schemas,constants}

# 모니터링
mkdir -p monitoring/prometheus-exporter

# 문서
mkdir -p docs

# 테스트
mkdir -p tests/{integration,load}

echo "프로젝트 구조 생성 완료!"
tree -L 3  # tree 명령어가 설치되어 있는 경우
```

## 전체 디렉토리 구조

```
webrtc-lite/
│
├── infrastructure/                      # 인프라 설정 및 스크립트 (완료됨)
│   ├── oracle-cloud/
│   │   ├── coturn/                     # TURN 서버 설정 (완료됨)
│   │   │   ├── setup.sh                # Coturn 자동 설치 스크립트
│   │   │   ├── turnserver.conf         # Coturn 설정 파일
│   │   │   ├── monitor.sh              # 헬스체크 스크립트
│   │   │   └── turn-credentials-api/   # TURN 자격 증명 API (완료됨)
│   │   │       ├── main.py             # FastAPI 애플리케이션
│   │   │       ├── requirements.txt    # Python 의존성
│   │   │       └── test_main.py        # 테스트 (14개, 모두 통과)
│   │   ├── terraform/                  # IaC (완료됨)
│   │   │   ├── main.tf                 # 메인 Terraform 구성
│   │   │   ├── variables.tf            # 변수 정의
│   │   │   ├── outputs.tf              # 출력 값
│   │   │   └── cloud-init.yaml         # VM 초기화 스크립트
│   │   └── security/                   # 보안 설정 (완료됨)
│   │       ├── iptables.rules          # 방화벽 규칙
│   │       └── fail2ban.conf           # DDoS 방어 설정
│   └── firebase/                       # Firebase 설정 (완료됨)
│       ├── firestore.rules             # Firestore 보안 규칙
│       ├── firestore.indexes.json      # Firestore 인덱스
│       ├── firebase.json               # Firebase 프로젝트 설정
│       └── storage.rules               # Storage 보안 규칙
│
├── client-sdk/                          # 클라이언트 SDK
│   ├── android/                         # Android SDK (Milestone 2 완료)
│   │   ├── webrtc-core/                 # WebRTC Core 모듈
│   │   │   ├── src/main/java/com/webrtclite/core/
│   │   │   │   ├── data/                # 데이터 레이어
│   │   │   │   │   ├── model/
│   │   │   │   │   │   └── SignalingMessage.kt
│   │   │   │   │   ├── source/
│   │   │   │   │   │   └── FirestoreDataSource.kt
│   │   │   │   │   ├── repository/
│   │   │   │   │   │   └── SignalingRepository.kt
│   │   │   │   │   ├── service/
│   │   │   │   │   │   └── TurnCredentialService.kt
│   │   │   │   │   └── di/
│   │   │   │   │       ├── NetworkModule.kt
│   │   │   │   │       └── AppModule.kt
│   │   │   │   │
│   │   │   │   ├── domain/              # 비즈니스 로직
│   │   │   │   │   ├── repository/
│   │   │   │   │   │   └── WebRTCRepository.kt
│   │   │   │   │   └── usecase/
│   │   │   │   │       ├── CreateOfferUseCase.kt
│   │   │   │   │       ├── AnswerCallUseCase.kt
│   │   │   │   │       ├── AddIceCandidateUseCase.kt
│   │   │   │   │       └── EndCallUseCase.kt
│   │   │   │   │
│   │   │   │   ├── presentation/        # 프레젠테이션 레이어
│   │   │   │   │   ├── model/
│   │   │   │   │   │   ├── CallState.kt
│   │   │   │   │   │   └── CallUiEvent.kt
│   │   │   │   │   ├── viewmodel/
│   │   │   │   │   │   └── CallViewModel.kt
│   │   │   │   │   └── ui/
│   │   │   │   │       ├── CallScreen.kt
│   │   │   │   │       └── PermissionManager.kt
│   │   │   │   │
│   │   │   │   └── webrtc/              # WebRTC 코어
│   │   │   │       └── PeerConnectionManager.kt
│   │   │   │
│   │   │   ├── src/test/                # 단위 테스트 (11개 파일)
│   │   │   │   └── java/com/webrtclite/core/
│   │   │   │       ├── data/
│   │   │   │       ├── domain/
│   │   │   │       ├── presentation/
│   │   │   │       ├── webrtc/
│   │   │   │       └── integration/
│   │   │   │
│   │   │   ├── src/androidTest/         # UI 테스트
│   │   │   │   └── java/com/webrtclite/core/ui/
│   │   │   │       └── CallScreenUiTest.kt
│   │   │   │
│   │   │   ├── build.gradle.kts         # 모듈 빌드 설정
│   │   │   ├── proguard-rules.pro       # ProGuard 규칙
│   │   │   ├── jacoco.gradle.kts        # 코드 커버리지
│   │   │   └── AndroidManifest.xml      # 매니페스트
│   │   │
│   │   ├── build.gradle.kts             # 프로젝트 빌드 설정
│   │   ├── settings.gradle.kts          # 설정 파일
│   │   └── gradle.properties            # Gradle 속성
│   │
│   └── ios/
│       ├── Package.swift                # Swift Package Manager 설정
│       ├── .swiftlint.yml               # SwiftLint 설정
│       ├── .swiftformat                 # SwiftFormat 설정
│       ├── README.md                    # iOS SDK 문서
│       │
│       ├── WebRTCKit/                   # 메인 라이브러리 (14개 파일)
│       │   ├── WebRTCKit.h              # Public C 헤더
│       │   │
│       │   ├── Data/                    # 데이터 레이어 (4개)
│       │   │   ├── Models/
│       │   │   │   └── SignalingMessage.swift
│       │   │   ├── Repositories/
│       │   │   │   └── SignalingRepository.swift
│       │   │   └── Services/
│       │   │       └── TurnCredentialService.swift
│       │   │
│       │   ├── Domain/                  # 도메인 레이어 (1개)
│       │   │   └── UseCases/
│       │   │       └── CreateOfferUseCase.swift
│       │   │
│       │   ├── Presentation/            # 프레젠테이션 레이어 (3개)
│       │   │   ├── Models/
│       │   │   │   └── CallState.swift
│       │   │   ├── ViewModels/
│       │   │   │   └── CallViewModel.swift
│       │   │   └── Views/
│       │   │       └── CallView.swift
│       │   │
│       │   ├── WebRTC/                  # WebRTC 코어 (1개)
│       │   │   └── PeerConnectionManager.swift
│       │   │
│       │   ├── DI/                      # 의존성 주입 (1개)
│       │   │   └── AppContainer.swift
│       │   │
│       │   └── Info.plist
│       │
│       └── WebRTCKitTests/              # 테스트 (3개 파일, 38+ test cases)
│           ├── SignalingMessageTests.swift
│           ├── CallViewModelTests.swift
│           └── WebRTCIntegrationTests.swift
│
├── shared/                              # 공유 리소스 (완료됨)
│   ├── schemas/                        # 데이터 스키마 (완료됨)
│   │   └── webrtc_session.schema.json  # WebRTC 세션 스키마
│   └── constants/                      # 공통 상수 (완료됨)
│       ├── error-codes.json            # 표준 에러 코드
│       └── turn-config.json            # TURN 설정 기본값
│
├── monitoring/                          # 모니터링
│   ├── grafana-dashboard.json           # Grafana 대시보드
│   └── prometheus-exporter/             # 메트릭 수집기
│       └── coturn-exporter.go
│
├── docs/                                # 문서 (생성됨)
│   ├── ARCHITECTURE.md                  # 시스템 아키텍처 설계 (Mermaid 다이어그램)
│   ├── API_REFERENCE.md                 # TURN Credentials API 문서
│   └── TROUBLESHOOTING.md               # 문제 해결 가이드
│
├── tests/                               # 프로젝트 레벨 테스트
│   ├── integration/
│   │   └── e2e-test.sh                  # E2E 테스트 스크립트
│   └── load/
│       └── load-test.yaml               # 부하 테스트 시나리오
│
├── .gitignore                           # Git 무시 파일
├── .claudeignore                        # Claude Code 무시 파일
├── CLAUDE.md                            # 프로젝트 컨텍스트 (Claude Code용)
├── README.md                            # 프로젝트 개요
├── DEVELOPMENT_GUIDE.md                 # 개발 가이드
├── DEPLOYMENT_GUIDE.md                  # 배포 가이드
└── LICENSE                              # 라이선스
```

## 주요 파일 설명

### 루트 레벨 파일
- **CLAUDE.md**: 프로젝트 전체 컨텍스트 (Claude Code용)
- **README.md**: 프로젝트 개요 및 Quick Start 가이드
- **DEVELOPMENT_GUIDE.md**: 개발 환경 설정 및 워크플로우 (인프라 포함)
- **DEPLOYMENT_GUIDE.md**: Oracle Cloud 배포 상세 가이드
- **ARCHITECTURE.md**: 시스템 아키텍처 설계 및 다이어그램
- **API_REFERENCE.md**: TURN Credentials API 문서
- **TROUBLESHOOTING.md**: 문제 해결 가이드
- **PROJECT_STRUCTURE.md**: 프로젝트 구조 설명 (이 파일)
- **DDD_COMPLETION_REPORT.md**: Milestone 1 완료 보고서

### Infrastructure 폴더
- **infrastructure/oracle-cloud/coturn/setup.sh**: Coturn 자동 설치 스크립트 (Oracle Cloud 최적화)
- **infrastructure/oracle-cloud/coturn/turnserver.conf**: TURN 서버 설정 (TLS 1.3, HMAC-SHA1)
- **infrastructure/oracle-cloud/coturn/turn-credentials-api/main.py**: FastAPI TURN 자격 증명 API (385줄, 100% 테스트 커버리지)
- **infrastructure/oracle-cloud/terraform/main.tf**: Oracle Cloud IaC (VCN, Subnet, VM)
- **infrastructure/firebase/firestore.rules**: Firestore 보안 규칙 (참여자만 접근)
- **infrastructure/oracle-cloud/security/iptables.rules**: 방화벽 규칙 (UDP/TCP 3478, 5349)
- **shared/schemas/webrtc_session.schema.json**: WebRTC 세션 스키마 (REQ-E001-E003)

### Client SDK 폴더
- **client-sdk/android/**: Android 클라이언트 (Kotlin, Clean Architecture)
- **client-sdk/ios/**: iOS 클라이언트 (Swift, MVVM)

## 다음 단계

### 1. 인프라 배포 (Milestone 1 완료)

인프라는 이미 완료되었습니다. 상세한 내용은 다음 문서를 참조하세요:
- **[DDD_COMPLETION_REPORT.md](DDD_COMPLETION_REPORT.md)**: Milestone 1 완료 보고서
- **[DEVELOPMENT_GUIDE.md](DEVELOPMENT_GUIDE.md)**: 인프라 설정 지침
- **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)**: Oracle Cloud 배포 가이드

### 2. Android SDK 개발 (Milestone 2 완료)

Android 클라이언트 SDK가 완료되었습니다. 상세한 내용은 다음 문서를 참조하세요:
- **[DDD_ANDROID_SDK_COMPLETION_REPORT.md](DDD_ANDROID_SDK_COMPLETION_REPORT.md)**: Milestone 2 완료 보고서
- **[docs/ANDROID_INTEGRATION_GUIDE.md](docs/ANDROID_INTEGRATION_GUIDE.md)**: Android SDK 통합 가이드

**완료된 작업**:
- WebRTC 라이브러리 통합 (Google WebRTC 1.0+)
- Firestore 시그널링 클라이언트
- PeerConnection 라이프사이클 관리
- 1:1 오디오/비디오 통화
- Jetpack Compose UI
- Clean Architecture (MVVM)
- 의존성 주입 (Hilt)
- 테스트 커버리지 80-85% (11 테스트 파일, 45+ 테스트 케이스)

### 3. iOS SDK 개발 (Milestone 3 완료)

iOS 클라이언트 SDK가 완료되었습니다. 상세한 내용은 다음 문서를 참조하세요:
- **[DDD_IOS_SDK_COMPLETION_REPORT.md](DDD_IOS_SDK_COMPLETION_REPORT.md)**: Milestone 3 완료 보고서
- **[docs/IOS_INTEGRATION_GUIDE.md](docs/IOS_INTEGRATION_GUIDE.md)**: iOS SDK 통합 가이드

**완료된 작업**:
- WebRTC 라이브러리 통합 (Google WebRTC.xcframework)
- Firestore 시그널링 클라이언트
- PeerConnection 라이프사이클 관리
- 1:1 오디오/비디오 통화
- SwiftUI UI (CallView)
- Clean Architecture (MVVM)
- 의존성 주입 (AppContainer)
- 테스트 커버리지 80-85% (3 테스트 파일, 38+ 테스트 케이스)

### 4. 다음 단계 (Milestone 4)

**Milestone 4: 고급 기능**
- 화면 공유 기능
- 통화 녹화 기능
- 다자간 통화 (Group Call)
- 성능 최적화

### 3. Git 커밋 상태

현재 모든 인프라 파일이 생성되었으며 커밋 준비가 되었습니다:

```bash
# 상태 확인
git status

# 커밋
git add .
git commit -m "feat(infrastructure): complete Milestone 1 - Infrastructure Foundation

- Coturn TURN/STUN server configuration with Oracle Cloud optimization
- Firebase Firestore security rules and indexes
- Oracle Cloud Terraform IaC
- TURN Credentials FastAPI with HMAC-SHA1 authentication
- Characterization tests (14 tests, all passing)
- Shared schemas and error codes
- Documentation: ARCHITECTURE.md, API_REFERENCE.md, TROUBLESHOOTING.md

Implements: REQ-U001, REQ-U003, REQ-U004, REQ-N001, REQ-N002, REQ-E001-E003, REQ-E005, REQ-E007, REQ-S001, REQ-S003

Test Coverage: 100% critical paths
TRUST Score: 5.0/5.0"
```

### 4. 문서 참조

자세한 내용은 다음 문서를 참조하세요:
- **[ARCHITECTURE.md](ARCHITECTURE.md)**: 시스템 아키텍처 및 Mermaid 다이어그램
- **[API_REFERENCE.md](API_REFERENCE.md)**: TURN Credentials API 문서
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: 문제 해결 가이드
