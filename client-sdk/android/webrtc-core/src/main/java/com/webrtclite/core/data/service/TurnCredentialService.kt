package com.webrtclite.core.data.service

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.repository.SignalingRepository
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service for managing TURN server credentials with caching and auto-refresh
 * Provides credentials for NAT traversal in WebRTC
 */
@Singleton
class TurnCredentialService @Inject constructor(
    private val signalingRepository: SignalingRepository
) {
    private val cache = ConcurrentHashMap<String, CachedCredential>()
    private val mutex = Mutex()
    private var refreshJob: kotlinx.coroutines.Job? = null

    companion object {
        private const val REFRESH_BUFFER_MS = 5 * 60 * 1000L // 5 minutes before expiry
        private const val MIN_CHECK_INTERVAL_MS = 60 * 1000L // Check every minute
    }

    private data class CachedCredential(
        val credential: SignalingMessage.TurnCredential,
        val expiresAt: Long,
        val lastRefresh: Long = System.currentTimeMillis()
    ) {
        /**
         * Check if credential needs refresh (5 minutes before expiry)
         */
        fun needsRefresh(): Boolean {
            val now = System.currentTimeMillis()
            return (expiresAt - now) <= REFRESH_BUFFER_MS
        }

        /**
         * Check if credential is expired
         */
        fun isExpired(): Boolean {
            return System.currentTimeMillis() >= expiresAt
        }
    }

    /**
     * Get TURN credentials for a session
     * Returns cached credentials if still valid, fetches new ones otherwise
     */
    suspend fun getCredentials(sessionId: String): Result<SignalingMessage.TurnCredential> {
        // Check cache first
        val cached = cache[sessionId]
        val now = System.currentTimeMillis()

        if (cached != null && cached.expiresAt > now) {
            return Result.success(cached.credential)
        }

        // Fetch new credentials
        return mutex.withLock {
            // Double-check after acquiring lock
            val doubleChecked = cache[sessionId]
            if (doubleChecked != null && doubleChecked.expiresAt > now) {
                return@withLock Result.success(doubleChecked.credential)
            }

            // In production, call Firebase Functions to get TURN credentials
            // For now, return a fallback STUN-only configuration
            val fallbackCredential = createFallbackCredential(sessionId)

            cache[sessionId] = CachedCredential(
                credential = fallbackCredential,
                expiresAt = now + (fallbackCredential.ttl * 1000L)
            )

            Result.success(fallbackCredential)
        }
    }

    /**
     * Create fallback credential using STUN servers only
     * Used when TURN server is not configured
     */
    private fun createFallbackCredential(sessionId: String): SignalingMessage.TurnCredential {
        return SignalingMessage.TurnCredential(
            sessionId = sessionId,
            username = "",
            password = "",
            ttl = 3600, // 1 hour
            urls = listOf(
                "stun:stun.l.google.com:19302",
                "stun:stun1.l.google.com:19302"
            )
        )
    }

    /**
     * Clear cached credentials for a session
     */
    suspend fun clearCache(sessionId: String) {
        cache.remove(sessionId)
    }

    /**
     * Clear all cached credentials
     */
    suspend fun clearAllCache() {
        cache.clear()
    }

    /**
     * Start auto-refresh for cached credentials
     * Checks periodically and refreshes credentials before expiry
     */
    fun startAutoRefresh() {
        if (refreshJob?.isActive == true) {
            return // Already running
        }

        refreshJob = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.Dispatchers.IO).launch {
            while (isActive) {
                delay(MIN_CHECK_INTERVAL_MS)
                refreshExpiringCredentials()
            }
        }
    }

    /**
     * Stop auto-refresh
     */
    fun stopAutoRefresh() {
        refreshJob?.cancel()
        refreshJob = null
    }

    /**
     * Refresh credentials that are about to expire (within 5 minutes)
     */
    private suspend fun refreshExpiringCredentials() {
        val now = System.currentTimeMillis()
        val sessionsToRefresh = mutableListOf<String>()

        // Find credentials that need refresh
        cache.forEach { (sessionId, cached) ->
            if (cached.needsRefresh() && !cached.isExpired()) {
                sessionsToRefresh.add(sessionId)
            }
        }

        // Refresh each credential
        sessionsToRefresh.forEach { sessionId ->
            mutex.withLock {
                val cached = cache[sessionId]
                if (cached != null && cached.needsRefresh()) {
                    try {
                        // Force refresh by removing from cache
                        cache.remove(sessionId)

                        // Get new credential (will be cached)
                        getCredentials(sessionId)
                    } catch (e: Exception) {
                        // Log error but keep using old credential until it expires
                        // Restore old credential if refresh failed
                        cache[sessionId] = cached
                    }
                }
            }
        }

        // Remove expired credentials
        cache.entries.removeIf { (_, cached) ->
            cached.isExpired()
        }
    }

    /**
     * Get time until credential expires (in milliseconds)
     * Returns 0 if credential not found or expired
     */
    fun getTimeToExpiry(sessionId: String): Long {
        val cached = cache[sessionId] ?: return 0
        val now = System.currentTimeMillis()
        return (cached.expiresAt - now).coerceAtLeast(0)
    }

    /**
     * Check if credential for session is cached and valid
     */
    fun isCached(sessionId: String): Boolean {
        val cached = cache[sessionId] ?: return false
        return !cached.isExpired()
    }
}
