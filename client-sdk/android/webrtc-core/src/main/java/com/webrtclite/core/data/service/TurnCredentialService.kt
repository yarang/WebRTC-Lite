package com.webrtclite.core.data.service

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.repository.SignalingRepository
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Service for managing TURN server credentials with caching
 * Provides credentials for NAT traversal in WebRTC
 */
@Singleton
class TurnCredentialService @Inject constructor(
    private val signalingRepository: SignalingRepository
) {
    private val cache = ConcurrentHashMap<String, CachedCredential>()
    private val mutex = Mutex()

    private data class CachedCredential(
        val credential: SignalingMessage.TurnCredential,
        val expiresAt: Long
    )

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
}
