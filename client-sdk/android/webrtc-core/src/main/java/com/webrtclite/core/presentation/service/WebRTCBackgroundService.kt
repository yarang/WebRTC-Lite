package com.webrtclite.core.presentation.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import androidx.core.app.NotificationCompat
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Foreground service for maintaining WebRTC connection in background
 * Shows persistent notification and handles background timeout
 */
@AndroidEntryPoint
class WebRTCBackgroundService : Service() {

    @Inject
    lateinit var sessionManager: WebRTCSessionManager

    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(Dispatchers.Main + Job())
    private var timeoutJob: kotlinx.coroutines.Job? = null

    private val _isInForeground = MutableStateFlow(false)
    val isInForeground: StateFlow<Boolean> = _isInForeground.asStateFlow()

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "webrtc_background_channel"
        private const val CHANNEL_NAME = "WebRTC Call"
        private const val BACKGROUND_TIMEOUT_MS = 5 * 60 * 1000L // 5 minutes
        private const val ACTION_STOP = "com.webrtclite.action.STOP"
        private const val ACTION_RESUME = "com.webrtclite.action.RESUME"

        fun startService(context: Context) {
            val intent = Intent(context, WebRTCBackgroundService::class.java)
            context.startForegroundService(intent)
        }

        fun stopService(context: Context) {
            val intent = Intent(context, WebRTCBackgroundService::class.java)
            context.stopService(intent)
        }
    }

    inner class LocalBinder : Binder() {
        fun getService(): WebRTCBackgroundService = this@WebRTCBackgroundService
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder {
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                sessionManager.cleanupSession()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
            ACTION_RESUME -> {
                cancelBackgroundTimeout()
            }
            else -> {
                startForeground(NOTIFICATION_ID, createNotification())
                startBackgroundTimeout()
            }
        }
        return START_STICKY
    }

    /**
     * Start background timeout timer
     * Will cleanup session after 5 minutes in background
     */
    private fun startBackgroundTimeout() {
        cancelBackgroundTimeout()
        timeoutJob = serviceScope.launch {
            delay(BACKGROUND_TIMEOUT_MS)
            // Timeout reached, cleanup session
            sessionManager.cleanupSession()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    /**
     * Cancel background timeout (app returned to foreground)
     */
    private fun cancelBackgroundTimeout() {
        timeoutJob?.cancel()
        timeoutJob = null
    }

    /**
     * Handle app moving to background
     */
    fun onAppBackgrounded() {
        _isInForeground.value = false
        startBackgroundTimeout()
        updateNotification(showWarning = true)
    }

    /**
     * Handle app returning to foreground
     */
    fun onAppForegrounded() {
        _isInForeground.value = true
        cancelBackgroundTimeout()
        updateNotification(showWarning = false)
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Keeps WebRTC connection alive during call"
        }

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.createNotificationChannel(channel)
    }

    private fun createNotification(showWarning: Boolean = false): Notification {
        val stopIntent = Intent(this, WebRTCBackgroundService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val resumeIntent = Intent(this, WebRTCBackgroundService::class.java).apply {
            action = ACTION_RESUME
        }
        val resumePendingIntent = PendingIntent.getService(
            this,
            0,
            resumeIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val contentText = if (showWarning) {
            "Call will end in 5 minutes if you return to app"
        } else {
            "Active call in progress"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("WebRTC Call")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_call)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "End",
                stopPendingIntent
            )
            .build()
    }

    private fun updateNotification(showWarning: Boolean) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, createNotification(showWarning))
    }

    override fun onDestroy() {
        super.onDestroy()
        cancelBackgroundTimeout()
    }
}

/**
 * Session manager for handling WebRTC session lifecycle
 */
interface WebRTCSessionManager {
    fun cleanupSession()
    suspend fun resumeSession(): Result<Unit>
}
