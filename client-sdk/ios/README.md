# WebRTCKit iOS SDK

WebRTC-Lite iOS SDK for real-time video calling with Firestore signaling.

## Overview

WebRTCKit is a Swift-based iOS SDK that provides WebRTC functionality with Firebase Firestore signaling. It follows Clean Architecture principles and is built with SwiftUI, Combine, and WebRTC native libraries.

## Features

- **Real-time Video Calling**: P2P WebRTC connections with STUN/TURN support
- **Firestore Signaling**: SDP offer/answer and ICE candidate exchange via Firebase
- **SwiftUI Integration**: Modern SwiftUI views and ViewModels
- **Clean Architecture**: Separated Data, Domain, and Presentation layers
- **Combine Publishers**: Reactive state management
- **Permission Handling**: Camera and microphone permission management
- **Media Controls**: Camera toggle, microphone toggle, speaker toggle, camera switch

## Requirements

- iOS 13.0+
- Xcode 14.0+
- Swift 5.9+
- Firebase iOS SDK 11.0+
- WebRTC.xcframework

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(
        url: "https://github.com/firebase/firebase-ios-sdk.git",
        from: "11.0.0"
    ),
    // Add WebRTC.xcframework manually
]
```

### Manual Setup

1. Download WebRTC.xcframework from [Google WebRTC](https://webrtc.googlesource.com/src/+/refs/heads/main/docs/native-ios.md)
2. Add WebRTC.xcframework to your Xcode project
3. Add Firebase via Swift Package Manager or CocoaPods

## Architecture

### Layer Structure

```
WebRTCKit/
├── Data/              # Data layer (Firestore, TURN service)
├── Domain/            # Domain layer (Use cases)
├── Presentation/      # Presentation layer (ViewModels, Views)
├── WebRTC/           # WebRTC core (PeerConnectionManager)
└── DI/               # Dependency Injection
```

### Clean Architecture

```
┌─────────────────────────────────────┐
│      Presentation Layer             │
│  (ViewModels, SwiftUI Views)        │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│       Domain Layer                  │
│  (Use Cases, Repository Interfaces) │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│        Data Layer                   │
│  (Repositories, DataSources)        │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│     External Services               │
│  (Firestore, TURN API, WebRTC)      │
└─────────────────────────────────────┘
```

## Usage

### 1. Initialize Firebase

```swift
import FirebaseCore

// In AppDelegate.swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
    FirebaseApp.configure()
    return true
}
```

### 2. Create ViewModel

```swift
import WebRTCKit

let viewModel = CallViewModel.create()
```

### 3. Present Call View

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        CallView(viewModel: viewModel)
    }
}
```

### 4. Handle Call Events

```swift
// Start outgoing call
viewModel.handleEvent(.startCall(targetUserId: "user-123"))

// Answer incoming call
viewModel.handleEvent(.answerCall(offer: offerMessage))

// End call
viewModel.handleEvent(.endCall)

// Toggle camera
viewModel.handleEvent(.toggleCamera(enabled: false))

// Toggle microphone
viewModel.handleEvent(.toggleMicrophone(enabled: false))

// Switch camera
viewModel.handleEvent(.switchCamera)
```

## Signaling Messages

### Offer

```swift
let offer = SignalingMessage.Offer(
    sessionId: "session-123",
    sdp: "v=0\r\no=- ...",
    callerId: "user-abc"
)
```

### Answer

```swift
let answer = SignalingMessage.Answer(
    sessionId: "session-123",
    sdp: "v=0\r\no=- ...",
    calleeId: "user-xyz"
)
```

### ICE Candidate

```swift
let candidate = SignalingMessage.IceCandidate(
    sessionId: "session-123",
    sdpMid: "0",
    sdpMLineIndex: 0,
    sdpCandidate: "candidate:1 1 UDP ..."
)
```

## Configuration

### TURN Server

```swift
let config = TurnCredentialService.TurnAPIConfig(
    baseURL: "https://your-turn-api.com/api",
    timeout: 10.0,
    retryCount: 3
)

let turnService = TurnCredentialService(config: config)
```

### Firestore Security Rules

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /sessions/{sessionId} {
      allow read, write: if request.auth != null;
      match /iceCandidates/{candidateId} {
        allow read, write: if request.auth != null;
      }
    }
  }
}
```

## Permissions

Add to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app needs camera access for video calls</string>
<key>NSMicrophoneUsageDescription</key>
<string>This app needs microphone access for audio calls</string>
```

## Testing

### Unit Tests

```bash
xcodebuild test \
  -scheme WebRTCKit \
  -destination 'platform=iOS Simulator,name=iPhone 14'
```

### Integration Tests

```bash
# Start Firebase emulator
firebase emulators:start --only firestore

# Run integration tests
xcodebuild test \
  -scheme WebRTCKitIntegrationTests \
  -destination 'platform=iOS Simulator,name=iPhone 14'
```

## Error Handling

```swift
switch viewModel.callState {
case .idle:
    // Ready
case .connecting:
    // Connecting to peer
case .connected(let sessionId):
    // Call is active
case .error(let message):
    // Handle error
    print("Call error: \(message)")
}
```

## Performance Targets

- P2P Connection Time: < 3s
- TURN Connection Time: < 5s
- Video Resolution: 1280x720 @ 30fps
- CPU Usage: < 30%
- Memory Usage: < 150MB

## TRUST 5 Compliance

- **Testable**: 80%+ test coverage with characterization tests
- **Readable**: Zero SwiftLint warnings, documented code
- **Unified**: Clean Architecture with clear layer separation
- **Secured**: No hardcoded credentials, OWASP compliant
- **Trackable**: Structured logging, conventional commits

## Troubleshooting

### Build Errors

If you encounter WebRTC framework errors:
1. Ensure WebRTC.xcframework is properly linked
2. Check iOS deployment target (iOS 13.0+)
3. Verify Swift Package Manager dependencies

### Runtime Errors

If camera/microphone doesn't work:
1. Check Info.plist permissions
2. Request permissions at runtime
3. Test on physical device (simulator has limited support)

### Connection Failures

If P2P connection fails:
1. Verify TURN server is reachable
2. Check Firestore security rules
3. Test STUN server connectivity
4. Review ICE candidate exchange

## License

MIT License - see LICENSE file for details

## Contributing

Please read CONTRIBUTING.md for details on our code of conduct and the process for submitting pull requests.

## Support

For issues and questions:
- GitHub Issues: [webrtc-lite/issues](https://github.com/webrtc-lite/issues)
- Documentation: [docs.webrtc-lite.io](https://docs.webrtc-lite.io)
