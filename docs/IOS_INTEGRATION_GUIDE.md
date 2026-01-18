# iOS SDK Integration Guide

iOS WebRTC SDK 통합 가이드입니다.

## 목차

- [개요](#개요)
- [전제 조건](#전제-조건)
- [패키지 가져오기](#패키지-가져오기)
- [Firebase 설정](#firebase-설정)
- [기본 사용법](#기본-사용법)
- [API 참조](#api-참조)
- [권한 처리](#권한-처리)
- [오류 처리](#오류-처리)
- [테스트](#테스트)
- [문제 해결](#문제-해결)

---

## 개요

WebRTC-Lite iOS SDK는 Clean Architecture로 설계된 WebRTC 클라이언트 라이브러리로, 다음 기능을 제공합니다:

- 1:1 오디오/비디오 통화
- Firebase Firestore 기반 시그널링
- TURN/STUN 서버 연결
- PeerConnection 라이프사이클 관리
- SwiftUI UI

---

## 전제 조건

### 최소 요구사항

- **iOS**: iOS 13.0 이상
- **Swift**: 5.9+
- **Xcode**: 15.0 이상
- **macOS**: Ventura (13.0) 이상

### Firebase 프로젝트

1. [Firebase Console](https://console.firebase.google.com/)에서 프로젝트 생성
2. Firestore Database 생성 (프로덕션 모드)
3. 앱 등록 (iOS)
4. `GoogleService-Info.plist` 다운로드

### TURN 서버

Oracle Cloud에 배포된 TURN 서버 또는 자체 호스팅 TURN 서버 필요

---

## 패키지 가져오기

### Swift Package Manager 사용

**Package.swift**:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YourApp",
    platforms: [.iOS(.v13)],
    dependencies: [
        .package(
            url: "https://github.com/your-repo/webrtc-lite-ios.git",
            from: "0.3.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "YourApp",
            dependencies: ["WebRTCKit"]
        )
    ]
)
```

### Xcode 프로젝트에 추가

1. File > Add Package Dependencies...
2. 패키지 URL 입력: `https://github.com/your-repo/webrtc-lite-ios.git`
3. 버전 선택: Up to Next Major Version 0.3.0
4. WebRTCKit 추가

### WebRTC Framework 추가

WebRTC.xcframework를 별도로 다운로드하여 프로젝트에 추가:

```bash
# WebRTC.xcframework 다운로드
# https://webrtc.github.io/webrtc-org/native-code/ios/

# 프로젝트에 복사
cp -r WebRTC.xcframework /path/to/your/project/

# Xcode에서 프로젝트 설정 > Target > General > Frameworks, Libraries, and Embedded Content
# WebRTC.xcframework 추가
```

---

## Firebase 설정

### 1. GoogleService-Info.plist 추가

```bash
# Firebase Console에서 다운로드한 파일 복사
cp ~/Downloads/GoogleService-Info.plist /path/to/your/project/
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

### 1. App Container 설정

```swift
import SwiftUI
import WebRTCKit

@main
struct YourApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
        }
    }
}
```

### 2. CallView 사용

```swift
import SwiftUI
import WebRTCKit

struct ContentView: View {
    @EnvironmentObject var container: AppContainer
    @State private var roomId: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Room ID", text: $roomId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                NavigationLink(
                    destination: container.makeCallView(roomId: roomId)
                ) {
                    Text("Start Call")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
            .navigationTitle("WebRTC Demo")
        }
    }
}
```

### 3. 통화 시작하기

```swift
// CallViewModel 사용
let viewModel = CallViewModel(
    createOfferUseCase: container.createOfferUseCase,
    answerCallUseCase: container.answerCallUseCase,
    endCallUseCase: container.endCallUseCase
)

// 통화 시작
Task {
    try await viewModel.startCall(roomId: "room-123")
}

// 통화 종료
Task {
    try await viewModel.endCall()
}
```

---

## API 참조

### CallViewModel

메인 뷰모델로 통화 상태를 관리합니다.

```swift
@MainActor
public class CallViewModel: ObservableObject {
    @Published public var callState: CallState

    private let createOfferUseCase: CreateOfferUseCase
    private let answerCallUseCase: AnswerCallUseCase
    private let endCallUseCase: EndCallUseCase

    public init(
        createOfferUseCase: CreateOfferUseCase,
        answerCallUseCase: AnswerCallUseCase,
        endCallUseCase: EndCallUseCase
    )

    public func startCall(roomId: String) async throws
    public func answerCall() async throws
    public func endCall() async throws
}
```

### CallState

통화 상태를 나타냅니다.

```swift
public struct CallState {
    public var isConnected: Bool
    public var isCalling: Bool
    public var localSessionDescription: String?
    public var remoteSessionDescription: String?
    public var errorMessage: String?
}
```

### AppContainer

의존성 주입 컨테이너입니다.

```swift
public final class AppContainer: ObservableObject {
    public let firestore: Firestore
    public let turnCredentialService: TurnCredentialService
    public let signalingRepository: SignalingRepository
    public let createOfferUseCase: CreateOfferUseCase
    public let answerCallUseCase: AnswerCallUseCase
    public let endCallUseCase: EndCallUseCase

    public init()

    public func makeCallViewModel() -> CallViewModel
    public func makeCallView(roomId: String) -> CallView
}
```

---

## 권한 처리

### 필수 권한

Info.plist에 추가:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls.</string>

<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for audio calls.</string>
```

### 런타임 권한 요청

```swift
import AVFoundation

struct PermissionRequestView: View {
    @State private var showPermissionAlert = false

    var body: some View {
        VStack {
            if hasCameraAndMicPermission() {
                CallView()
            } else {
                Button("Request Permissions") {
                    requestPermissions()
                }
            }
        }
        .alert("Permissions Required", isPresented: $showPermissionAlert) {
            Button("Settings", action: openAppSettings)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Camera and microphone access is required for video calls.")
        }
    }

    private func hasCameraAndMicPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized &&
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
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
| `E004` | 권한 거부 | Info.plist 권한 설정 확인 |
| `E005` | 카메라/마이크 없음 | 디바이스 하드웨어 확인 |

### 에러 처리 예시

```swift
struct CallView: View {
    @StateObject private var viewModel: CallViewModel

    var body: some View {
        VStack {
            if let error = viewModel.callState.errorMessage {
                ErrorView(message: error) {
                    viewModel.callState.errorMessage = nil
                }
            } else {
                // 통화 UI
            }
        }
    }
}

struct ErrorView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Text("Error: \(message)")
                .foregroundColor(.red)
            Button("Dismiss") {
                onDismiss()
            }
        }
        .padding()
    }
}
```

---

## 테스트

### 단위 테스트 실행

```bash
cd client-sdk/ios
swift test
```

### 코드 커버리지 확인

```bash
swift test --enable-code-coverage
```

### Xcode 테스트

```bash
xcodebuild test \
  -workspace WebRTCKit.xcworkspace \
  -scheme WebRTCKit \
  -destination 'platform=iOS Simulator,name=iPhone 15'
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

3. Xcode 콘솔 로그 확인
```
# WebRTC 로그 필터링
# Xcode > Console > 검색: WebRTC
```

### 카메라/마이크 작동 안 함

**증상**: 비디오/오디오가 송출되지 않음

**해결 방법**:

1. 권한 확인
```swift
// 권한 상태 출력
print("Camera: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
print("Mic: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
```

2. 디바이스 호환성 확인
- 카메라 하드웨어 존재 여부
- 마이크 하드웨어 존재 여부

3. 시뮬레이터 제한사항
- 시뮬레이터에서는 카메라/마이크가 제한될 수 있음
- 실제 디바이스에서 테스트 권장

### 빌드 실패

**증상**: Swift 빌드 실패

**해결 방법**:

1. 빌드 캐시 삭제
```bash
rm -rf .build
swift build
```

2. Xcode 버전 확인
```bash
xcodebuild -version  # Xcode 15.0 이상 필요
```

3. 의존성 충돌 확인
```bash
swift package show-dependencies
```

### WebRTC.xcframework 관련 문제

**증상**: WebRTC 관련 링크 에러

**해결 방법**:

1. xcframework 파일 경로 확인
```bash
ls -la WebRTC.xcframework/
```

2. 프로젝트 설정에서 추가 확인
- Target > General > Frameworks, Libraries, and Embedded Content
- WebRTC.xcframework가 포함되어 있는지 확인

3. 필요한 시스템 프레임워크 추가
- CoreMedia
- CoreAudio
- AudioToolbox
- AVFoundation
- VideoToolbox

---

## 추가 리소스

- [WebRTC-Lite Architecture](../ARCHITECTURE.md)
- [Development Guide](../DEVELOPMENT_GUIDE.md)
- [Troubleshooting](../TROUBLESHOOTING.md)
- [WebRTC 공식 문서](https://webrtc.org/)
- [SwiftUI 공식 문서](https://developer.apple.com/documentation/swiftui)

---

## 샘플 프로젝트

전체 샘플 프로젝트는 `examples/iOS/DemoApp`을 참조하세요.

```swift
import SwiftUI
import WebRTCKit

@main
struct DemoApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RoomListView()
                .environmentObject(container)
        }
    }
}

struct RoomListView: View {
    @EnvironmentObject var container: AppContainer
    @State private var roomId: String = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                TextField("Enter Room ID", text: $roomId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()

                NavigationLink(
                    "Join Room",
                    destination: container.makeCallView(roomId: roomId)
                )
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(roomId.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(10)
                .disabled(roomId.isEmpty)
            }
            .navigationTitle("WebRTC Demo")
            .padding()
        }
    }
}
```

---

**버전**: 0.3.0
**마지막 업데이트**: 2026-01-18
