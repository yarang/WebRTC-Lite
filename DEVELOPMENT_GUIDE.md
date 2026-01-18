# Development Guide

## 목차
- [개발 환경 설정](#개발-환경-설정)
- [프로젝트 구조](#프로젝트-구조)
- [개발 워크플로우](#개발-워크플로우)
- [고급 기능 개발](#고급-기능-개발)
- [코딩 컨벤션](#코딩-컨벤션)
- [테스트 전략](#테스트-전략)
- [디버깅 가이드](#디버깅-가이드)
- [성능 최적화](#성능-최적화)

---

## 개발 환경 설정

### 인프라 개발 환경 (Milestone 1 완료)

#### 필수 소프트웨어
- **Oracle Cloud Account**: Free Tier 계정
- **Terraform**: 1.0+ (IaC)
- **Firebase CLI**: 12.0+
- **Python**: 3.12+ (TURN API)
- **Docker**: (옵션) 컨테이너화된 개발

#### Oracle Cloud TURN 서버 설정

**1. Terraform으로 인프라 프로비저닝**:
```bash
cd infrastructure/oracle-cloud/terraform

# Oracle Cloud 자격 증명 설정
export TF_VAR_tenancy_ocid="ocid1.tenancy.oc1..."
export TF_VAR_user_ocid="ocid1.user.oc1..."
export TF_VAR_fingerprint="00:00:00:00"
export TF_VAR_private_key_path="~/.oci/oci_api_key.pem"
export TF_VAR_region="ap-seoul-1"

# Terraform 초기화 및 적용
terraform init
terraform plan
terraform apply
```

**2. Coturn TURN 서버 설치**:
```bash
# VM에 SSH 접속
ssh -i ~/.ssh/oracle_cloud.pem ubuntu@<VM_PUBLIC_IP>

# Coturn 자동 설치 스크립트 실행
cd /path/to/webrtc-lite/infrastructure/oracle-cloud/coturn
chmod +x setup.sh
sudo ./setup.sh

# 방화벽 규칙 적용
sudo iptables-restore < /etc/iptables.rules
sudo netfilter-persistent save

# Coturn 서비스 시작
sudo systemctl start coturn
sudo systemctl enable coturn
```

**3. TURN Credentials API 배포**:
```bash
cd infrastructure/oracle-cloud/coturn/turn-credentials-api

# Python 가상 환경 생성
python3 -m venv venv
source venv/bin/activate

# 의존성 설치
pip install -r requirements.txt

# 환경변수 설정
export TURN_SECRET=$(openssl rand -base64 32)
export TURN_SERVER=<VM_PUBLIC_IP>
export TURN_PORT=5349
export API_KEY=$(openssl rand -hex 16)

# 서비스 시작
python -m uvicorn main:app --host 0.0.0.0 --port 8080

# 또는 systemd 서비스로 등록
sudo cp turn-credentials-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl start turn-credentials-api
```

**4. Firebase 설정**:
```bash
cd infrastructure/firebase

# Firebase CLI 로그인
firebase login

# Firestore 보안 규칙 배포
firebase deploy --only firestore:rules

# Firestore 인덱스 배포
firebase deploy --only firestore:indexes
```

#### 로컬 개발 환경 설정

**TURN API 로컬 테스트**:
```bash
cd infrastructure/oracle-cloud/coturn/turn-credentials-api

# 테스트 실행
pytest test_main.py -v

# 커버리지 확인
pytest test_main.py --cov=main --cov-report=html
```

**Firebase 에뮬레이터**:
```bash
# Firestore 에뮬레이터 시작
firebase emulators:start --only firestore

# 에뮬레이터 데이터베이스 초기화
firebase emulators:start --only firestore --import=./emulator-data
```

---

### Android 개발 환경 (Milestone 2 완료)

#### 필수 소프트웨어
- **Android Studio**: Hedgehog (2023.1.1) 이상
- **JDK**: 17 이상
- **Gradle**: 8.2+ (Kotlin DSL)
- **Android SDK**: API 24 (최소), API 34 (타겟)
- **Kotlin**: 1.9.0+

#### 환경 설정 단계
```bash
# 1. 프로젝트 클론
git clone https://github.com/your-repo/webrtc-hybrid-server.git
cd webrtc-hybrid-server/client-sdk/android

# 2. 로컬 설정 파일 생성
echo "sdk.dir=$ANDROID_HOME" > local.properties

# 3. Firebase 설정 파일 추가
# Firebase Console에서 google-services.json 다운로드
# 프로젝트: webrtc-core 모듈
cp ~/Downloads/google-services.json webrtc-core/src/

# 4. WebRTC 설정 업데이트
# webrtc-core/src/main/java/com/webrtclite/core/webrtc/PeerConnectionManager.kt
# TURN_SERVER_URL을 Oracle Cloud VM IP로 변경

# 5. Gradle Sync
./gradlew build

# 6. 디바이스/에뮬레이터에 설치
./gradlew :webrtc-core:installDebug

# 7. 테스트 실행
./gradlew :webrtc-core:testDebugUnitTest
```

#### 프로젝트 구조
Android 프로젝트는 **Clean Architecture**로 구성되었습니다:

```
client-sdk/android/
├── webrtc-core/                    # 메인 모듈
│   ├── src/main/java/com/webrtclite/core/
│   │   ├── data/                   # 데이터 레이어
│   │   │   ├── model/              # DTO, 엔티티
│   │   │   ├── source/             # 데이터 소스 (Firestore)
│   │   │   ├── repository/         # Repository 구현
│   │   │   ├── service/            # TURN 자격 증명 서비스
│   │   │   └── di/                 # 의존성 주입 (Hilt)
│   │   ├── domain/                 # 도메인 레이어
│   │   │   ├── repository/         # Repository 인터페이스
│   │   │   └── usecase/            # 유즈 케이스
│   │   ├── presentation/           # 프레젠테이션 레이어
│   │   │   ├── model/              # UI 상태, 이벤트
│   │   │   ├── viewmodel/          # ViewModel
│   │   │   └── ui/                 # Jetpack Compose UI
│   │   └── webrtc/                 # WebRTC 코어
│   │       └── PeerConnectionManager.kt
│   └── src/test/                   # 단위 테스트 (11개 파일)
│
├── build.gradle.kts                # 프로젝트 빌드 설정
├── settings.gradle.kts             # 설정 파일
└── gradle.properties               # Gradle 속성
```

#### 의존성 관리
```kotlin
// webrtc-core/build.gradle.kts
dependencies {
    // WebRTC
    implementation("org.webrtc:google-webrtc:1.0.+")

    // Firebase BOM
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-common-ktx")

    // Hilt (DI)
    implementation("com.google.dagger:hilt-android:2.48")
    kapt("com.google.dagger:hilt-compiler:2.48")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Jetpack Compose
    implementation(platform("androidx.compose:compose-bom:2023.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")

    // Testing
    testImplementation("io.mockk:mockk:1.13.8")
    testImplementation("com.google.truth:truth:1.1.5")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}
```

#### 권장 플러그인
- Kotlin Plugin
- Firebase Plugin
- SonarLint (코드 품질)
- GitToolBox (Git 통합)

### iOS 개발 환경 (Milestone 3 완료)

#### 필수 소프트웨어
- **Xcode**: 15.0 이상
- **Swift**: 5.9+
- **Swift Package Manager**: (기본 내장)
- **macOS**: Ventura (13.0) 이상

#### 환경 설정 단계
```bash
# 1. 프로젝트 디렉토리 이동
cd client-sdk/ios

# 2. Swift Package Manager로 의존성 해결
# Package.swift에 정의된 의존성이 자동으로 로드됨
# - Firebase iOS SDK
# - WebRTC (수동으로 xcframework 추가 필요)

# 3. Firebase 설정 파일 추가
# Firebase Console에서 GoogleService-Info.plist 다운로드
cp ~/Downloads/GoogleService-Info.plist WebRTCKit/

# 4. WebRTC.xcframework 추가 (수동)
# WebRTC.xcframework를 프로젝트 루트에 복사
# Xcode에서 프로젝트 설정 > Frameworks, Libraries, and Embedded Content
# WebRTC.xcframework 추가

# 5. SwiftLint/SwiftFormat 설정
# .swiftlint.yml 및 .swiftformat 파일이 이미 프로젝트에 포함됨

# 6. 빌드 및 테스트
swift build
swift test

# 7. Xcode에서 열기 (선택사항)
open Package.swift
```

#### 프로젝트 구조
iOS 프로젝트는 **Clean Architecture**로 구성되었습니다:

```
client-sdk/ios/
├── Package.swift                      # Swift Package Manager 설정
├── .swiftlint.yml                     # SwiftLint 설정
├── .swiftformat                       # SwiftFormat 설정
├── WebRTCKit/                         # 메인 라이브러리
│   ├── WebRTCKit.h                    # Public C 헤더
│   ├── Data/                          # 데이터 레이어
│   │   ├── Models/
│   │   │   └── SignalingMessage.swift
│   │   ├── Repositories/
│   │   │   └── SignalingRepository.swift
│   │   └── Services/
│   │       └── TurnCredentialService.swift
│   ├── Domain/                        # 도메인 레이어
│   │   └── UseCases/
│   │       └── CreateOfferUseCase.swift
│   ├── Presentation/                  # 프레젠테이션 레이어
│   │   ├── Models/
│   │   │   └── CallState.swift
│   │   ├── ViewModels/
│   │   │   └── CallViewModel.swift
│   │   └── Views/
│   │       └── CallView.swift
│   ├── WebRTC/                        # WebRTC 코어
│   │   └── PeerConnectionManager.swift
│   ├── DI/                            # 의존성 주입
│   │   └── AppContainer.swift
│   └── Info.plist
│
└── WebRTCKitTests/                    # 테스트 (3개 파일)
    ├── SignalingMessageTests.swift
    ├── CallViewModelTests.swift
    └── WebRTCIntegrationTests.swift
```

#### 의존성 관리
```swift
// Package.swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebRTCKit",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "WebRTCKit",
            targets: ["WebRTCKit"])
    ],
    dependencies: [
        // Firebase (SPM)
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            from: "11.0.0"
        )
    ],
    targets: [
        .target(
            name: "WebRTCKit",
            dependencies: [
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk")
            ]
        ),
        .testTarget(
            name: "WebRTCKitTests",
            dependencies: ["WebRTCKit"]
        )
    ]
)
```

#### 권장 설정
- SwiftLint 활성화 (코드 스타일 자동 검사)
- SwiftFormat 설정 (자동 포맷팅)
- Xcode Behaviors 커스터마이징 (빌드 완료 알림 등)

#### WebRTC Framework 설치
```bash
# WebRTC.xcframework는 별도로 다운로드 필요
# https://webrtc.github.io/webrtc-org/native-code/ios/

# 또는 CocoaPods 사용 (대안)
# Podfile 생성 후:
pod install
```

#### iOS 단위 테스트
```bash
# Swift Package Manager 테스트
cd client-sdk/ios
swift test

# Xcode 테스트
xcodebuild test -scheme WebRTCKit -destination 'platform=iOS Simulator,name=iPhone 15'

# 코드 커버리지
swift test --enable-code-coverage
```

#### iOS 통합 테스트
```bash
# Firebase 에뮬레이터 시작
firebase emulators:start --only firestore

# 에뮬레이터 사용 설정
# WebRTCKit/Data/Repositories/SignalingRepository.swift에서
# Firestore.firestore().useEmulator(withHost: "localhost", port: 8080)
```

### Firebase 개발 환경

### Firebase 개발 환경

#### Firebase CLI 설치
```bash
# npm으로 설치
npm install -g firebase-tools

# 로그인
firebase login

# 프로젝트 초기화 (처음 한 번만)
cd infrastructure/firebase
firebase init

# Firestore 선택
# - Firestore Rules
# - Firestore Indexes
```

#### Firestore 에뮬레이터 설정 (로컬 개발)
```bash
# firebase.json 설정
{
  "emulators": {
    "firestore": {
      "port": 8080
    }
  }
}

# 에뮬레이터 시작
firebase emulators:start --only firestore

# 클라이언트에서 에뮬레이터 접속
# Android: FirebaseFirestore.getInstance().useEmulator("10.0.2.2", 8080)
# iOS: Firestore.firestore().useEmulator(withHost: "localhost", port: 8080)
```

---

## 프로젝트 구조

### 전체 디렉토리 구조
```
webrtc-hybrid-server/
├── infrastructure/              # 인프라 설정
│   ├── oracle-cloud/
│   │   ├── coturn/             # TURN 서버 설정
│   │   ├── terraform/          # IaC (선택)
│   │   └── security/           # 방화벽 규칙
│   └── firebase/
│       ├── firestore.rules     # 보안 규칙
│       └── firestore.indexes.json
│
├── client-sdk/                  # 클라이언트 SDK
│   ├── android/
│   │   └── app/src/main/java/com/webrtc/
│   │       ├── data/           # 데이터 레이어
│   │       ├── domain/         # 비즈니스 로직
│   │       ├── presentation/   # UI
│   │       └── di/             # 의존성 주입
│   └── ios/
│       └── WebRTCKit/
│           ├── Data/           # 데이터 레이어
│           ├── Domain/         # 비즈니스 로직
│           └── Presentation/   # UI
│
├── shared/                      # 공유 리소스
│   ├── schemas/                # 데이터 스키마
│   └── constants/              # 공통 상수
│
├── docs/                        # 문서
└── tests/                       # 테스트
```

### Android 모듈 구조 (Clean Architecture)
```
app/src/main/java/com/webrtc/
├── data/
│   ├── repository/
│   │   ├── SignalingRepositoryImpl.kt
│   │   └── WebRTCRepositoryImpl.kt
│   ├── datasource/
│   │   ├── remote/
│   │   │   └── FirestoreDataSource.kt
│   │   └── local/
│   │       └── SharedPreferencesDataSource.kt
│   └── model/
│       └── RoomDto.kt
│
├── domain/
│   ├── repository/
│   │   ├── SignalingRepository.kt
│   │   └── WebRTCRepository.kt
│   ├── usecase/
│   │   ├── CreateOfferUseCase.kt
│   │   ├── AnswerCallUseCase.kt
│   │   └── AddIceCandidateUseCase.kt
│   └── model/
│       └── Room.kt
│
├── presentation/
│   ├── call/
│   │   ├── CallViewModel.kt
│   │   ├── CallActivity.kt
│   │   └── CallState.kt
│   └── common/
│       └── BaseViewModel.kt
│
└── di/
    ├── AppModule.kt
    ├── DataModule.kt
    └── DomainModule.kt
```

### iOS 모듈 구조 (MVVM)
```
WebRTCKit/
├── Data/
│   ├── Repository/
│   │   ├── SignalingRepositoryImpl.swift
│   │   └── WebRTCRepositoryImpl.swift
│   ├── DataSource/
│   │   └── FirestoreDataSource.swift
│   └── Model/
│       └── RoomDTO.swift
│
├── Domain/
│   ├── Repository/
│   │   ├── SignalingRepository.swift
│   │   └── WebRTCRepository.swift
│   ├── UseCase/
│   │   ├── CreateOfferUseCase.swift
│   │   └── AnswerCallUseCase.swift
│   └── Entity/
│       └── Room.swift
│
├── Presentation/
│   ├── Call/
│   │   ├── CallViewController.swift
│   │   ├── CallViewModel.swift
│   │   └── CallView.swift
│   └── Common/
│       └── BaseViewModel.swift
│
└── DI/
    └── DependencyContainer.swift
```

---

## 개발 워크플로우

### 기능 개발 프로세스

#### 1. 작업 시작
```bash
# 최신 develop 브랜치로 전환
git checkout develop
git pull origin develop

# 새로운 피처 브랜치 생성
git checkout -b feature/add-screen-sharing

# Claude Code로 작업 지침 확인
# CLAUDE.md 파일에서 해당 Phase의 Task 확인
```

#### 2. 개발 (TDD 방식)
```bash
# 2.1. 테스트 먼저 작성
# Android 예시
# app/src/test/java/com/webrtc/domain/usecase/CreateOfferUseCaseTest.kt

# 2.2. 최소한의 코드로 테스트 통과
# app/src/main/java/com/webrtc/domain/usecase/CreateOfferUseCase.kt

# 2.3. 리팩토링 (테스트 통과 상태 유지)
```

#### 3. 로컬 테스트
```bash
# Android - 단위 테스트
./gradlew test

# Android - 통합 테스트 (디바이스 연결 필요)
./gradlew connectedAndroidTest

# iOS - 테스트
xcodebuild test -workspace WebRTCKit.xcworkspace \
  -scheme WebRTCKit -destination 'platform=iOS Simulator,name=iPhone 15'
```

#### 4. 코드 품질 검사
```bash
# Android - Lint
./gradlew lint

# Android - Detekt (정적 분석)
./gradlew detekt

# iOS - SwiftLint
swiftlint
```

#### 5. 커밋 및 푸시
```bash
# 변경사항 스테이징
git add .

# 커밋 (Conventional Commits 형식)
git commit -m "feat(call): add screen sharing functionality

- Implemented MediaProjection API for Android
- Added screen capture permission handling
- Created ScreenShareViewModel

Closes #42"

# 푸시
git push origin feature/add-screen-sharing
```

#### 6. Pull Request
- GitHub에서 Pull Request 생성
- PR 템플릿 작성 (변경 사항, 테스트, 스크린샷)
- 최소 1명의 리뷰어 지정
- CI/CD 파이프라인 통과 확인

#### 7. 코드 리뷰 반영
```bash
# 리뷰 피드백 반영
git add .
git commit -m "refactor(call): apply code review feedback"
git push origin feature/add-screen-sharing
```

#### 8. Merge
- Squash and Merge (권장)
- 피처 브랜치 삭제

---

## 고급 기능 개발

### 네트워크 모니터링 (Milestone 4)

Milestone 4에서 구현된 고급 기능들을 사용하는 방법입니다.

#### Android 네트워크 모니터링 설정

**RTCStatsCollector 통합**:
```kotlin
// PeerConnectionManager에서 stats collector 사용
class PeerConnectionManager(
    private val context: Context
) {
    private val statsCollector = RTCStatsCollector(peerConnection)

    fun startMonitoring() {
        statsCollector.start()
    }

    fun getQualityMetrics(): QualityMetrics {
        return statsCollector.getCurrentMetrics()
    }
}
```

**QualityMetricsOverlay 사용**:
```kotlin
// CallScreen.kt에서 품질 메트릭 표시
@Composable
fun CallScreen(viewModel: CallViewModel = hiltViewModel()) {
    val qualityMetrics by viewModel.qualityMetrics.collectAsState()

    Box {
        VideoCallContent()
        QualityMetricsOverlay(
            metrics = qualityMetrics,
            onDismiss = { viewModel.toggleQualityOverlay() }
        )
    }
}
```

#### iOS 네트워크 모니터링 설정

**RTCStatsCollector 통합**:
```swift
// PeerConnectionManager에서 stats collector 사용
class PeerConnectionManager {
    private let statsCollector: RTCStatsCollector

    init(peerConnection: RTCPeerConnection) {
        self.statsCollector = RTCStatsCollector(peerConnection: peerConnection)
    }

    func startMonitoring() {
        statsCollector.start()
    }

    func getQualityMetrics() -> QualityMetrics {
        return statsCollector.getCurrentMetrics()
    }
}
```

**QualityMetricsOverlay 사용**:
```swift
// CallView.swift에서 품질 메트릭 표시
struct CallView: View {
    @StateObject var viewModel: CallViewModel
    @State var showQualityMetrics = false

    var body: some View {
        ZStack {
            VideoCallContent()
            if showQualityMetrics {
                QualityMetricsOverlay(metrics: viewModel.qualityMetrics)
            }
        }
    }
}
```

### 자동 재연결 (Milestone 4)

#### Android 자동 재연결 설정

**ReconnectionManager 통합**:
```kotlin
// CallViewModel에서 재연결 관리자 사용
class CallViewModel @Inject constructor(
    private val webRTCRepository: WebRTCRepository,
    private val reconnectionManager: ReconnectionManager
) : ViewModel() {

    fun handleConnectionFailure(error: WebRTCException) {
        when {
            error.isMinor() -> reconnectionManager.handleMinorFailure()
            error.isMajor() -> reconnectionManager.handleMajorFailure()
            error.isFatal() -> reconnectionManager.handleFatalFailure()
        }

        when (reconnectionManager.state) {
            ReconnectionState.STABLE -> {
                // 연결이 안정적임, 아무 작업 없음
            }
            ReconnectionState.RECONNECTING -> {
                // 재연결 진행 중 UI 표시
                _callState.update { it.copy(isReconnecting = true) }
            }
            ReconnectionState.FAILED -> {
                // 재연결 실패, 사용자에게 알림
                _callState.update { it.copy(
                    isReconnecting = false,
                    errorMessage = "Connection failed after multiple attempts"
                ) }
            }
        }
    }
}
```

#### iOS 자동 재연결 설정

**ReconnectionManager 통합**:
```swift
// CallViewModel에서 재연결 관리자 사용
class CallViewModel: ObservableObject {
    private let reconnectionManager: ReconnectionManager

    func handleConnectionFailure(error: Error) {
        switch error.severity {
        case .minor:
            reconnectionManager.handleMinorFailure()
        case .major:
            reconnectionManager.handleMajorFailure()
        case .fatal:
            reconnectionManager.handleFatalFailure()
        }

        switch reconnectionManager.state {
        case .stable:
            // 연결이 안정적임
            break
        case .reconnecting:
            // 재연결 진행 중 UI 표시
            isReconnecting = true
        case .failed:
            // 재연결 실패
            isReconnecting = false
            errorMessage = "Connection failed after multiple attempts"
        }
    }
}
```

### TURN 자격 증명 자동 갱신 (Milestone 4)

#### Android TURN 자격 증명 자동 갱신

**앱 시작 시 자동 갱신 시작**:
```kotlin
// Application 클래스에서
class WebRTCApplication : Application() {
    @Inject lateinit var turnCredentialService: TurnCredentialService

    override fun onCreate() {
        super.onCreate()
        // 자동 갱신 시작
        turnCredentialService.startAutoRefresh()
    }
}
```

**캐시 상태 확인**:
```kotlin
// TURN 자격 증명 사용 전
val credentials = turnCredentialService.getCredentials(userId)

if (turnCredentialService.isCached()) {
    val timeToExpiry = turnCredentialService.getTimeToExpiry()
    if (timeToExpiry < 300) {
        // 5분 이내에 만료됨, 갱신 필요
        turnCredentialService.refreshCredentials(userId)
    }
}
```

#### iOS TURN 자격 증명 자동 갱신

**앱 시작 시 자동 갱신 시작**:
```swift
// AppContainer에서
class AppContainer {
    let turnCredentialService: TurnCredentialService

    init() {
        self.turnCredentialService = TurnCredentialService()
        // 자동 갱신 시작
        self.turnCredentialService.startAutoRefresh()
    }
}
```

**캐시 상태 확인**:
```swift
// TURN 자격 증명 사용 전
let credentials = turnCredentialService.getCredentials(username: userId)

if turnCredentialService.isCached() {
    let timeToExpiry = turnCredentialService.getTimeToExpiry()
    if timeToExpiry < 300 {
        // 5분 이내에 만료됨, 갱신 필요
        turnCredentialService.refreshCredentials(username: userId)
    }
}
```

### 백그라운드 상태 처리 (Milestone 4)

#### Android 백그라운드 서비스 설정

**AndroidManifest.xml에 권한 추가**:
```xml
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

**백그라운드 서비스 시작**:
```kotlin
// CallViewModel에서
fun startBackgroundService() {
    val intent = Intent(context, WebRTCBackgroundService::class.java)
    ContextCompat.startForegroundService(context, intent)
}

fun stopBackgroundService() {
    val intent = Intent(context, WebRTCBackgroundService::class.java)
    context.stopService(intent)
}
```

#### iOS 백그라운드 상태 처리

**Info.plist에 백그라운드 모드 추가**:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

**백그라운드 핸들러 설정**:
```swift
// AppContainer에서 초기화
let backgroundHandler = BackgroundStateHandler()
backgroundHandler.start()

// CallViewModel에서 사용
func handleBackgroundTransition() {
    backgroundHandler.onDidEnterBackground {
        // 5분 타이머 시작
        self.startBackgroundTimeout()
    }

    backgroundHandler.onWillEnterForeground {
        // 타이머 취소 및 세션 복원
        self.cancelBackgroundTimeout()
    }
}
```

### 품질 메트릭 해석

**품질 상태**:
- **Excellent (85-100점)**: 녹색 - 최적 연결 상태
- **Good (70-84점)**: 연두색 - 양호한 연결 상태
- **Fair (50-69점)**: 주황색 - 보통 연결 상태
- **Poor (0-49점)**: 빨간색 - 나쁜 연결 상태

**품질 점수 계산**:
- RTT (왕복 시간): <50ms (우수), <100ms (양호), <200ms (보통), >=200ms (나쁨)
- 패킷 손실률: <1% (우수), <3% (양호), <5% (보통), >=5% (나쁨)
- 비트레이트: >1Mbps (우수), >500Kbps (양호), >250Kbps (보통), <=250Kbps (나쁨)

---

## 코딩 컨벤션

### Kotlin (Android)

#### 네이밍
```kotlin
// ✅ 클래스: PascalCase
class PeerConnectionManager

// ✅ 함수/변수: camelCase
fun createOffer()
val peerConnection

// ✅ 상수: UPPER_SNAKE_CASE
const val DEFAULT_TIMEOUT = 30_000L

// ✅ Private 프로퍼티: _camelCase (backing property)
private val _connectionState = MutableLiveData<ConnectionState>()
val connectionState: LiveData<ConnectionState> = _connectionState
```

#### 함수 길이 및 복잡도
```kotlin
// ✅ 좋은 예: 단일 책임, 짧고 명확
suspend fun createOffer(): Result<SessionDescription> {
    return withContext(Dispatchers.IO) {
        try {
            val constraints = buildMediaConstraints()
            val sdp = peerConnection.createOffer(constraints).await()
            Result.success(sdp)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}

// ❌ 나쁜 예: 너무 많은 책임
fun handleCall() {
    // 100줄 이상의 코드...
    // 여러 가지 일을 동시에 처리
}
```

#### 에러 처리
```kotlin
// ✅ 좋은 예: Result 타입 사용
sealed class Result<out T> {
    data class Success<T>(val data: T) : Result<T>()
    data class Error(val exception: Exception) : Result<Nothing>()
}

suspend fun sendOffer(sdp: SessionDescription): Result<Unit> {
    return try {
        firestoreDataSource.sendOffer(sdp)
        Result.Success(Unit)
    } catch (e: FirebaseException) {
        Result.Error(e)
    }
}

// ❌ 나쁜 예: 예외를 무시
fun sendOffer(sdp: SessionDescription) {
    try {
        firestoreDataSource.sendOffer(sdp)
    } catch (e: Exception) {
        // 아무것도 안 함
    }
}
```

### Swift (iOS)

#### 네이밍
```swift
// ✅ 클래스/프로토콜: PascalCase
class PeerConnectionManager
protocol SignalingClientDelegate

// ✅ 함수/변수: camelCase
func createOffer()
var peerConnection

// ✅ 상수: 일반 camelCase (static let)
static let defaultTimeout: TimeInterval = 30

// ✅ Private 프로퍼티: _camelCase 사용 안 함 (private 키워드 충분)
private var connectionState: ConnectionState
```

#### Optional 처리
```swift
// ✅ 좋은 예: Guard let으로 early return
func handleRemoteOffer(_ offer: RTCSessionDescription?) {
    guard let offer = offer else {
        print("Offer is nil")
        return
    }
    
    peerConnection.setRemoteDescription(offer) { error in
        if let error = error {
            print("Failed to set remote description: \(error)")
        }
    }
}

// ❌ 나쁜 예: 강제 언래핑
func handleRemoteOffer(_ offer: RTCSessionDescription?) {
    peerConnection.setRemoteDescription(offer!) { error in
        // 크래시 위험
    }
}
```

#### 비동기 처리
```swift
// ✅ 좋은 예: async/await 사용 (Swift 5.5+)
func createOffer() async throws -> RTCSessionDescription {
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, 
                                          optionalConstraints: nil)
    return try await peerConnection.offer(for: constraints)
}

// ❌ 나쁜 예: Completion handler 중첩 (Pyramid of Doom)
func createOffer(completion: @escaping (RTCSessionDescription?, Error?) -> Void) {
    peerConnection.offer(for: constraints) { offer, error in
        if let error = error {
            completion(nil, error)
        } else {
            self.peerConnection.setLocalDescription(offer!) { error in
                if let error = error {
                    completion(nil, error)
                } else {
                    completion(offer, nil)
                }
            }
        }
    }
}
```

---

## 테스트 전략

### 테스트 피라미드

```
         ╱╲
        ╱  ╲
       ╱ E2E ╲        10% (UI 테스트)
      ╱────────╲
     ╱          ╲
    ╱Integration╲    30% (통합 테스트)
   ╱──────────────╲
  ╱                ╲
 ╱   Unit Tests     ╲  60% (단위 테스트)
╱────────────────────╲
```

### 단위 테스트 (Unit Tests)

#### Android - JUnit + MockK
```kotlin
@Test
fun `createOffer should return Success when PeerConnection succeeds`() = runTest {
    // Given
    val expectedSdp = SessionDescription(SessionDescription.Type.OFFER, "sdp-content")
    coEvery { mockPeerConnection.createOffer(any()) } returns expectedSdp
    
    // When
    val result = createOfferUseCase.invoke()
    
    // Then
    assertTrue(result is Result.Success)
    assertEquals(expectedSdp, (result as Result.Success).data)
}

@Test
fun `createOffer should return Error when PeerConnection fails`() = runTest {
    // Given
    val expectedException = RuntimeException("Connection failed")
    coEvery { mockPeerConnection.createOffer(any()) } throws expectedException
    
    // When
    val result = createOfferUseCase.invoke()
    
    // Then
    assertTrue(result is Result.Error)
    assertEquals(expectedException, (result as Result.Error).exception)
}
```

#### iOS - XCTest
```swift
func testCreateOfferSuccess() async throws {
    // Given
    let expectedSdp = RTCSessionDescription(type: .offer, sdp: "sdp-content")
    mockPeerConnection.createOfferResult = .success(expectedSdp)
    
    // When
    let result = try await sut.createOffer()
    
    // Then
    XCTAssertEqual(result.sdp, expectedSdp.sdp)
    XCTAssertEqual(mockPeerConnection.createOfferCallCount, 1)
}

func testCreateOfferFailure() async {
    // Given
    mockPeerConnection.createOfferResult = .failure(TestError.connectionFailed)
    
    // When/Then
    do {
        _ = try await sut.createOffer()
        XCTFail("Expected error to be thrown")
    } catch {
        XCTAssertTrue(error is TestError)
    }
}
```

### 통합 테스트 (Integration Tests)

#### Firestore 연동 테스트
```kotlin
@Test
fun `should send and receive offer through Firestore`() = runTest {
    // Given
    val roomId = "test-room-${UUID.randomUUID()}"
    val offer = SessionDescription(SessionDescription.Type.OFFER, "test-sdp")
    
    // When
    signalingClient.sendOffer(roomId, offer)
    delay(1000) // Firestore 동기화 대기
    
    val receivedOffer = signalingClient.observeOffer(roomId).first()
    
    // Then
    assertEquals(offer.description, receivedOffer.description)
    
    // Cleanup
    firestoreDataSource.deleteRoom(roomId)
}
```

### E2E 테스트 (UI Tests)

#### Android - Espresso
```kotlin
@Test
fun `should establish video call between two users`() {
    // Given - 앱 시작
    ActivityScenario.launch(MainActivity::class.java)
    
    // When - Room ID 입력 및 Call 버튼 클릭
    onView(withId(R.id.roomIdEditText))
        .perform(typeText("test-room-123"))
    onView(withId(R.id.callButton))
        .perform(click())
    
    // Then - 원격 비디오 뷰가 표시됨
    onView(withId(R.id.remoteVideoView))
        .check(matches(isDisplayed()))
}
```

#### iOS - XCUITest
```swift
func testVideoCallFlow() throws {
    let app = XCUIApplication()
    app.launch()
    
    // When
    let roomIdTextField = app.textFields["roomIdTextField"]
    roomIdTextField.tap()
    roomIdTextField.typeText("test-room-123")
    
    app.buttons["callButton"].tap()
    
    // Then
    let remoteVideoView = app.otherElements["remoteVideoView"]
    XCTAssertTrue(remoteVideoView.waitForExistence(timeout: 10))
}
```

---

## 디버깅 가이드

### Android 디버깅

#### WebRTC Stats 확인
```kotlin
peerConnection.getStats { report ->
    report.statsMap.values.forEach { stats ->
        when (stats.type) {
            "inbound-rtp" -> {
                val bytesReceived = stats.members["bytesReceived"]
                val packetsLost = stats.members["packetsLost"]
                Log.d("WebRTC", "Inbound: bytes=$bytesReceived, lost=$packetsLost")
            }
            "outbound-rtp" -> {
                val bytesSent = stats.members["bytesSent"]
                Log.d("WebRTC", "Outbound: bytes=$bytesSent")
            }
        }
    }
}
```

#### Logcat 필터링
```bash
# WebRTC 관련 로그만 필터링
adb logcat -s WebRTC:D *:S

# 특정 패키지 로그
adb logcat | grep com.webrtc
```

### iOS 디버깅

#### WebRTC Stats 확인
```swift
peerConnection.statistics { report in
    report.statistics.forEach { (id, stats) in
        if stats.type == "inbound-rtp" {
            let bytesReceived = stats.values["bytesReceived"]
            let packetsLost = stats.values["packetsLost"]
            print("Inbound: bytes=\(bytesReceived), lost=\(packetsLost)")
        }
    }
}
```

#### Console 로그
```swift
// OSLog 사용 (권장)
import os.log

extension OSLog {
    private static var subsystem = Bundle.main.bundleIdentifier!
    static let webrtc = OSLog(subsystem: subsystem, category: "WebRTC")
}

os_log("Connection state changed: %@", log: .webrtc, type: .info, newState.description)
```

### TURN 서버 디버깅

#### Coturn 로그 확인
```bash
# 실시간 로그 모니터링
sudo tail -f /var/log/turnserver.log

# 특정 사용자 필터링
sudo grep "testuser" /var/log/turnserver.log

# 에러만 필터링
sudo grep "ERROR" /var/log/turnserver.log
```

#### 연결 테스트 도구
```bash
# turnutils-uclient로 TURN 서버 테스트
turnutils-uclient -v -u testuser -w testpass <VM_IP> -p 3478

# Trickle ICE 웹 도구
# https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/
```

---

## 성능 최적화

### Android 최적화

#### 1. ProGuard 설정
```proguard
# proguard-rules.pro
-keep class org.webrtc.** { *; }
-keep class com.google.firebase.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
```

#### 2. 메모리 최적화
```kotlin
// ViewModel에서 PeerConnection 정리
override fun onCleared() {
    peerConnection.dispose()
    audioTrack?.dispose()
    videoTrack?.dispose()
    super.onCleared()
}
```

#### 3. 배터리 최적화
```kotlin
// 화면 꺼짐 시 비디오 일시 중지
lifecycle.addObserver(object : DefaultLifecycleObserver {
    override fun onStop(owner: LifecycleOwner) {
        videoTrack?.setEnabled(false)
    }
    
    override fun onStart(owner: LifecycleOwner) {
        videoTrack?.setEnabled(true)
    }
})
```

### iOS 최적화

#### 1. Background Mode
```swift
// Info.plist
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
    <string>voip</string>
</array>
```

#### 2. 메모리 관리
```swift
deinit {
    peerConnection?.close()
    audioTrack = nil
    videoTrack = nil
}
```

#### 3. 비디오 해상도 조정
```swift
// 네트워크 상태에 따라 해상도 조정
func adjustVideoQuality(networkQuality: NetworkQuality) {
    let constraints: RTCMediaConstraints
    
    switch networkQuality {
    case .poor:
        constraints = RTCMediaConstraints(mandatoryConstraints: [
            "maxWidth": "640",
            "maxHeight": "480"
        ], optionalConstraints: nil)
    case .good:
        constraints = RTCMediaConstraints(mandatoryConstraints: [
            "maxWidth": "1280",
            "maxHeight": "720"
        ], optionalConstraints: nil)
    }
    
    // 비디오 소스 재설정
}
```

### TURN 서버 최적화

#### Coturn 설정 튜닝
```conf
# /etc/turnserver.conf

# 동시 접속자 제한
max-bps=1000000

# 할당 타임아웃
stale-nonce=600

# 로그 레벨 조정 (프로덕션에서는 WARNING으로)
log-level=WARNING

# 릴레이 쓰레드 수
relay-threads=4
```

---

## 다음 단계

개발 환경 설정이 완료되었다면:

1. [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - 프로덕션 배포 방법
2. [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - 자주 발생하는 문제 해결
3. [ARCHITECTURE.md](ARCHITECTURE.md) - 아키텍처 심화 학습

---

**문의사항이 있으시면 GitHub Issues를 통해 알려주세요!**
