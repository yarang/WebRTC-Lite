package com.webrtclite.core.data.source

import com.google.firebase.firestore.FirebaseFirestore
import com.webrtclite.core.data.model.SignalingMessage
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Firestore data source for WebRTC signaling
 * Handles offer/answer/ICE exchange via Firestore collections
 */
@Singleton
class FirestoreDataSource @Inject constructor(
    private val firestore: FirebaseFirestore
) {
    companion object {
        private const val COLLECTION_SESSIONS = "sessions"
        private const val COLLECTION_SIGNALING = "signaling"
        private const val COLLECTION_ICE_CANDIDATES = "ice_candidates"
        private const val FIELD_OFFER = "offer"
        private const val FIELD_ANSWER = "answer"
    }

    /**
     * Send SDP offer to Firestore
     */
    suspend fun sendOffer(sessionId: String, offer: SignalingMessage.Offer) {
        firestore.collection(COLLECTION_SESSIONS)
            .document(sessionId)
            .set(mapOf(FIELD_OFFER to offer))
            .await()
    }

    /**
     * Send SDP answer to Firestore
     */
    suspend fun sendAnswer(sessionId: String, answer: SignalingMessage.Answer) {
        firestore.collection(COLLECTION_SESSIONS)
            .document(sessionId)
            .set(mapOf(FIELD_ANSWER to answer))
            .await()
    }

    /**
     * Send ICE candidate to Firestore
     */
    suspend fun sendIceCandidate(
        sessionId: String,
        candidateId: String,
        candidate: SignalingMessage.IceCandidate
    ) {
        firestore.collection(COLLECTION_SESSIONS)
            .document(sessionId)
            .collection(COLLECTION_ICE_CANDIDATES)
            .document(candidateId)
            .set(candidate)
            .await()
    }

    /**
     * Observe offer messages for a session
     */
    fun observeOffer(sessionId: String): Flow<SignalingMessage.Offer> = callbackFlow {
        val listener = firestore.collection(COLLECTION_SESSIONS)
            .document(sessionId)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }

                val offer = snapshot?.get(FIELD_OFFER) as? Map<*, *>
                if (offer != null) {
                    trySend(SignalingMessage.Offer(
                        sessionId = offer["sessionId"] as? String ?: "",
                        sdp = offer["sdp"] as? String ?: "",
                        callerId = offer["callerId"] as? String ?: "",
                        timestamp = offer["timestamp"] as? Long ?: System.currentTimeMillis()
                    ))
                }
            }

        awaitClose { listener.remove() }
    }

    /**
     * Observe answer messages for a session
     */
    fun observeAnswer(sessionId: String): Flow<SignalingMessage.Answer> = callbackFlow {
        val listener = firestore.collection(COLLECTION_SESSIONS)
            .document(sessionId)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }

                val answer = snapshot?.get(FIELD_ANSWER) as? Map<*, *>
                if (answer != null) {
                    trySend(SignalingMessage.Answer(
                        sessionId = answer["sessionId"] as? String ?: "",
                        sdp = answer["sdp"] as? String ?: "",
                        calleeId = answer["calleeId"] as? String ?: "",
                        timestamp = answer["timestamp"] as? Long ?: System.currentTimeMillis()
                    ))
                }
            }

        awaitClose { listener.remove() }
    }

    /**
     * Observe ICE candidates for a session
     */
    fun observeIceCandidates(sessionId: String): Flow<SignalingMessage.IceCandidate> = callbackFlow {
        val listener = firestore.collection(COLLECTION_SESSIONS)
            .document(sessionId)
            .collection(COLLECTION_ICE_CANDIDATES)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }

                snapshot?.documents?.forEach { doc ->
                    val data = doc.data
                    if (data != null) {
                        trySend(SignalingMessage.IceCandidate(
                            sessionId = data["sessionId"] as? String ?: "",
                            sdpMid = data["sdpMid"] as? String ?: "",
                            sdpMLineIndex = (data["sdpMLineIndex"] as? Number)?.toInt() ?: 0,
                            sdpCandidate = data["sdpCandidate"] as? String ?: "",
                            timestamp = data["timestamp"] as? Long ?: System.currentTimeMillis()
                        ))
                    }
                }
            }

        awaitClose { listener.remove() }
    }

    /**
     * Delete session and all associated data
     */
    suspend fun deleteSession(sessionId: String) {
        firestore.collection(COLLECTION_SESSIONS)
            .document(sessionId)
            .delete()
            .await()
    }
}
