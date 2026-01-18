# Android SDK Integration Guide

Android WebRTC SDK 통합 가이드입니다.

## 목차

- [개요](#개요)
- [전제 조건](#전제-조건)
- [모듈 가져오기](#모듈-가져오기)
- [Firebase 설정](#firebase-설정)
- [기본 사용법](#기본-사용법)
- [API 참조](#api-참조)
- [권한 처리](#권한-처리)
- [오류 처리](#오류-처리)
- [테스트](#테스트)
- [문제 해결](#문제-해결)

---

## 개요

WebRTC-Lite Android SDK는 Clean Architecture로 설계된 WebRTC 클라이언트 라이브러리로, 다음 기능을 제공합니다:

- 1:1 오디오/비디오 통화
- Firebase Firestore 기반 시그널링
- TURN/STUN 서버 연결
- PeerConnection 라이프사이클 관리
- Jetpack Compose UI

---

## 전제 조건

### 최소 요구사항

- **Android SDK**: API 24 (Android 7.0) 이상
- **Kotlin**: 1.9.0+
- **JDK**: 17 이상
- **Gradle**: 8.2+

### Firebase 프로젝트

1. [Firebase Console](https://console.firebase.google.com/)에서 프로젝트 생성
2. Firestore Database 생성 (프로덕션 모드)
3. 앱 등록 (Android)
4. `google-services.json` 다운로드

### TURN 서버

Oracle Cloud에 배포된 TURN 서버 또는 자체 호스팅 TURN 서버 필요

---

## 모듈 가져오기

### Gradle 설정

**settings.gradle.kts**:
```kotlin
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

include(":webrtc-core")
```

**webrtc-core/build.gradle.kts**:
```kotlin
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.google.dagger.hilt.android")
    id("com.google.gms.google-services")
}

android {
    compileSdk = 34

    defaultConfig {
        minSdk = 24
        targetSdk = 34

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        consumerProguardFiles("consumer-rules.pro")
    }

    buildFeatures {
        compose = true
    }

    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.3"
    }
}

dependencies {
    // WebRTC
    implementation("org.webrtc:google-webrtc:1.0.+")

    // Firebase BOM
    implementation(platform("com.google.firebase:firebase-bom:32.7.0"))
    implementation("com.google.firebase:firebase-firestore")

    // Hilt
    implementation("com.google.dagger:hilt-android:2.48")
    kapt("com.google.dagger:hilt-compiler:2.48")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    // Jetpack Compose
    implementation(platform("androidx.compose:compose-bom:2023.10.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.1")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.6.2")
}
```

---

## Firebase 설정

### 1. google-services.json 추가

```bash
# 프로젝트 루트에서
cp ~/Downloads/google-services.json webrtc-core/src/main/
```

### 2. Firestore 보안 규칙 배포

```bash
cd infrastructure/firebase
firebase deploy --only firestore:rules
```

### 3. Firestore 인덱스 배포

```bash
firebase deploy --only firestore:indexes
```

---

## 기본 사용법

### 1. Application 클래스 설정

```kotlin
@HiltAndroidApp
class WebRTCApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Firebase 초기화
        FirebaseApp.initializeApp(this)
    }
}
```

### 2. MainActivity에서 CallScreen 사용

```kotlin
@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            WebRTCLiteTheme {
                CallScreen(
                    onBackClick = { finish() }
                )
            }
        }
    }
}
```

### 3. 통화 시작하기

```kotlin
// CallViewModel을 통한 통화 시작
val viewModel: CallViewModel = hiltViewModel()

// 통화 시작
viewModel.onEvent(CallUiEvent.StartCall(roomId = "room-123"))

// 통화 종료
viewModel.onEvent(CallUiEvent.EndCall)
```

---

## API 참조

### CallViewModel

메인 뷰모델로 통화 상태를 관리합니다.

```kotlin
class CallViewModel @Inject constructor(
    private val createOfferUseCase: CreateOfferUseCase,
    private val answerCallUseCase: AnswerCallUseCase,
    private val endCallUseCase: EndCallUseCase
) : ViewModel() {

    // 통화 상태 흐름
    val callState: StateFlow<CallState>

    // UI 이벤트 처리
    fun onEvent(event: CallUiEvent)
}
```

### CallState

통화 상태를 나타냅니다.

```kotlin
data class CallState(
    val isConnected: Boolean = false,
    val isCalling: Boolean = false,
    val localSessionDescription: String? = null,
    val remoteSessionDescription: String? = null,
    val errorMessage: String? = null
)
```

### CallUiEvent

UI 이벤트 타입입니다.

```kotlin
sealed class CallUiEvent {
    data class StartCall(val roomId: String) : CallUiEvent()
    object AnswerCall : CallUiEvent()
    object EndCall : CallUiEvent()
}
```

---

## 권한 처리

### 필수 권한

AndroidManifest.xml에 추가:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
```

### 런타임 권한 요청

```kotlin
@Composable
fun PermissionRequestScreen(
    onPermissionsGranted: () -> Unit
) {
    val cameraPermission = rememberPermissionState(Manifest.permission.CAMERA)
    val audioPermission = rememberPermissionState(Manifest.permission.RECORD_AUDIO)

    LaunchedEffect(Unit) {
        if (cameraPermission.status.isGranted && audioPermission.status.isGranted) {
            onPermissionsGranted()
        }
    }

    if (!cameraPermission.status.isGranted || !audioPermission.status.isGranted) {
        AlertDialog(
            onDismissRequest = { },
            title = { Text("권한 필요") },
            text = { Text("카메라와 마이크 권한이 필요합니다.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        cameraPermission.launchPermissionRequest()
                        audioPermission.launchPermissionRequest()
                    }
                ) {
                    Text("권한 요청")
                }
            }
        )
    }
}
```

---

## 오류 처리

### 공통 에러 코드

| 에러 코드 | 설명 | 해결 방법 |
|-----------|------|-----------|
| `E001` | Firestore 연결 실패 | 인터넷 연결 확인, Firebase 설정 확인 |
| `E002` | TURN 자격 증명 실패 | TURN 서버 상태 확인 |
| `E003` | PeerConnection 생성 실패 | WebRTC 라이브러리 버전 확인 |
| `E004` | 권한 거부 | 런타임 권한 요청 구현 |
| `E005` | 카메라/마이크 없음 | 디바이스 하드웨어 확인 |

### 에러 처리 예시

```kotlin
@Composable
fun CallScreen(
    viewModel: CallViewModel = hiltViewModel()
) {
    val state by viewModel.callState.collectAsState()

    LaunchedEffect(state.errorMessage) {
        state.errorMessage?.let { message ->
            // 에러 표시
            showErrorDialog(message)
        }
    }
}
```

---

## 테스트

### 단위 테스트 실행

```bash
cd client-sdk/android
./gradlew :webrtc-core:testDebugUnitTest
```

### 코드 커버리지 확인

```bash
./gradlew :webrtc-core:jacocoTestReport
# 리포트: webrtc-core/build/reports/jacoco/test/html/index.html
```

### UI 테스트 실행

```bash
./gradlew :webrtc-core:connectedAndroidTest
```

---

## 문제 해결

### 통화 연결 실패

**증상**: 통화 시작 후 연결되지 않음

**해결 방법**:
1. TURN 서버 상태 확인
```bash
# TURN 서버 핑 테스트
ping <ORACLE_VM_IP>
```

2. Firestore 문서 확인
```bash
# Firebase Console > Firestore Database > webrtc_sessions 컬렉션 확인
```

3. WebRTC 로그 확인
```bash
adb logcat | grep WebRTC
```

### 카메라/마이크 작동 안 함

**증상**: 비디오/오디오가 송출되지 않음

**해결 방법**:
1. 권한 확인
```bash
adb shell dumpsys package com.webrtclite.core | grep permission
```

2. 디바이스 호환성 확인
- 카메라 하드웨어 존재 여부
- 마이크 하드웨어 존재 여부

3. WebRTC 로그에서 에러 확인
```bash
adb logcat -s WebRTC:E
```

### 빌드 실패

**증상**: Gradle 빌드 실패

**해결 방법**:
1. Gradle 캐시 삭제
```bash
./gradlew clean
rm -rf ~/.gradle/caches/
```

2. JDK 버전 확인
```bash
java -version  # JDK 17 이상 필요
```

3. 의존성 충돌 확인
```bash
./gradlew :webrtc-core:dependencies
```

---

## 추가 리소스

- [WebRTC-Lite Architecture](../ARCHITECTURE.md)
- [Development Guide](../DEVELOPMENT_GUIDE.md)
- [Troubleshooting](../TROUBLESHOOTING.md)
- [WebRTC 공식 문서](https://webrtc.org/)

---

**버전**: 0.2.0
**마지막 업데이트**: 2026-01-18
