package com.webrtclite.core.data.repository

import com.webrtclite.core.data.model.SignalingMessage
import com.webrtclite.core.data.source.FirestoreDataSource
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Repository interface for WebRTC signaling operations
 */
interface SignalingRepository {
    suspend fun sendOffer(sessionId: String, offer: SignalingMessage.Offer): Result<Unit>
    suspend fun sendAnswer(sessionId: String, answer: SignalingMessage.Answer): Result<Unit>
    suspend fun sendIceCandidate(
        sessionId: String,
        candidateId: String,
        candidate: SignalingMessage.IceCandidate
    ): Result<Unit>
    fun observeOffer(sessionId: String): Flow<SignalingMessage.Offer>
    fun observeAnswer(sessionId: String): Flow<SignalingMessage.Answer>
    fun observeIceCandidates(sessionId: String): Flow<SignalingMessage.IceCandidate>
    suspend fun deleteSession(sessionId: String): Result<Unit>
}

/**
 * Implementation of SignalingRepository using Firestore
 */
@Singleton
class SignalingRepositoryImpl @Inject constructor(
    private val dataSource: FirestoreDataSource
) : SignalingRepository {

    override suspend fun sendOffer(
        sessionId: String,
        offer: SignalingMessage.Offer
    ): Result<Unit> = runCatching {
        dataSource.sendOffer(sessionId, offer)
    }

    override suspend fun sendAnswer(
        sessionId: String,
        answer: SignalingMessage.Answer
    ): Result<Unit> = runCatching {
        dataSource.sendAnswer(sessionId, answer)
    }

    override suspend fun sendIceCandidate(
        sessionId: String,
        candidateId: String,
        candidate: SignalingMessage.IceCandidate
    ): Result<Unit> = runCatching {
        dataSource.sendIceCandidate(sessionId, candidateId, candidate)
    }

    override fun observeOffer(sessionId: String): Flow<SignalingMessage.Offer> {
        return dataSource.observeOffer(sessionId)
    }

    override fun observeAnswer(sessionId: String): Flow<SignalingMessage.Answer> {
        return dataSource.observeAnswer(sessionId)
    }

    override fun observeIceCandidates(sessionId: String): Flow<SignalingMessage.IceCandidate> {
        return dataSource.observeIceCandidates(sessionId)
    }

    override suspend fun deleteSession(sessionId: String): Result<Unit> = runCatching {
        dataSource.deleteSession(sessionId)
    }
}
