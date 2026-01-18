// MARK: - CallView
// TRUST 5 Compliance: Readable, Unified

import SwiftUI
import WebRTC
import AVFoundation

// MARK: - Call View

/// SwiftUI view for WebRTC call interface
struct CallView: View {

    // MARK: - Properties

    @StateObject private var viewModel: CallViewModel
    @State private var showError = false

    // MARK: - Initialization

    init(viewModel: CallViewModel = .create()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            switch viewModel.callState {
            case .idle:
                idleView
            case .connecting:
                connectingView
            case .waitingForAnswer(let sessionId):
                waitingView(sessionId: sessionId)
            case .connected(let sessionId):
                connectedView(sessionId: sessionId)
            case .ending:
                endingView
            case .ended(let reason):
                endedView(reason: reason)
            case .error(let message):
                errorView(message: message)
            }
        }
        .onAppear {
            requestPermissions()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {
                viewModel.handleEvent(.dismissError)
            }
        } message: {
            if case .error(let message) = viewModel.callState {
                Text(message)
            }
        }
    }

    // MARK: - Idle View

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "video.fill")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("WebRTC Call")
                .font(.largeTitle)
                .foregroundColor(.white)

            Text("Ready to make a call")
                .font(.subheadline)
                .foregroundColor(.gray)

            Spacer()

            Button(action: {
                viewModel.handleEvent(.startCall(targetUserId: "target-user"))
            }) {
                Label("Start Call", systemImage: "phone.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Connecting View

    private var connectingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Connecting...")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()
        }
    }

    // MARK: - Waiting View

    private func waitingView(sessionId: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Waiting for answer...")
                .font(.headline)
                .foregroundColor(.white)

            Text("Session: \(sessionId)")
                .font(.caption)
                .foregroundColor(.gray)

            Spacer()

            Button(action: {
                viewModel.handleEvent(.endCall)
            }) {
                Label("End Call", systemImage: "phone.down.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Connected View

    private func connectedView(sessionId: String) -> some View {
        VStack(spacing: 0) {
            // Remote video view
            RemoteVideoView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Controls overlay
            VStack(spacing: 16) {
                // Connection info
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connected")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text(formatDuration(viewModel.controlsState.connectionDuration))
                            .font(.headline)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("ICE: \(viewModel.controlsState.localIceCandidates)/\(viewModel.controlsState.remoteIceCandidates)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()

                // Control buttons
                HStack(spacing: 24) {
                    // Camera toggle
                    ControlButton(
                        icon: viewModel.controlsState.isCameraEnabled ? "video.fill" : "video.slash.fill",
                        color: viewModel.controlsState.isCameraEnabled ? .white : .red
                    ) {
                        viewModel.handleEvent(.toggleCamera(enabled: !viewModel.controlsState.isCameraEnabled))
                    }

                    // Microphone toggle
                    ControlButton(
                        icon: viewModel.controlsState.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill",
                        color: viewModel.controlsState.isMicrophoneEnabled ? .white : .red
                    ) {
                        viewModel.handleEvent(.toggleMicrophone(enabled: !viewModel.controlsState.isMicrophoneEnabled))
                    }

                    // End call
                    ControlButton(
                        icon: "phone.down.fill",
                        color: .red,
                        size: 64
                    ) {
                        viewModel.handleEvent(.endCall)
                    }

                    // Switch camera
                    ControlButton(
                        icon: "camera.rotate",
                        color: .white
                    ) {
                        viewModel.handleEvent(.switchCamera)
                    }

                    // Speaker toggle
                    ControlButton(
                        icon: viewModel.controlsState.isSpeakerEnabled ? "speaker.wave.3.fill" : "speaker.slash.fill",
                        color: viewModel.controlsState.isSpeakerEnabled ? .white : .gray
                    ) {
                        viewModel.handleEvent(.toggleSpeaker(enabled: !viewModel.controlsState.isSpeakerEnabled))
                    }
                }
                .padding(.bottom, 32)
            }
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    // MARK: - Ending View

    private var endingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)

            Text("Ending call...")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()
        }
    }

    // MARK: - Ended View

    private func endedView(reason: String?) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "phone.slash.fill")
                .font(.system(size: 80))
                .foregroundColor(.gray)

            Text("Call Ended")
                .font(.largeTitle)
                .foregroundColor(.white)

            if let reason = reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button("Close") {
                // Navigate back
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Error View

    private func errorView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 80))
                .foregroundColor(.red)

            Text("Error")
                .font(.largeTitle)
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

            Spacer()

            Button("Retry") {
                viewModel.handleEvent(.dismissError)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue)
            .cornerRadius(12)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helper Methods

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                // Handle permission
            }
        }

        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                // Handle permission
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Remote Video View

/// SwiftUI view for rendering remote WebRTC video stream
struct RemoteVideoView: UIViewRepresentable {

    let viewModel: CallViewModel

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.contentMode = .scaleAspectFill
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        if let videoTrack = viewModel.getRemoteVideoTrack() {
            videoTrack.add(uiView)
        }
    }
}

// MARK: - Control Button

/// Reusable control button for call interface
struct ControlButton: View {
    let icon: String
    let color: Color
    var size: CGFloat = 50
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(color))
        }
    }
}

// MARK: - Preview

struct CallView_Previews: PreviewProvider {
    static var previews: some View {
        CallView()
    }
}
