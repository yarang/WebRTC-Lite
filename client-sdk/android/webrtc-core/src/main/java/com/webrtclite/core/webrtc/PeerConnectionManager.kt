package com.webrtclite.core.webrtc

import com.webrtclite.core.data.service.TurnCredentialService
import com.webrtclite.core.data.repository.SignalingRepository
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import org.webrtc.*
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Manager for WebRTC PeerConnection lifecycle
 * Handles peer connection creation, media capture, and ICE negotiation
 */
@Singleton
class PeerConnectionManager @Inject constructor(
    private val signalingRepository: SignalingRepository,
    private val turnCredentialService: TurnCredentialService
) {
    private val _connectionState = MutableStateFlow("new")
    val connectionState: StateFlow<String> = _connectionState

    private var peerConnectionFactory: PeerConnectionFactory? = null
    private var peerConnection: PeerConnection? = null
    private var videoCapturer: CameraVideoCapturer? = null
    private var audioTrack: AudioTrack? = null
    private var videoTrack: VideoTrack? = null
    private var localVideoSink: ProxyVideoSink? = null
    private var remoteVideoSink: ProxyVideoSink? = null

    private val iceCandidates = MutableStateFlow<IceCandidate?>(null)
    private val remoteMediaStream = MutableStateFlow<MediaStream?>(null)

    private var isCameraEnabled = true
    private var isMicrophoneEnabled = true

    /**
     * Initialize peer connection with STUN/TURN configuration
     */
    suspend fun initialize(
        sessionId: String,
        stunTurnUrls: List<String>,
        username: String,
        password: String
    ): Result<Unit> = runCatching {
        // Initialize PeerConnectionFactory
        initializePeerConnectionFactory()

        // Create ICE servers
        val iceServers = stunTurnUrls.map { url ->
            PeerConnection.IceServer.builder(url)
                .setUsername(username)
                .setPassword(password)
                .createIceServer()
        }

        // Create PeerConnection configuration
        val rtcConfig = PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            iceCandidatePoolSize = 10
        }

        // Create PeerConnection with observer
        peerConnection = peerConnectionFactory?.createPeerConnection(
            rtcConfig,
            object : PeerConnection.Observer {
                override fun onSignalingChange(newState: PeerConnection.SignalingState?) {
                    _connectionState.value = "signaling:${newState?.name}"
                }

                override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState?) {
                    _connectionState.value = "ice:${newState?.name}"
                }

                override fun onIceConnectionReceivingChange(receiving: Boolean) {
                    _connectionState.value = "ice_receiving:$receiving"
                }

                override fun onIceGatheringChange(newState: PeerConnection.IceGatheringState?) {
                    _connectionState.value = "gathering:${newState?.name}"
                }

                override fun onIceCandidate(candidate: IceCandidate?) {
                    candidate?.let { iceCandidates.value = it }
                }

                override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>?) {
                    // Handle removed candidates
                }

                override fun onSelectedCandidatePairChanged(event: PeerConnection.CandidatePairChangeEvent?) {
                    // Handle candidate pair change
                }

                override fun onAddStream(stream: MediaStream?) {
                    stream?.let { remoteMediaStream.value = it }
                }

                override fun onRemoveStream(stream: MediaStream?) {
                    // Handle stream removal
                }

                override fun onDataChannel(channel: DataChannel?) {
                    // Handle data channel
                }

                override fun onRenegotiationNeeded() {
                    // Handle renegotiation
                }

                override fun onAddTrack(receiver: RtpReceiver?, mediaStreams: Array<out MediaStream>?) {
                    // Handle added track
                }
            }
        ) ?: throw Exception("Failed to create peer connection")

        _connectionState.value = "initialized"
    }

    /**
     * Initialize PeerConnectionFactory with required dependencies
     */
    private fun initializePeerConnectionFactory() {
        val options = PeerConnectionFactory.Options().apply {
            networkIgnoreMask = 16
            networkIgnoreMask = 0
        }

        // Initialize audio and video modules
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(null)
                .setEnableInternalTracer(true)
                .setFieldTrials("")
                .createInitializationOptions()
        )

        // Create encoder/decoder factory
        val encoderFactory = DefaultVideoEncoderFactory(
            EglBase.create().eglBaseContext,
            true,
            true
        )
        val decoderFactory = DefaultVideoDecoderFactory(EglBase.create().eglBaseContext)

        peerConnectionFactory = PeerConnectionFactory.builder()
            .setOptions(options)
            .setVideoEncoderFactory(encoderFactory)
            .setVideoDecoderFactory(decoderFactory)
            .createPeerConnectionFactory()
    }

    /**
     * Create SDP offer
     */
    suspend fun createOffer(): Result<SessionDescription> = suspendCancellableCoroutine { continuation ->
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
        }

        peerConnection?.createOffer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                continuation.resume(Result.success(sdp))
            }

            override fun onCreateFailure(error: String) {
                continuation.resume(Result.failure(Exception(error)))
            }

            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    /**
     * Create SDP answer
     */
    suspend fun createAnswer(): Result<SessionDescription> = suspendCancellableCoroutine { continuation ->
        val constraints = MediaConstraints().apply {
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveAudio", "true"))
            mandatory.add(MediaConstraints.KeyValuePair("OfferToReceiveVideo", "true"))
        }

        peerConnection?.createAnswer(object : SdpObserver {
            override fun onCreateSuccess(sdp: SessionDescription) {
                continuation.resume(Result.success(sdp))
            }

            override fun onCreateFailure(error: String) {
                continuation.resume(Result.failure(Exception(error)))
            }

            override fun onSetSuccess() {}
            override fun onSetFailure(error: String) {}
        }, constraints)
    }

    /**
     * Set remote description
     */
    suspend fun setRemoteDescription(description: SessionDescription): Result<Unit> = suspendCancellableCoroutine { continuation ->
        peerConnection?.setRemoteDescription(object : SdpObserver {
            override fun onSetSuccess() {
                continuation.resume(Result.success(Unit))
            }

            override fun onSetFailure(error: String) {
                continuation.resume(Result.failure(Exception(error)))
            }

            override fun onCreateSuccess(sdp: SessionDescription?) {}
            override fun onCreateFailure(error: String?) {}
        }, description)
    }

    /**
     * Set local description
     */
    suspend fun setLocalDescription(description: SessionDescription): Result<Unit> = suspendCancellableCoroutine { continuation ->
        peerConnection?.setLocalDescription(object : SdpObserver {
            override fun onSetSuccess() {
                continuation.resume(Result.success(Unit))
            }

            override fun onSetFailure(error: String) {
                continuation.resume(Result.failure(Exception(error)))
            }

            override fun onCreateSuccess(sdp: SessionDescription?) {}
            override fun onCreateFailure(error: String?) {}
        }, description)
    }

    /**
     * Add ICE candidate
     */
    suspend fun addIceCandidate(candidate: IceCandidate): Result<Unit> = runCatching {
        peerConnection?.addIceCandidate(candidate)
        Unit
    }

    /**
     * Observe ICE candidates
     */
    fun observeIceCandidates(): Flow<IceCandidate> = callbackFlow {
        val job = iceCandidates.collect { candidate ->
            candidate?.let { trySend(it) }
        }
        awaitClose { job.cancel() }
    }

    /**
     * Observe remote media stream
     */
    fun observeRemoteMediaStream(): Flow<MediaStream> = callbackFlow {
        val job = remoteMediaStream.collect { stream ->
            stream?.let { trySend(it) }
        }
        awaitClose { job.cancel() }
    }

    /**
     * Start local media capture
     */
    suspend fun startLocalCapture(): Result<Unit> = runCatching {
        // Create audio track
        val audioSource = peerConnectionFactory?.createAudioSource(MediaConstraints())
        audioTrack = peerConnectionFactory?.createAudioTrack(AUDIO_TRACK_ID, audioSource)

        // Create video capturer
        videoCapturer = createCameraCapturer()
        val videoSource = peerConnectionFactory?.createVideoSource(false)
        videoCapturer?.initialize(
            EglBase.create().eglBaseContext,
            null,
            videoSource?.capturerObserver
        )
        videoCapturer?.startCapture(1280, 720, 30)

        // Create video track
        videoTrack = peerConnectionFactory?.createVideoTrack(VIDEO_TRACK_ID, videoSource)

        // Add tracks to peer connection
        audioTrack?.let { peerConnection?.addTrack(it, listOf("audio")) }
        videoTrack?.let { peerConnection?.addTrack(it, listOf("video")) }

        _connectionState.value = "capturing"
    }

    /**
     * Stop local media capture
     */
    suspend fun stopLocalCapture(): Result<Unit> = runCatching {
        videoCapturer?.stopCapture()
        videoCapturer?.dispose()
        audioTrack?.dispose()
        videoTrack?.dispose()

        videoCapturer = null
        audioTrack = null
        videoTrack = null

        _connectionState.value = "stopped"
    }

    /**
     * Toggle camera
     */
    suspend fun toggleCamera(enabled: Boolean): Result<Unit> = runCatching {
        isCameraEnabled = enabled
        videoTrack?.setEnabled(enabled)
    }

    /**
     * Toggle microphone
     */
    suspend fun toggleMicrophone(enabled: Boolean): Result<Unit> = runCatching {
        isMicrophoneEnabled = enabled
        audioTrack?.setEnabled(enabled)
    }

    /**
     * Switch camera
     */
    suspend fun switchCamera(): Result<Unit> = suspendCancellableCoroutine { continuation ->
        videoCapturer?.switchCamera(object : CameraVideoCapturer.CameraSwitchHandler {
            override fun onCameraSwitchDone(isCameraFront: Boolean) {
                continuation.resume(Result.success(Unit))
            }

            override fun onCameraSwitchError(error: String) {
                continuation.resume(Result.failure(Exception(error)))
            }
        })
    }

    /**
     * Close peer connection and cleanup
     */
    suspend fun close(): Result<Unit> = runCatching {
        stopLocalCapture()
        peerConnection?.close()
        peerConnection?.dispose()
        peerConnectionFactory?.dispose()

        peerConnection = null
        peerConnectionFactory = null

        _connectionState.value = "closed"
    }

    /**
     * Get current connection state
     */
    fun getConnectionState(): String = _connectionState.value

    companion object {
        private const val AUDIO_TRACK_ID = "audio_track"
        private const val VIDEO_TRACK_ID = "video_track"
    }

    /**
     * Create camera video capturer
     */
    private fun createCameraCapturer(): CameraVideoCapturer? {
        val enumerator = Camera2Enumerator(null)
        val deviceNames = enumerator.deviceNames

        for (name in deviceNames) {
            if (enumerator.isFrontFacing(name)) {
                return enumerator.createCapturer(name, null)
            }
        }

        for (name in deviceNames) {
            if (!enumerator.isFrontFacing(name)) {
                return enumerator.createCapturer(name, null)
            }
        }

        return null
    }

    /**
     * Proxy video sink for rendering
     */
    private class ProxyVideoSink : VideoSink {
        private var target: VideoSink? = null

        fun setTarget(sink: VideoSink?) {
            target = sink
        }

        override fun onFrame(frame: VideoFrame) {
            target?.onFrame(frame)
        }
    }
}
